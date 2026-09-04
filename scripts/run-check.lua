local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
local tmp = assert(vim.env.NVIM_TEST_TMP, "NVIM_TEST_TMP is required")
local group = assert(vim.env.NVIM_TEST_GROUP, "NVIM_TEST_GROUP is required")
assert(
	vim.tbl_contains({
		"performance",
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
