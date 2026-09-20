-- Manual definitions supplement the full-mode catalog without enabling the
-- Java/Rust integrations, debuggers, or automatic clients.
local shared = require("user.core.lsp_definitions")
local toolchain = require("user.toolchain")
local M = {
	servers = vim.list_extend(vim.deepcopy(shared.servers), { "jdtls", "rust_analyzer" }),
	auxiliary = shared.auxiliary,
}
local configured = false

local function configure()
	if configured then
		return
	end
	configured = true
	local policy = require("user.core.buffer_policy")
	vim.lsp.config("rust_analyzer", {
		root_dir = function(bufnr, on_dir)
			if policy.allow(bufnr) then
				on_dir(vim.fs.root(bufnr, { "Cargo.toml", "rust-project.json", ".git" }))
			end
		end,
		settings = {
			["rust-analyzer"] = {
				checkOnSave = false,
				cargo = { buildScripts = { enable = false } },
				procMacro = { enable = false },
				lens = { enable = false },
			},
		},
	})
	vim.lsp.config("jdtls", {
		root_dir = function(bufnr, on_dir)
			if policy.allow(bufnr) then
				on_dir(require("user.core.java").project_root(bufnr))
			end
		end,
		cmd = function(dispatchers, config)
			local java = require("user.core.java")
			local executable, reason = java.runtime()
			assert(executable, reason)
			local root = config.root_dir or vim.fn.getcwd()
			-- Keep two projects with the same basename out of the same workspace.
			local workspace = vim.fs.joinpath(vim.fn.stdpath("cache"), "jdtls", vim.fn.sha256(root):sub(1, 16))
			local command = {
				assert(toolchain.executable("jdtls"), "Install jdtls first"),
				"--java-executable",
				executable,
				"-data",
				workspace,
			}
			for argument in (vim.env.JDTLS_JVM_ARGS or ""):gmatch("%S+") do
				table.insert(command, "--jvm-arg=" .. argument)
			end
			return vim.lsp.rpc.start(command, dispatchers, { cwd = root })
		end,
		init_options = { bundles = {} },
	})
end

function M.resolve()
	local ready = shared.resolve({ installed_only = true })
	configure()
	for name, command in pairs({ rust_analyzer = "rust-analyzer", jdtls = "jdtls" }) do
		local executable = toolchain.executable(command)
		if executable then
			if name == "rust_analyzer" then
				vim.lsp.config(name, { cmd = { executable } })
			end
			table.insert(ready, name)
		end
	end
	return ready
end

return M
