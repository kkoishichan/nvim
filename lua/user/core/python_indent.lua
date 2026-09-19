local M = {}
local configured = false

-- ERROR-node child constraints do not reliably restrict the matched text.
-- The upstream recovery rule for an unfinished `try:` also matches an
-- unfinished annotation such as `def f(\n    value:\n)`, adding a block
-- indent on top of the parameter-list indent. Require the actual keyword.
local unsafe_try = [[(ERROR
  "try"
  .
  ":"
  (#set! indent.immediate 1)) @indent.begin]]

local guarded_try = [[((ERROR) @indent.begin
  (#lua-match? @indent.begin "^try%s*:")
  (#set! indent.immediate 1))]]

function M.setup()
	if configured then
		return
	end
	local contents = {}
	for _, path in ipairs(vim.treesitter.query.get_files("python", "indents")) do
		contents[#contents + 1] = table.concat(vim.fn.readfile(path), "\n")
	end
	local source = table.concat(contents, "\n")
	local first, last = source:find(unsafe_try, 1, true)
	if first then
		-- Preserve the other installed rules and user extensions; do not replace
		-- the query when a future upstream version no longer has this pattern.
		vim.treesitter.query.set("python", "indents", source:sub(1, first - 1) .. guarded_try .. source:sub(last + 1))
	end
	configured = true
end

return M
