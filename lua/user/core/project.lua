local M = {}

M.markers = {
	".root",
	{
		"mvnw",
		"gradlew",
		"settings.gradle",
		"settings.gradle.kts",
		"pom.xml",
		"build.gradle",
		"build.gradle.kts",
		"build.xml",
		"compile_commands.json",
		"CMakeLists.txt",
		"Makefile",
		"package.json",
		"pyproject.toml",
		"Cargo.toml",
		"go.mod",
		"typst.toml",
	},
	{ ".git", ".jj" },
}

function M.canonical(path)
	if not path or path == "" then
		return nil
	end
	if path == "~" then
		path = vim.uv.os_homedir()
	elseif path:sub(1, 2) == "~/" then
		path = vim.fs.joinpath(vim.uv.os_homedir(), path:sub(3))
	end
	-- Resolve existing symlinks before collapsing `..`: link/../file belongs
	-- beside the link's target, not beside the link itself.
	path = vim.fs.abspath(path)
	local real = vim.uv.fs_realpath(path)
	if real then
		return vim.fs.normalize(real, { expand_env = false })
	end
	-- New files below a symlinked directory use the same project key as saved
	-- files. Resolve the longest existing prefix without creating anything.
	local parent, suffix = path, {}
	while parent and parent ~= vim.fs.dirname(parent) do
		table.insert(suffix, 1, vim.fs.basename(parent))
		parent = vim.fs.dirname(parent)
		real = vim.uv.fs_realpath(parent)
		if real then
			return vim.fs.normalize(vim.fs.joinpath(real, unpack(suffix)), { expand_env = false })
		end
	end
	return vim.fs.normalize(path, { expand_env = false })
end

local function contains_canonical(root, path)
	return root ~= nil
		and path ~= nil
		and (path == root or path:sub(1, #(root:gsub("/$", "") .. "/")) == root:gsub("/$", "") .. "/")
end

function M.contains(root, path)
	return contains_canonical(M.canonical(root), M.canonical(path))
end

local function directory(path, canonical)
	path = canonical and path or M.canonical(path)
	if not path then
		return M.canonical(vim.fn.getcwd())
	end
	local stat = vim.uv.fs_stat(path)
	return stat and stat.type == "directory" and path or vim.fs.dirname(path)
end

local function repository_root(dir)
	return M.canonical(vim.fs.root(dir, { M.markers[3] }))
end

local function bounded_root(dir, markers, repository)
	local root = M.canonical(vim.fs.root(dir, markers))
	return root and (not repository or contains_canonical(repository, root)) and root or nil
end

-- Reuse discoveries within one lookup. No persistent filesystem cache: a new
-- package marker or nested repository must affect the very next tool request.
local function roots(dir)
	local repository = repository_root(dir)
	local marker = bounded_root(dir, M.markers[1], repository)
	local language = bounded_root(dir, { M.markers[2] }, repository) or marker or repository
	return repository, marker, language
end

function M.find_root(path)
	local dir = directory(path)
	local repository = repository_root(dir)
	-- A nested repository starts a new project even without a language marker.
	-- Keep workspace .root markers separate from closer language packages.
	return bounded_root(dir, { M.markers[2] }, repository) or bounded_root(dir, M.markers[1], repository) or repository
end

function M.context(source)
	local by_path = type(source) == "string"
	local bufnr = not by_path and (source == nil or source == 0) and vim.api.nvim_get_current_buf() or source
	local cwd = M.canonical(vim.fn.getcwd())
	local file, bound
	if by_path then
		file = M.canonical(source)
	elseif type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
		bound = M.canonical(vim.b[bufnr].user_project_root)
		if vim.bo[bufnr].buftype == "" then
			file = M.canonical(vim.api.nvim_buf_get_name(bufnr))
		end
	end
	local dir = bound or directory(file or cwd, true)
	local repository, marker, language_root = roots(dir)
	if bound and file then
		local file_dir = directory(file, true)
		if file_dir ~= dir then
			language_root = M.find_root(file)
		end
	end
	local scope = vim.fn.haslocaldir()
	local explicit = not by_path and M.canonical(vim.t.user_project_root) or nil
	if not by_path and scope == 1 then
		explicit = cwd
	end
	return {
		root = explicit or bound or marker or repository or language_root or dir,
		language_root = language_root or dir,
		repository = repository,
		cwd = cwd,
		file = file,
		directory = dir,
		explicit = explicit ~= nil,
	}
end

function M.root(source)
	return M.context(source).root
end

function M.set(path)
	path = assert(M.canonical(path), "Project directory is empty")
	assert(vim.fn.isdirectory(path) == 1, "Project directory does not exist: " .. path)
	vim.cmd.tcd({ args = { path } })
	vim.t.user_project_root = path
	return path
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_project_context", { clear = true })
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			if vim.v.event.scope == "tabpage" then
				vim.t.user_project_root = M.canonical(vim.v.event.cwd)
			elseif vim.v.event.scope == "global" then
				vim.t.user_project_root = nil
			end
		end,
	})
	vim.api.nvim_create_user_command("ProjectContext", function()
		local context = M.context()
		vim.notify(
			table.concat({
				"Workspace: " .. context.root,
				"Language project: " .. context.language_root,
				"Repository: " .. (context.repository or "none"),
				"Working directory: " .. context.cwd,
			}, "\n"),
			vim.log.levels.INFO,
			{ title = "Project context" }
		)
	end, { desc = "Explain the current workspace and language project" })
	vim.api.nvim_create_user_command("ToolsRefresh", function()
		require("user.toolchain").refresh()
	end, { desc = "Refresh tool discovery after installing or changing environments" })
end

return M
