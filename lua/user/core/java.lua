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

function M.runtime()
	local executable = vim.fn.exepath("java")
	if executable == "" then
		return nil, "Java 21 or newer is not available in PATH"
	end
	if java_version_cache[executable] then
		return executable, java_version_cache[executable]
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
		return nil, "Could not determine the Java runtime version"
	end
	if major < 21 then
		return nil, ("JDTLS requires Java 21 or newer; PATH currently resolves Java %d"):format(major)
	end

	java_version_cache[executable] = major
	return executable, major
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
