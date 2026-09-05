return function(tmp)
	do
		local base = tmp .. "/root/project"
		vim.fn.mkdir(base .. "/module/src", "p")
		vim.fn.mkdir(base .. "/.git", "p")
		vim.fn.writefile({}, base .. "/module/pom.xml")
		assert(
			require("user.core.java").project_root(base .. "/module/src/Main.java") == base .. "/module",
			"nested Java root was ignored"
		)
	end

	do
		local lazy = require("lazy")
		local before = vim.env.PATH
		lazy.load({ plugins = { "nvim-lspconfig" } })
		assert(vim.env.PATH == before, "LSP changed PATH")
		assert(not package.loaded.mason and not package.loaded["mason-registry"], "ordinary LSP load started Mason")
		local attach = vim.api.nvim_get_autocmds({ group = "user_lsp_attach", event = "LspAttach" })[1]
		assert(attach and type(attach.callback) == "function", "LSP attach callback is missing")
		local keymap_buffer = vim.api.nvim_create_buf(false, true)
		attach.callback({ buf = keymap_buffer, data = { client_id = -1 } })
		local lsp_keymaps = {}
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(keymap_buffer, "n")) do
			lsp_keymaps[mapping.lhs] = mapping.rhs
		end
		for lhs, command in pairs({
			gd = "definitions",
			gD = "declarations",
			gi = "implementations",
			gy = "type_definitions",
			gr = "references",
			[" cpd"] = "definitions",
			[" cpD"] = "declarations",
			[" cpi"] = "implementations",
			[" cpt"] = "type_definitions",
			[" cpr"] = "references",
		}) do
			assert(lsp_keymaps[lhs] == "<Cmd>Glance " .. command .. "<CR>", lhs .. " no longer uses Glance")
		end
		vim.api.nvim_buf_delete(keymap_buffer, { force = true })
		for _, server in ipairs(require("user.toolchain").lsp_servers) do
			local config = vim.lsp.config[server]
			assert(type(config) == "table", "missing LSP config: " .. server)
			assert(type(config.filetypes) == "table" and #config.filetypes > 0, "LSP has no filetypes: " .. server)
		end
		local rpc_start = vim.lsp.rpc.start
		local ok_commands, web_commands = pcall(function()
			vim.lsp.rpc.start = function(command)
				return command
			end
			local config = { root_dir = tmp .. "/web-lsp-command-audit" }
			return {
				biome = vim.lsp.config.biome.cmd({}, config),
				tailwindcss = vim.lsp.config.tailwindcss.cmd({}, config),
			}
		end)
		vim.lsp.rpc.start = rpc_start
		assert(ok_commands, "Web LSP command resolution failed: " .. tostring(web_commands))
		local web_command_specs = {
			biome = { executable = "biome", argument = "lsp-proxy" },
			tailwindcss = { executable = "tailwindcss-language-server", argument = "--stdio" },
		}
		local toolchain = require("user.toolchain")
		for server, spec in pairs(web_command_specs) do
			local resolved = toolchain.executable(spec.executable)
			assert(
				not resolved or web_commands[server][1] == resolved,
				server .. " did not resolve its Mason/system binary"
			)
			assert(web_commands[server][2] == spec.argument, server .. " lost its LSP transport argument")
		end

		local vue = require("user.toolchain").executable("vue-language-server")
		if vue then
			local plugins = vim.lsp.config.vtsls.settings.vtsls.tsserver.globalPlugins
			assert(
				plugins and vim.uv.fs_stat(plugins[1].location .. "/package.json"),
				"vtsls has an invalid Vue plugin path"
			)
		end

		lazy.load({ plugins = { "nvim-jdtls" } })
		assert(not package.loaded.mason and not package.loaded["mason-registry"], "Java support started Mason")
		assert(not package.loaded.dap, "nvim-dap loaded before Java debugging")

		lazy.load({ plugins = { "rustaceanvim" } })
		assert(vim.g.rustaceanvim.dap.autoload_configurations == false, "Rust DAP still autoloads on LSP attach")
		assert(not package.loaded.dap, "nvim-dap loaded before Rust debugging")
		local codelldb = require("user.toolchain").executable("codelldb")
		if codelldb then
			assert(
				vim.g.rustaceanvim.dap.adapter().executable.command == codelldb,
				"Rust DAP did not resolve codelldb by absolute path"
			)
		end
		vim.lsp.enable(require("user.toolchain").lsp_servers, false)
	end

	do
		require("lazy").load({ plugins = { "nvim-dap" } })
		local dap = require("dap")
		assert(type(dap.adapters.codelldb) == "function", "codelldb adapter is missing")
		assert(#(dap.configurations.c or {}) >= 2, "C launch/attach configurations are missing")
		assert(#(dap.configurations.cpp or {}) >= 2, "C++ launch/attach configurations are missing")
	end

	do
		require("lazy").load({ plugins = { "nvim-lint" } })
		local lint = require("lint")
		for filetype, names in pairs(lint.linters_by_ft) do
			for _, name in ipairs(names) do
				assert(lint.linters[name] ~= nil, ("unknown linter %s for %s"):format(name, filetype))
			end
		end
	end

	do
		local base = tmp .. "/tests"
		vim.fn.mkdir(base .. "/python", "p")
		vim.fn.writefile({}, base .. "/python/pyproject.toml")
		vim.fn.writefile({ "def test_ok():", "    assert True" }, base .. "/python/test_ok.py")
		vim.fn.mkdir(base .. "/go", "p")
		vim.fn.writefile({ "module example.test", "", "go 1.24" }, base .. "/go/go.mod")
		vim.fn.writefile({ "package example" }, base .. "/go/example_test.go")

		require("lazy").load({ plugins = { "neotest" } })
		local testing = require("user.core.testing")
		local python_buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(python_buffer, base .. "/python/test_ok.py")
		vim.api.nvim_set_current_buf(python_buffer)
		vim.bo[python_buffer].filetype = "python"
		assert(testing.prepare(), "Python test adapter unavailable")
		local consumer = require("neotest").run

		local go_buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(go_buffer, base .. "/go/example_test.go")
		vim.api.nvim_set_current_buf(go_buffer)
		vim.bo[go_buffer].filetype = "go"
		assert(testing.prepare(), "Go test adapter unavailable")
		assert(require("neotest").run == consumer, "Neotest client was replaced while adding an adapter")
		assert(not package.loaded["neotest-jest"], "unrelated test adapter was loaded")
		assert(not package.loaded["neotest-vitest"], "unrelated test adapter was loaded")
		vim.api.nvim_buf_delete(go_buffer, { force = true })
		vim.api.nvim_buf_delete(python_buffer, { force = true })
	end
end
