local toolchain = require("user.toolchain")
local float_style = require("user.core.float_style")

local function executable(name)
	return toolchain.executable(name)
end

local function missing_adapter(package)
	vim.notify(
		("Debug adapter %q is unavailable. Run :MasonToolsInstall or install it from :Mason."):format(package),
		vim.log.levels.ERROR,
		{ title = "DAP" }
	)
end

local function missing_runtime(runtime, context)
	vim.notify(("%s debugging requires %q on PATH."):format(context, runtime), vim.log.levels.ERROR, { title = "DAP" })
end

local function debugpy_python()
	return toolchain.debugpy_host().path
end

local adapter_by_filetype = {
	c = { command = "codelldb", package = "codelldb" },
	cpp = { command = "codelldb", package = "codelldb" },
	go = { command = "dlv", package = "delve", plugin = "nvim-dap-go" },
	python = { check = debugpy_python, package = "debugpy", plugin = "nvim-dap-python" },
	javascript = { command = "js-debug-adapter", package = "js-debug-adapter", plugin = "nvim-dap-vscode-js" },
	javascriptreact = { command = "js-debug-adapter", package = "js-debug-adapter", plugin = "nvim-dap-vscode-js" },
	typescript = { command = "js-debug-adapter", package = "js-debug-adapter", plugin = "nvim-dap-vscode-js" },
	typescriptreact = { command = "js-debug-adapter", package = "js-debug-adapter", plugin = "nvim-dap-vscode-js" },
	vue = { command = "js-debug-adapter", package = "js-debug-adapter", plugin = "nvim-dap-vscode-js" },
}

local function adapter_executable(requirement)
	if requirement.runtime and not executable(requirement.runtime) then
		missing_runtime(requirement.runtime, requirement.label or requirement.package)
		return nil
	end
	local available
	if requirement.check then
		available = requirement.check()
	else
		available = executable(requirement.command)
	end
	if not available then
		missing_adapter(requirement.package)
		return nil
	end
	return available
end

local function debug_continue()
	local requirement = adapter_by_filetype[vim.bo.filetype]
	if requirement then
		if not adapter_executable(requirement) then
			return
		end
		if requirement.plugin then
			require("lazy").load({ plugins = { requirement.plugin } })
		end
	end
	require("dap").continue()
end

local function load_dap_ui(open)
	pcall(function()
		require("lazy").load({ plugins = { "nvim-dap-ui", "nvim-dap-virtual-text" } })
	end)
	if open then
		local ok, dapui = pcall(require, "dapui")
		if ok then
			dapui.open()
		end
	end
end

return {
	{
		"mfussenegger/nvim-dap",
		keys = {
			{ "<F5>", debug_continue, desc = "Debug: continue / start" },
			{
				"<F10>",
				function()
					require("dap").step_over()
				end,
				desc = "Debug: step over",
			},
			{
				"<F11>",
				function()
					require("dap").step_into()
				end,
				desc = "Debug: step into",
			},
			{
				"<S-F11>",
				function()
					require("dap").step_out()
				end,
				desc = "Debug: step out",
			},
			{ "<leader>dc", debug_continue, desc = "Continue / start" },
			{
				"<leader>dC",
				function()
					require("dap").run_to_cursor()
				end,
				desc = "Run to cursor",
			},
			{
				"<leader>db",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = "Toggle breakpoint",
			},
			{
				"<leader>dB",
				function()
					require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
				end,
				desc = "Conditional breakpoint",
			},
			{
				"<leader>di",
				function()
					require("dap").step_into()
				end,
				desc = "Step into",
			},
			{
				"<leader>do",
				function()
					require("dap").step_over()
				end,
				desc = "Step over",
			},
			{
				"<leader>dO",
				function()
					require("dap").step_out()
				end,
				desc = "Step out",
			},
			{
				"<leader>dr",
				function()
					require("dap").repl.toggle()
				end,
				desc = "Toggle REPL",
			},
			{
				"<leader>dl",
				function()
					require("dap").run_last()
				end,
				desc = "Run last",
			},
			{
				"<leader>dt",
				function()
					require("dap").terminate()
				end,
				desc = "Terminate",
			},
		},
		config = function()
			local dap = require("dap")

			dap.adapters.codelldb = function(callback)
				local command = adapter_executable(adapter_by_filetype.c)
				if not command then
					return
				end
				callback({
					type = "server",
					port = "${port}",
					executable = { command = command, args = { "--port", "${port}" } },
				})
			end

			local cpp = {
				{
					name = "Launch executable (codelldb)",
					type = "codelldb",
					request = "launch",
					program = function()
						return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
				},
				{
					name = "Attach to process",
					type = "codelldb",
					request = "attach",
					pid = require("dap.utils").pick_process,
					cwd = "${workspaceFolder}",
				},
			}
			dap.configurations.c = cpp
			dap.configurations.cpp = cpp

			dap.listeners.after.event_initialized["user_dap_ui"] = function()
				load_dap_ui(true)
			end
			local function close_ui()
				local dapui = package.loaded.dapui
				if dapui then
					dapui.close()
				end
			end
			dap.listeners.before.event_terminated["user_dap_ui"] = close_ui
			dap.listeners.before.event_exited["user_dap_ui"] = close_ui

			vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", numhl = "" })
			vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", numhl = "" })
			vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "Visual", numhl = "" })
			vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticHint", numhl = "" })
		end,
	},
	{
		"rcarriga/nvim-dap-ui",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
		opts = {
			floating = {
				border = float_style.border(),
			},
		},
		keys = {
			{
				"<leader>du",
				function()
					require("dapui").toggle()
				end,
				desc = "Toggle DAP UI",
			},
			{
				"<leader>de",
				function()
					require("dapui").eval()
				end,
				mode = { "n", "x" },
				desc = "Eval expression",
			},
		},
	},
	{
		"theHamsta/nvim-dap-virtual-text",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		opts = { commented = true },
	},
	{
		"jay-babu/mason-nvim-dap.nvim",
		cmd = { "DapInstall", "DapUninstall" },
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = {},
			automatic_installation = false,
		},
	},
	{
		"leoluz/nvim-dap-go",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local delve = adapter_executable(adapter_by_filetype.go)
			if not delve then
				return
			end
			require("dap-go").setup({ delve = { path = delve } })
		end,
	},
	{
		"mfussenegger/nvim-dap-python",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local python = adapter_executable(adapter_by_filetype.python)
			if not python then
				return
			end
			local function target_python()
				return toolchain.python_executable()
			end
			require("dap-python").setup(python, { pythonPath = target_python })
			local dap = require("dap")
			local adapter = dap.adapters.python
			local function resolve_adapter(callback, config)
				local host = debugpy_python()
				if not host then
					missing_adapter("debugpy")
					return
				end
				if host ~= python then
					-- Refresh the host for this launch without rebuilding the user's
					-- configurations or changing a currently running debug session.
					require("dap-python").setup(host, { include_configs = false })
					adapter, python = dap.adapters.python, host
					dap.adapters.python, dap.adapters.debugpy = resolve_adapter, resolve_adapter
				end
				adapter(function(resolved)
					local enrich = resolved.enrich_config
					resolved.enrich_config = function(configuration, on_config)
						if
							configuration.request == "launch"
							and not configuration.pythonPath
							and not configuration.python
						then
							local source = type(configuration.program) == "string"
									and not configuration.program:find("${", 1, true)
									and configuration.program
								or nil
							configuration.pythonPath = toolchain.python_executable(source)
						end
						enrich(configuration, on_config)
					end
					callback(resolved)
				end, config)
			end
			dap.adapters.python = resolve_adapter
			dap.adapters.debugpy = resolve_adapter
		end,
	},
	{
		"mxsdev/nvim-dap-vscode-js",
		lazy = true,
		dependencies = { "mfussenegger/nvim-dap" },
		config = function()
			local command = adapter_executable(adapter_by_filetype.javascript)
			if not command then
				return
			end
			require("dap-vscode-js").setup({
				debugger_cmd = { command },
				adapters = { "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" },
			})

			local dap = require("dap")
			local node_launch = {
				{
					name = "Launch current JavaScript file",
					type = "pwa-node",
					request = "launch",
					program = "${file}",
					cwd = "${workspaceFolder}",
					sourceMaps = true,
					console = "integratedTerminal",
				},
			}
			local node_attach = {
				{
					name = "Attach to Node process",
					type = "pwa-node",
					request = "attach",
					processId = require("dap.utils").pick_process,
					cwd = "${workspaceFolder}",
					sourceMaps = true,
				},
			}
			local browser_attach = {
				{
					name = "Attach Chrome on :9222",
					type = "pwa-chrome",
					request = "attach",
					port = 9222,
					webRoot = "${workspaceFolder}",
					sourceMaps = true,
				},
			}

			local javascript = vim.list_extend(vim.deepcopy(node_launch), vim.deepcopy(node_attach))
			vim.list_extend(javascript, vim.deepcopy(browser_attach))
			dap.configurations.javascript = javascript
			local attach_only = vim.list_extend(vim.deepcopy(node_attach), vim.deepcopy(browser_attach))
			dap.configurations.javascriptreact = vim.deepcopy(attach_only)
			dap.configurations.typescript = vim.deepcopy(attach_only)
			dap.configurations.typescriptreact = vim.deepcopy(attach_only)
			dap.configurations.vue = vim.deepcopy(browser_attach)
		end,
	},
}
