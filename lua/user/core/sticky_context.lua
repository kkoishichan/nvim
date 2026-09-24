local M = {}
local owner
local source_hash = "b0c804eefd5780cba727ae3b08d735c09def614191ae5a5a743b21fbf4151ba4"

function M.shutdown()
	if owner then
		local _, current = debug.getupvalue(owner.get, owner.index)
		if current == owner.wrapper then
			debug.setupvalue(owner.get, owner.index, owner.native)
		end
		owner = nil
	end
	if vim._user_sticky_context == M then
		vim._user_sticky_context = nil
	end
end

function M.setup()
	local previous = vim._user_sticky_context
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	local get = require("treesitter-context.context").get
	-- Only replace the locked plugin's height calculation. Its parser, queries,
	-- highlights, throttling and navigation remain owned by the plugin.
	local source = debug.getinfo(get, "S").source
	local file = source:sub(1, 1) == "@" and io.open(source:sub(2), "rb") or nil
	if not file then
		return false
	end
	local text = file:read("*a")
	file:close()
	if vim.fn.sha256(text) ~= source_hash then
		return false
	end
	for index = 1, 20 do
		local name, native = debug.getupvalue(get, index)
		if name == "calc_max_lines" and type(native) == "function" then
			local config = require("treesitter-context.config")
			local function wrapper(win)
				local limit = native(win)
				local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
				if view.topfill == 0 then
					return limit
				end
				-- A cursor on topline can still have a whole image above it.
				local rows = view.lnum - view.topline + view.topfill
				if config.separator and rows > 0 then
					rows = rows - 1
				end
				local max = config.max_lines
				if type(max) == "string" then
					max = math.ceil(vim.api.nvim_win_get_height(win) * (tonumber(max:match("^(%d+)%%$")) or 0) / 100)
				end
				return max <= 0 and rows or math.min(max, rows)
			end
			debug.setupvalue(get, index, wrapper)
			owner = { get = get, index = index, native = native, wrapper = wrapper }
			vim._user_sticky_context = M
			return true
		end
	end
	return false
end

return M
