local parsers = { "c_sharp", "kotlin" }
local treesitter = require("nvim-treesitter")

local installed = treesitter
	.install(parsers, {
		force = true,
		max_jobs = 2,
		summary = true,
	})
	:wait(300000)

assert(installed, "failed to install the Tree-sitter parsers required by the integration checks")

for _, parser in ipairs(parsers) do
	assert(vim.treesitter.language.add(parser), parser .. " Tree-sitter parser was installed but cannot be loaded")
end

print("Tree-sitter test parsers installed and loadable.")
