local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
local tmp = assert(vim.env.NVIM_TEST_TMP, "NVIM_TEST_TMP is required")
local group = assert(vim.env.NVIM_TEST_GROUP, "NVIM_TEST_GROUP is required")
assert(vim.v.errmsg == "", "Configuration startup failed: " .. vim.v.errmsg)
assert(
	vim.tbl_contains({
		"performance",
		"editing_cost",
		"matchup_cache",
		"matchup_highlights",
		"matchup_input",
		"lsp_progress",
		"startup_loading",
		"ui_runtime",
		"scrolling_colors",
		"statusline_refresh",
		"scrollview_refresh",
		"ai",
		"languages",
		"projects",
		"project_actions",
		"toolchain",
		"terminals",
		"workflow_actions",
		"workflow_python_js",
		"workflow_native",
		"workflow_java_docs",
		"signature",
		"lifecycle",
		"pdf_lifecycle",
		"windows",
		"layout_session",
		"ui_themes",
		"offline_assets",
	}, group),
	"Unknown behavior check group: " .. group
)

local path = vim.fs.joinpath(root, "scripts", "checks", group .. ".lua")
local module, err = loadfile(path)
assert(module, ("Could not load check group %s: %s"):format(path, err))
local check = module()
assert(type(check) == "function", "Check group must return function(tmp): " .. group)
check(tmp)

print(("Neovim %s checks passed."):format(group))
