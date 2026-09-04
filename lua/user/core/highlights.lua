local M = {}
-- Preserve registrations when this helper itself is reloaded. Each owner has
-- one replaceable callback, dispatched by one autocmd across all generations.
local state_key = "_user_highlight_callbacks"
local callbacks = rawget(vim, state_key) or {}
rawset(vim, state_key, callbacks)
local group = vim.api.nvim_create_augroup("user_custom_highlights", { clear = true })

local function invoke(name, callback)
	local ok, err = pcall(callback)
	if not ok then
		vim.schedule(function()
			vim.notify("Highlight callback " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
		end)
	end
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = group,
	callback = function()
		for _, name in ipairs(vim.tbl_keys(callbacks)) do
			if callbacks[name] then
				invoke(name, callbacks[name])
			end
		end
	end,
})

---@param name string
---@param callback fun()
function M.on_colorscheme(name, callback)
	-- Keep existing callers reload-safe during a gradual configuration reload.
	if type(name) == "function" and callback == nil then
		local info = debug.getinfo(name, "S")
		callback, name = name, info.source .. ":" .. info.linedefined
	end
	assert(type(name) == "string" and type(callback) == "function", "A highlight owner and callback are required")
	callbacks[name] = callback
	invoke(name, callback)
end

function M.remove(name)
	callbacks[name] = nil
end

function M.count()
	return vim.tbl_count(callbacks)
end

return M
