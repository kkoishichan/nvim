-- Legacy integration entrypoint. Each topic keeps its original ordering because
-- this group verifies plugin-loading interactions within one Neovim instance.
local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
local tmp = assert(vim.env.NVIM_TEST_TMP, "NVIM_TEST_TMP is required")
assert(vim.v.errmsg == "", "Configuration startup failed: " .. vim.v.errmsg)
for _, topic in ipairs({
	"startup",
	"treesitter",
	"sensitive",
	"plugin_ui",
	"signature_ui",
	"navigation_ui",
	"floats",
	"tools",
	"language_wiring",
	"python_indent",
	"editing",
}) do
	local path = vim.fs.joinpath(root, "scripts", "checks", "integration", topic .. ".lua")
	local check = assert(loadfile(path))()
	assert(type(check) == "function", "Invalid integration topic: " .. topic)
	check(tmp)
	print("Integration topic passed: " .. topic)
end
print("Neovim integration checks passed.")
