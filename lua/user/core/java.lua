local M = {}

local build_markers = {
	"mvnw",
	"gradlew",
	"settings.gradle",
	"settings.gradle.kts",
	"build.xml",
	"pom.xml",
	"build.gradle",
	"build.gradle.kts",
}

function M.project_root(source)
	-- All build descriptors have equal priority, so vim.fs.root chooses the
	-- nearest one. VCS metadata is considered only when no build file exists.
	local root = vim.fs.root(source, { build_markers, { ".git", ".jj" } })
	if root then
		return vim.fs.normalize(root)
	end

	local path = type(source) == "number" and vim.api.nvim_buf_get_name(source) or source
	return path and path ~= "" and vim.fs.dirname(vim.fs.normalize(path)) or vim.fn.getcwd()
end

local java_version_cache = {}

function M.clear_runtime_cache()
	java_version_cache = {}
end

local function java_version(executable)
	if java_version_cache[executable] then
		return java_version_cache[executable]
	end

	local result = vim.system({ executable, "-version" }, { text = true }):wait(3000)
	local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
	local version = output:match('version%s+"([^"]+)"') or output:match("openjdk%s+([%w._+-]+)")
	local first, second
	if version then
		first, second = version:match("^(%d+)%.?(%d*)")
	end
	local major = tonumber(first)
	if major == 1 then
		major = tonumber(second)
	end
	if result.code ~= 0 or not major then
		return nil
	end

	java_version_cache[executable] = major
	return major
end

function M.runtime()
	local candidates = {}
	if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= "" then
		table.insert(
			candidates,
			vim.fs.joinpath(vim.env.JAVA_HOME, "bin", vim.fn.has("win32") == 1 and "java.exe" or "java")
		)
	end
	table.insert(candidates, vim.fn.exepath("java"))
	local found = {}
	for _, candidate in ipairs(candidates) do
		if candidate ~= "" and vim.fn.executable(candidate) == 1 then
			local executable = vim.uv.fs_realpath(candidate) or candidate
			local major = java_version(executable)
			if major and major >= 21 then
				return executable, major
			end
			table.insert(found, executable .. " (" .. (major and "Java " .. major or "unknown version") .. ")")
		end
	end
	return nil,
		"JDTLS requires Java 21 or newer in JAVA_HOME or PATH"
			.. (#found > 0 and ": " .. table.concat(found, ", ") or "")
end

function M.python_runtime()
	for _, name in ipairs({ "python3", "python" }) do
		local executable = vim.fn.exepath(name)
		if executable ~= "" then
			local result = vim.system({ executable, "--version" }, { text = true }):wait(3000)
			local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
			local major, minor = output:match("Python%s+(%d+)%.(%d+)")
			major, minor = tonumber(major), tonumber(minor)
			if result.code == 0 and major and (major > 3 or (major == 3 and minor >= 9)) then
				return executable, ("%d.%d"):format(major, minor)
			end
		end
	end
	return nil, "Mason's JDTLS launcher requires Python 3.9 or newer in PATH"
end

function M.workspace_dir(root)
	local project = vim.fn.fnamemodify(root, ":t"):gsub("[^%w._-]", "_")
	if project == "" then
		project = "root"
	end

	return vim.fs.joinpath(
		vim.fn.stdpath("data"),
		"jdtls",
		"workspaces",
		("%s-%s"):format(project, vim.fn.sha256(root):sub(1, 12))
	)
end

return M
