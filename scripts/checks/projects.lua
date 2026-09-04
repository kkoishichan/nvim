return function(tmp)
	local project = require("user.core.project")
	local base = vim.fs.joinpath(tmp, "project fixtures")
	local a, b = base .. "/a", base .. "/b"
	local function write(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines, path)
	end
	vim.fn.mkdir(a .. "/.git", "p")
	write(a .. "/packages/app/package.json", { "{}" })
	write(a .. "/packages/app/src/main.ts", { "export const value = 1;" })
	write(b .. "/.git", { "gitdir: ../shared/worktrees/b" })
	write(b .. "/pyproject.toml", { "[project]", 'name = "example"' })
	local context = project.context(a .. "/packages/app/src/main.ts")
	assert(context.root == a and context.repository == a, "Nested package lost workspace repository")
	assert(context.language_root == a .. "/packages/app", "Nested language project collapsed to repository")
	assert(project.context(b .. "/new.py").repository == b, "Worktree .git file was not recognized")
	assert(project.contains(a, a .. "/packages/app"), "Workspace containment failed")
	assert(not project.contains(a, a .. "-other/main.ts"), "Workspace prefix matched another project")
	assert(project.contains("/", a), "Filesystem root containment failed")

	-- Language tools and workspace markers must stop at a nested repository.
	write(a .. "/pyproject.toml", { "[project]" })
	write(a .. "/.root", {})
	write(a .. "/.venv/bin/python", { "#!/bin/sh", "exit 0" })
	vim.fn.setfperm(a .. "/.venv/bin/python", "rwxr-xr-x")
	local nested = a .. "/nested"
	vim.fn.mkdir(nested .. "/.git", "p")
	write(nested .. "/main.py", { "pass" })
	local nested_context = project.context(nested .. "/main.py")
	assert(
		nested_context.root == nested and nested_context.repository == nested and nested_context.language_root == nested,
		"An outer marker overrode the nested repository"
	)
	assert(
		require("user.toolchain").python_resolve(nested .. "/main.py").source ~= "project",
		"Python lookup escaped a nested repository to the outer virtualenv"
	)
	write(nested .. "/workspace/.root", {})
	write(nested .. "/workspace/packages/python/pyproject.toml", { "[project]" })
	local package_context = project.context(nested .. "/workspace/packages/python/new.py")
	assert(
		package_context.root == nested .. "/workspace"
			and package_context.language_root == nested .. "/workspace/packages/python",
		"A workspace .root marker replaced the nearest language package"
	)
	vim.fn.mkdir(a .. "/jujutsu/.jj", "p")
	assert(
		project.context(a .. "/jujutsu/new.py").repository == a .. "/jujutsu",
		"An outer Git repository overrode a closer Jujutsu repository"
	)

	assert(vim.uv.fs_symlink(a, base .. "/alias"))
	assert(
		project.canonical(base .. "/alias/packages/app/new.ts") == a .. "/packages/app/new.ts",
		"New file below symlink got another project key"
	)
	vim.fn.mkdir(base .. "/real/child", "p")
	vim.fn.mkdir(base .. "/links", "p")
	assert(vim.uv.fs_symlink(base .. "/real/child", base .. "/links/alias"))
	write(base .. "/real/saved.txt", { "symlink target parent" })
	write(base .. "/links/saved.txt", { "symlink parent" })
	for _, name in ipairs({ "saved.txt", "new.txt" }) do
		assert(
			project.canonical(base .. "/links/alias/../" .. name) == base .. "/real/" .. name,
			"Symlink/.. resolved to the link's parent for " .. name
		)
	end
	write(base .. "/single/readme.txt", { "standalone" })
	local fs_root = vim.fs.root
	vim.fs.root = function()
		return nil
	end
	local standalone = project.context(base .. "/single/readme.txt")
	vim.fs.root = fs_root
	assert(standalone.root == base .. "/single", "Standalone file has wrong fallback")

	local original_tab = vim.api.nvim_get_current_tabpage()
	vim.cmd.tabnew()
	local tab_a = vim.api.nvim_get_current_tabpage()
	project.set(a)
	assert(project.root() == a and vim.fn.getcwd() == a, "Project with spaces failed to set tab cwd")
	vim.cmd.tabnew()
	local tab_b = vim.api.nvim_get_current_tabpage()
	project.set(b)
	assert(project.root() == b, "Second tab did not adopt its project")
	vim.api.nvim_set_current_tabpage(tab_a)
	assert(project.root() == a, "Second project changed first tab")
	assert(project.context(b .. "/new.py").root == b, "Path resolution inherited another tab's explicit project")

	local buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[buffer].buftype = "nofile"
	vim.b[buffer].user_project_root = b
	vim.api.nvim_set_current_buf(buffer)
	assert(
		project.root() == a,
		"Terminal metadata overrode an explicit tab project: "
			.. vim.inspect({ context = project.context(), scope = vim.fn.haslocaldir(), tab = vim.t.user_project_root })
	)
	vim.cmd.cd({ args = { base } })
	assert(project.root() == b, "Special buffer lost its bound project without a tab override")
	vim.api.nvim_set_current_tabpage(tab_b)
	vim.cmd.tabclose()
	vim.api.nvim_set_current_tabpage(tab_a)
	vim.cmd.tabclose()
	vim.api.nvim_set_current_tabpage(original_tab)

	-- Local preferences are data, validated before use, and never executable.
	local preferences = require("user.core.preferences")
	local stdpath = vim.fn.stdpath
	local settings = base .. "/preferences"
	vim.fn.mkdir(settings, "p")
	vim.fn.stdpath = function(kind)
		return kind == "config" and settings or stdpath(kind)
	end
	write(settings .. "/preferences.json", { '{"tools":{"prefer_mason":true},"format":{"timeout_ms":700}}' })
	preferences.refresh()
	assert(preferences.get("tools").prefer_mason, "Machine tool preference ignored")
	assert(preferences.get("format").timeout_ms == 700, "Formatting preference ignored")
	local copy = preferences.get("tools")
	copy.prefer_mason = false
	assert(preferences.get("tools").prefer_mason, "Caller mutated shared preference state")
	write(settings .. "/preferences.json", { '{"format":{"timeout_ms":-1},"execute":"arbitrary command"}' })
	preferences.refresh()
	assert(
		preferences.get("format").timeout_ms == 2000 and #preferences.errors() == 2,
		"Invalid preferences did not fall back with explanations"
	)
	write(settings .. "/preferences.json", { "invalid json" })
	preferences.refresh()
	assert(
		not preferences.get("tools").prefer_mason and #preferences.errors() == 1,
		"Malformed preferences did not fall back"
	)
	vim.fn.stdpath = stdpath
	preferences.refresh()
end
