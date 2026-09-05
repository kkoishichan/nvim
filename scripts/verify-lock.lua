local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
local data = vim.fn.stdpath("data")
assert(
	vim.uv.fs_stat(data .. "/lazy/lazy.nvim/lua/lazy/init.lua"),
	"lazy.nvim is missing; run scripts/prepare-checks.sh first"
)
local support = assert(loadfile(root .. "/scripts/check-support.lua"))()
local lock, plugins = support.plugins(root, data)
local count = 0
for name, pin in pairs(lock) do
	local directory = plugins[name].dir
	assert(vim.uv.fs_stat(directory .. "/.git"), "Missing plugin; run prepare-checks.sh: " .. name)
	assert(
		support.command({ "git", "rev-parse", "HEAD" }, directory) == pin.commit,
		"Plugin differs from lock: " .. name
	)
	assert(
		support.command({ "git", "status", "--porcelain", "--untracked-files=no" }, directory) == "",
		"Tracked plugin files were modified: " .. name
	)
	count = count + 1
end
local parsers, info = {}, {}
if vim.env.NVIM_VERIFY_PARSERS ~= "0" then
	parsers, info = support.parser_info(data)
end
for _, parser in ipairs(parsers) do
	local binary = data .. "/site/parser/" .. parser .. ".so"
	assert(vim.uv.fs_stat(binary), "Missing prepared parser binary: " .. parser)
	local install = info[parser].install_info
	if install and install.revision then
		local revision = data .. "/site/parser-info/" .. parser .. ".revision"
		assert(vim.uv.fs_stat(revision), "Missing parser revision: " .. parser)
		assert(
			vim.trim(table.concat(vim.fn.readfile(revision), "\n")) == install.revision,
			"Parser revision differs from locked plugin: " .. parser
		)
	end
	assert(vim.treesitter.language.add(parser, { path = binary }), "Parser cannot load: " .. parser)
end
local tools = vim.env.NVIM_VERIFY_TOOLS == "0" and {} or support.tools
for _, name in ipairs(tools) do
	local receipt_path = data .. "/mason/packages/" .. name .. "/mason-receipt.json"
	assert(vim.uv.fs_stat(receipt_path), "Missing prepared check tool: " .. name)
	local receipt = support.json(receipt_path)
	local pin = require("user.toolchain").version(name)
	assert(receipt.source.id:sub(-#pin - 1) == "@" .. pin, "Check tool differs from configured pin: " .. name)
	assert(vim.fn.executable(data .. "/mason/bin/" .. name) == 1, "Prepared check tool cannot execute: " .. name)
end
if vim.env.NVIM_VERIFY_ASSETS ~= "0" then
	support.verify_blink(data, lock["blink.cmp"].commit)
end
print(("Verified %d locked plugins, %d parser revisions and %d check tools."):format(count, #parsers, #tools))
