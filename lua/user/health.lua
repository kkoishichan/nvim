local M = {}

local executable_names = {
	["css-lsp"] = "vscode-css-language-server",
	["html-lsp"] = "vscode-html-language-server",
	["json-lsp"] = "vscode-json-language-server",
	["lua-language-server"] = "lua-language-server",
	["sqlls"] = "sql-language-server",
	["verible"] = "verible-verilog-ls",
	["cmakelang"] = "cmake-format",
	["delve"] = "dlv",
	["debugpy"] = "debugpy-adapter",
	["dockerfile-language-server"] = "docker-langserver",
}
local java_artifacts = {
	["java-debug-adapter"] = "java-debug-adapter/com.microsoft.java.debug.plugin.jar",
	["java-test"] = "java-test/com.microsoft.java.test.plugin.jar",
}
-- Only use documented version flags. Servers without a version CLI still get
-- their exact installed Mason receipt and the configured restore version.
local version_flags = {
	git = { "--version" },
	fzf = { "--version" },
	rg = { "--version" },
	fd = { "--version" },
	node = { "--version" },
	python = { "--version" },
	python3 = { "--version" },
	java = { "-version" },
	go = { "version" },
	rustc = { "--version" },
	ruff = { "--version" },
	stylua = { "--version" },
	biome = { "--version" },
	prettier = { "--version" },
	stylelint = { "--version" },
	shellcheck = { "--version" },
	shfmt = { "--version" },
	clangd = { "--version" },
	["clang-format"] = { "--version" },
	["rust-analyzer"] = { "--version" },
	basedpyright = { "--version" },
	sqruff = { "--version" },
	typstyle = { "--version" },
}

local function installed_version(package)
	local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", package, "mason-receipt.json")
	local ok_read, lines = pcall(vim.fn.readfile, path)
	if not ok_read then
		return nil
	end
	local ok, receipt = pcall(vim.json.decode, table.concat(lines, "\n"))
	local id = ok and type(receipt) == "table" and receipt.source and receipt.source.id
	return type(id) == "string" and id:match("@([^@]+)$") or nil
end

local function probe_version(path, name)
	local flags = version_flags[name]
	if not flags or not path then
		return nil
	end
	local ok, process = pcall(vim.system, vim.list_extend({ path }, flags), { text = true })
	if not ok then
		return nil
	end
	local result = process:wait(1000)
	if result.code ~= 0 then
		return nil
	end
	local text = vim.trim((result.stdout or "") .. "\n" .. (result.stderr or ""))
	if name == "shellcheck" then
		return text:match("version:%s*([^\r\n]+)")
	end
	return text:match("[^\r\n]+")
end

local function source_buffer()
	if vim.bo.buftype == "" then
		return vim.api.nvim_get_current_buf()
	end
	local alternate = vim.fn.bufnr("#")
	return alternate > 0 and vim.api.nvim_buf_is_valid(alternate) and vim.bo[alternate].buftype == "" and alternate or 0
end

function M.check()
	local health = vim.health
	local toolchain = require("user.toolchain")
	local project = require("user.core.project")
	local preferences = require("user.core.preferences")
	local bufnr = source_buffer()
	local context = project.context(bufnr)
	health.start("Project context")
	health.info("Workspace: " .. context.root)
	health.info("Language project: " .. context.language_root)
	health.info("Repository: " .. (context.repository or "none"))
	health.info("Working directory: " .. context.cwd)
	health.info("File: " .. (context.file or "none"))
	health.info(
		"Tool preference: "
			.. (preferences.get("tools").prefer_mason and "Mason first" or "PATH first")
			.. "; project Node tools have priority"
	)
	for _, message in ipairs(preferences.errors()) do
		health.warn(message, "Correct preferences.json, then run :ToolsRefresh")
	end
	health.start("Search dependencies")
	for _, name in ipairs({ "fzf", "rg", "fd" }) do
		local resolved = toolchain.resolve(name, { bufnr = bufnr })
		if not resolved.path then
			health.error(
				name .. " is missing",
				"Install " .. name .. " for the configured file search and picker workflow"
			)
		else
			local version = probe_version(resolved.path, name)
			local major, minor = (version or ""):match("(%d+)%.(%d+)")
			if name == "fzf" and (not major or (tonumber(major) == 0 and tonumber(minor) < 36)) then
				health.error(
					"fzf needs version 0.36 or newer; found " .. (version or "unknown"),
					"Update fzf and run :ToolsRefresh"
				)
			else
				health.ok(name .. ": " .. resolved.path .. "; " .. (version or "version unavailable"))
			end
		end
	end

	health.start("Runtimes")
	for _, name in ipairs({ "git", "node", "java", "go", "rustc" }) do
		local resolved = toolchain.resolve(name, { bufnr = bufnr })
		if resolved.path then
			health.ok(
				name
					.. ": "
					.. resolved.path
					.. " ["
					.. resolved.source
					.. "]; "
					.. (probe_version(resolved.path, name) or "version unavailable")
			)
		else
			health.info(name .. ": unavailable; needed only by the corresponding workflows")
		end
	end
	local python = toolchain.python_resolve(bufnr)
	local debugpy = toolchain.debugpy_host()
	if python.path then
		health.ok(
			"Python target: "
				.. python.path
				.. " ["
				.. python.source
				.. "]; "
				.. python.reason
				.. "; "
				.. (probe_version(python.path, "python") or "version unavailable")
		)
	else
		health.info("Python target: " .. python.reason)
	end
	health.info(
		"debugpy host: " .. (debugpy.path or "unavailable") .. " [" .. debugpy.source .. "]; " .. debugpy.reason
	)
	local jdtls_java, java_version = require("user.core.java").runtime()
	if jdtls_java then
		health.ok(
			"JDTLS Java: " .. jdtls_java .. "; validated Java " .. java_version .. "; selected from JAVA_HOME then PATH"
		)
	else
		health.info("JDTLS Java: " .. java_version)
	end

	health.start("Configured tools")
	local missing = {}
	for _, package in ipairs(toolchain.packages) do
		local name = package[1]
		local receipt = installed_version(name)
		local executable = executable_names[name] or name
		local resolved = toolchain.node_commands[executable] and toolchain.node_resolve(executable, bufnr)
			or toolchain.resolve(executable, { bufnr = bufnr, prefer_mason = name == "latexindent" and true or nil })
		if java_artifacts[name] then
			local artifact = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "share", java_artifacts[name])
			resolved = {
				path = vim.uv.fs_stat(artifact) and artifact or nil,
				source = "mason",
				reason = "JDTLS support bundle",
			}
		end
		if resolved.path then
			local version = resolved.source == "mason" and receipt or probe_version(resolved.path, executable)
			health.info(
				name
					.. ": "
					.. resolved.path
					.. " ["
					.. resolved.source
					.. "]; "
					.. resolved.reason
					.. "; "
					.. (version and "selected version " .. version or "selected version unavailable")
					.. "; Mason restore "
					.. package.version
			)
			if resolved.source == "mason" and receipt and receipt ~= package.version then
				health.warn(
					name .. " Mason receipt differs from its restore pin",
					"Run :MasonToolsInstall to restore configured versions"
				)
			end
		else
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		health.warn(
			"Unavailable configured tools: " .. table.concat(missing, ", "),
			"Run :MasonToolsInstall for the pinned tools, then :ToolsRefresh. Basic editing does not require every language tool."
		)
	else
		health.ok("All configured tool executables and Java bundles were found")
	end

	health.start("Running language servers")
	local clients = vim.lsp.get_clients()
	for _, client in ipairs(clients) do
		local command = client.config.cmd
		local path = type(command) == "table" and table.concat(command, " ")
			or "dynamic launcher (see tool source above)"
		health.info(client.name .. " #" .. client.id .. ": " .. path .. "; root " .. (client.root_dir or "single file"))
	end
	if #clients == 0 then
		health.info("No language server is currently running")
	end
	health.info(
		":ToolsRefresh discovers new tools and enables available servers. Existing clients keep their running command until you restart them explicitly."
	)
end

return M
