-- Language server definitions: which server exists, what command starts it,
-- which root it belongs to and which settings it gets. Enabling is deliberately
-- not part of this module, so the same definitions serve full mode's automatic
-- clients and fast mode's single on-request client without either having to
-- load the other's wiring.

local M = {}
local toolchain = require("user.toolchain")

M.servers = toolchain.lsp_servers

-- Servers that assist a primary one (spelling, linting, class name completion)
-- rather than owning a language. A manual start offers these only when asked
-- for by name, so one request cannot bring up three clients.
M.auxiliary = {
	biome = true,
	emmet_language_server = true,
	ruff = true,
	tailwindcss = true,
	typos_lsp = true,
}

---Optional project servers require evidence of that tool in standard mode.
---Package dependencies cover Tailwind v4 projects without tailwind.config.*.
function M.project_configured(server, bufnr)
	local markers = server == "biome" and { "biome.json", "biome.jsonc" }
		or {
			"tailwind.config.js",
			"tailwind.config.cjs",
			"tailwind.config.mjs",
			"tailwind.config.ts",
			"tailwind.config.cts",
			"tailwind.config.mts",
		}
	if vim.fs.root(bufnr, markers) then
		return true
	end
	if server ~= "tailwindcss" then
		return false
	end
	local file = vim.api.nvim_buf_get_name(bufnr)
	local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
	while dir do
		local path = vim.fs.joinpath(dir, "package.json")
		if vim.uv.fs_stat(path) then
			local ok, package = pcall(function()
				return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
			end)
			if ok and type(package) == "table" then
				for _, section in ipairs({ "dependencies", "devDependencies", "peerDependencies" }) do
					if type(package[section]) == "table" and package[section].tailwindcss then
						return true
					end
				end
			end
		end
		if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then
			break
		end
		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end
	return false
end

local configured = false
local original_commands = {}
local node_commands = {}

-- Servers that can analyse the whole project do so only in a mode that
-- accepts the background cost, and only below a size the host accepts.
local skipped_directories = {
	[".git"] = true,
	[".jj"] = true,
	[".cache"] = true,
	[".mypy_cache"] = true,
	[".ruff_cache"] = true,
	[".venv"] = true,
	venv = true,
	node_modules = true,
	target = true,
	dist = true,
	build = true,
	__pycache__ = true,
}

---Decisions taken for `:checkhealth user`, keyed by server and root.
M.workspace_decisions = {}

---Whether `server` should analyse all of `root`. Counts source files with the
---given extensions, skipping dependency and build directories, up to the host
---limit; the walk stops as soon as the limit is exceeded.
---@param root string|nil
---@param extensions table<string, true>
---@param server string
---@return boolean enabled, integer files
function M.workspace_scope(root, extensions, server)
	local limit = require("user.core.preferences").get("runtime").workspace_diagnostics_max_files
	local allowed = require("user.core.mode").capabilities().workspace_diagnostics
	local count = 0
	if allowed and root then
		for name, kind in
			vim.fs.dir(root, {
				depth = 32,
				skip = function(directory)
					return not skipped_directories[vim.fs.basename(directory)]
				end,
			})
		do
			if kind == "file" and extensions[name:match("%.([^.]+)$") or ""] then
				count = count + 1
				if count > limit then
					break
				end
			end
		end
	end
	local enabled = allowed and root ~= nil and count <= limit
	M.workspace_decisions[server .. "\0" .. tostring(root)] = {
		server = server,
		root = root,
		files = count,
		limit = limit,
		enabled = enabled,
		reason = not allowed and "mode keeps servers in open-files mode"
			or (count > limit and ("more than " .. limit .. " source files"))
			or nil,
	}
	return enabled, count
end

-- The client keeps a reference to the settings table it was created with, so
-- before_init has to change that table in place; replacing it would leave
-- workspace/configuration answering from the original.
---Whether a published diagnostic belongs to the project: files under the
---root and outside node_modules, plus anything the user has actually opened.
---Project-wide analysis otherwise reports TypeScript's own lib files and
---vendored packages, which would drown the workspace counts.
---@param root string|nil
---@param path string
---@param loaded boolean
function M.project_diagnostic(root, path, loaded)
	if loaded then
		return true
	end
	path = vim.fs.normalize(path)
	if path:find("/node_modules/", 1, true) then
		return false
	end
	if not root then
		return true
	end
	root = vim.fs.normalize(root)
	return path == root or vim.startswith(path, root .. "/")
end

local function project_only_diagnostics(err, result, ctx)
	if result and result.uri then
		local client = vim.lsp.get_client_by_id(ctx.client_id)
		local path = vim.uri_to_fname(result.uri)
		if not M.project_diagnostic(client and client.root_dir, path, vim.fn.bufloaded(path) == 1) then
			return
		end
	end
	return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx)
end

local function extend_settings(config, settings)
	if type(config.settings) ~= "table" then
		config.settings = settings
		return
	end
	for key, value in pairs(vim.tbl_deep_extend("force", config.settings, settings)) do
		config.settings[key] = value
	end
end

local function node_lsp_command(name, args)
	return function(dispatchers, config)
		local root = (config or {}).root_dir
		local command = toolchain.node_executable(name, root) or name
		return vim.lsp.rpc.start(vim.list_extend({ command }, args), dispatchers)
	end
end

---Install every server definition exactly once. `capabilities` is whatever the
---caller's completion stack advertises; fast mode passes Neovim's own.
---@param opts table|nil { capabilities = table }
function M.configure(opts)
	if configured then
		return
	end
	configured = true
	local capabilities = (opts or {}).capabilities or vim.lsp.protocol.make_client_capabilities()

	vim.lsp.config("*", {
		capabilities = capabilities,
	})

	vim.lsp.config("asm_lsp", {
		filetypes = { "asm", "riscv", "vmasm" },
	})

	vim.lsp.config("clangd", {
		cmd = {
			"clangd",
			"--log=error",
			"--background-index",
			"--clang-tidy",
			"--completion-style=detailed",
			"--header-insertion=iwyu",
			"--header-insertion-decorators",
			"--fallback-style=llvm",
		},
		init_options = {
			clangdFileStatus = true,
			completeUnimported = true,
			usePlaceholders = true,
		},
	})

	vim.lsp.config("gopls", {
		settings = {
			gopls = {
				analyses = {
					nilness = true,
					shadow = true,
					unusedparams = true,
					unusedwrite = true,
				},
				gofumpt = true,
				staticcheck = true,
			},
		},
	})

	vim.lsp.config("lua_ls", {
		settings = {
			Lua = {
				completion = {
					callSnippet = "Replace",
				},
				diagnostics = {
					globals = { "vim", "Snacks", "MiniIcons" },
				},
				runtime = {
					version = "LuaJIT",
				},
				workspace = {
					checkThirdParty = false,
				},
			},
		},
	})

	vim.lsp.config("basedpyright", {
		settings = {
			basedpyright = {
				analysis = {
					autoImportCompletions = true,
				},
			},
		},
		before_init = function(params, config)
			if M.workspace_scope(config.root_dir, { py = true, pyi = true }, "basedpyright") then
				extend_settings(config, {
					python = { analysis = { diagnosticMode = "workspace" } },
					basedpyright = { analysis = { diagnosticMode = "workspace" } },
				})
				-- A client that advertises pull diagnostics is served on request
				-- only, and Neovim pulls per document: the unopened files of the
				-- workspace would never be reported. Withhold the capability so
				-- the server pushes for every tracked file instead.
				if params.capabilities and params.capabilities.textDocument then
					params.capabilities.textDocument.diagnostic = nil
				end
			end
		end,
	})

	vim.lsp.config("biome", {
		cmd = node_lsp_command("biome", { "lsp-proxy" }),
	})

	vim.lsp.config("sqlls", {
		-- Keep database completion; its generic SQL parser rejects psql
		-- commands such as \echo and \dt. Sqruff owns PostgreSQL diagnostics.
		handlers = {
			["textDocument/publishDiagnostics"] = function() end,
		},
	})

	vim.lsp.config("typos_lsp", {
		-- Prose uses Neovim's spell checker. Restrict typos-lsp to code and
		-- structured data so the two systems do not duplicate diagnostics.
		filetypes = {
			"asm",
			"bash",
			"c",
			"cmake",
			"cpp",
			"css",
			"dockerfile",
			"gitconfig",
			"gitignore",
			"go",
			"gomod",
			"gosum",
			"gowork",
			"html",
			"hyprlang",
			"java",
			"javascript",
			"javascriptreact",
			"json",
			"jsonc",
			"lua",
			"make",
			"nasm",
			"python",
			"query",
			"riscv",
			"rust",
			"sh",
			"sql",
			"systemverilog",
			"toml",
			"typescript",
			"typescriptreact",
			"verilog",
			"vim",
			"vue",
			"yaml",
			"zsh",
		},
		init_options = {
			-- Surface typos quietly; they are hints, not errors.
			diagnosticSeverity = "Hint",
		},
	})

	vim.lsp.config("verible", {
		cmd = { "verible-verilog-ls", "--rules_config_search" },
		filetypes = { "systemverilog", "verilog" },
		root_markers = { ".git" },
	})

	local function vue_language_server_path()
		local executable = toolchain.executable("vue-language-server")
		local realpath = executable and (vim.uv.fs_realpath(executable) or executable)
		local package = realpath and vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(realpath)))
		if package and vim.uv.fs_stat(vim.fs.joinpath(package, "package.json")) then
			return package
		end

		-- Windows Mason shims are regular .cmd files rather than symlinks, so
		-- their realpath cannot reveal the npm package directory.
		local mason_package = vim.fs.joinpath(
			vim.fn.stdpath("data"),
			"mason",
			"packages",
			"vue-language-server",
			"node_modules",
			"@vue",
			"language-server"
		)
		return vim.uv.fs_stat(vim.fs.joinpath(mason_package, "package.json")) and mason_package or nil
	end

	local vue_plugin = vue_language_server_path()
	local vtsls_filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
	}
	local vtsls_settings = {}
	if vue_plugin then
		table.insert(vtsls_filetypes, "vue")
		vtsls_settings.tsserver = {
			globalPlugins = {
				{
					name = "@vue/typescript-plugin",
					location = vue_plugin,
					languages = { "vue" },
					configNamespace = "typescript",
				},
			},
		}
	end
	vim.lsp.config("vtsls", {
		filetypes = vtsls_filetypes,
		settings = {
			vtsls = vtsls_settings,
		},
		handlers = {
			["textDocument/publishDiagnostics"] = project_only_diagnostics,
		},
		before_init = function(_, config)
			local sources = {
				ts = true,
				tsx = true,
				mts = true,
				cts = true,
				js = true,
				jsx = true,
				mjs = true,
				cjs = true,
				vue = true,
			}
			if M.workspace_scope(config.root_dir, sources, "vtsls") then
				extend_settings(config, {
					typescript = { tsserver = { experimental = { enableProjectDiagnostics = true } } },
				})
			end
		end,
	})

	vim.lsp.config("jsonls", {
		settings = {
			json = {
				validate = { enable = true },
			},
		},
	})

	vim.lsp.config("yamlls", {
		settings = {
			yaml = {
				keyOrdering = false,
			},
		},
	})

	vim.lsp.config("tailwindcss", {
		cmd = node_lsp_command("tailwindcss-language-server", { "--stdio" }),
		filetypes = {
			"astro",
			"css",
			"html",
			"javascript",
			"javascriptreact",
			"typescript",
			"typescriptreact",
			"vue",
		},
	})

	-- nvim-lspconfig defaults use command names. Resolve each command to an
	-- absolute system-or-Mason path so Mason can keep PATH="skip".
	local custom_node_commands = { biome = "biome", tailwindcss = "tailwindcss-language-server" }
	for _, server in ipairs(M.servers) do
		local config = vim.lsp.config[server]
		if config then
			local policy = require("user.core.buffer_policy")
			local command = config.cmd
			local node_name = custom_node_commands[server]
			if type(command) == "table" and toolchain.node_commands[command[1]] then
				node_name = command[1]
				command = node_lsp_command(node_name, vim.list_slice(command, 2))
			end
			original_commands[server] = vim.deepcopy(command)
			node_commands[server] = node_name
			local root = policy.lsp_root(config)
			if node_name then
				local guarded_root = root
				root = function(bufnr, on_dir)
					local selected = toolchain.node_resolve(node_name, bufnr)
					if not selected.path then
						return
					end
					guarded_root(bufnr, function(directory)
						if selected.source == "project" and directory then
							local package_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(selected.path)))
							if require("user.core.project").contains(directory, package_root) then
								-- Separate package-local tool versions into separate clients.
								directory = package_root
							end
						end
						on_dir(directory)
					end)
				end
			elseif type(command) == "table" and type(command[1]) == "string" then
				local guarded_root = root
				local executable_name = command[1]
				root = function(bufnr, on_dir)
					if toolchain.executable(executable_name, { bufnr = bufnr }) then
						guarded_root(bufnr, on_dir)
					end
				end
			end
			if
				require("user.core.mode").capabilities().lsp_auto
				and not require("user.core.mode").capabilities().auxiliary_lsp
				and (server == "biome" or server == "tailwindcss")
			then
				local guarded_root = root
				root = function(bufnr, on_dir)
					if M.project_configured(server, bufnr) then
						guarded_root(bufnr, on_dir)
					end
				end
			end
			vim.lsp.config(server, { cmd = command, root_dir = root, on_init = policy.lsp_init(config.on_init) })
		end
	end
end

---Point every definition at the executable installed right now and return the
---servers that can actually start. The caller decides whether to enable them
---automatically or to start one of them on request.
function M.resolve(opts)
	M.configure()
	local ready = {}
	for _, server in ipairs(M.servers) do
		local automatic = not (opts and opts.automatic)
			or require("user.core.mode").capabilities().auxiliary_lsp
			or (server ~= "typos_lsp" and server ~= "emmet_language_server")
		local cmd = automatic and original_commands[server] or nil
		if type(cmd) == "table" and type(cmd[1]) == "string" then
			local resolved = toolchain.executable(cmd[1])
			if resolved then
				cmd = vim.deepcopy(cmd)
				cmd[1] = resolved
				vim.lsp.config(server, { cmd = cmd })
				table.insert(ready, server)
			end
		elseif type(cmd) == "function" then
			-- Full mode registers definitions for future project-local tools.
			-- A manual picker must list only tools available to this buffer now.
			local executable = node_commands[server]
			if not (opts and opts.installed_only) or not executable or toolchain.node_executable(executable) then
				table.insert(ready, server)
			end
		end
	end
	return ready
end

return M
