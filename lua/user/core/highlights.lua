-- The one place custom highlights are (re)derived from. Every ColorScheme
-- runs the same chain: first the transparency pass, which clears the surfaces
-- the active theme painted, then every registered owner in registration
-- order. Owners read `user.core.palette`, which already reflects the theme
-- and the transparency state, so no owner needs its own ColorScheme autocmd
-- or its own transparency branch.
local M = {}
-- Preserve registrations when this helper itself is reloaded. Each owner has
-- one replaceable callback, dispatched by one autocmd across all generations.
local state_key = "_user_highlight_callbacks"
local callbacks = rawget(vim, state_key)
if type(callbacks) ~= "table" or type(callbacks.order) ~= "table" then
	-- First load, or a reload over the previous flat registry: owners
	-- re-register themselves as their modules reload.
	callbacks = { order = {}, by_name = {} }
end
rawset(vim, state_key, callbacks)
local group = vim.api.nvim_create_augroup("user_custom_highlights", { clear = true })

local function invoke(name, callback)
	local ok, err = pcall(callback)
	if not ok then
		vim.schedule(function()
			vim.notify(
				"Highlight callback " .. name .. ": " .. tostring(err),
				vim.log.levels.ERROR,
				{ title = "Highlights" }
			)
		end)
	end
end

---Re-derive everything: the transparency pass, then every owner.
function M.refresh()
	local ok, transparency = pcall(require, "user.core.transparency")
	if ok then
		invoke("transparency", transparency.apply)
	end
	for _, name in ipairs(callbacks.order) do
		local callback = callbacks.by_name[name]
		if callback then
			invoke(name, callback)
		end
	end
end

vim.api.nvim_create_autocmd("ColorScheme", {
	group = group,
	callback = function()
		M.refresh()
		-- Plugins whose own ColorScheme handlers run after this one repaint
		-- their surfaces; one deferred transparency pass clears those too.
		local ok, transparency = pcall(require, "user.core.transparency")
		if ok then
			vim.schedule(function()
				invoke("transparency", transparency.apply)
			end)
		end
	end,
})

---Register an owner. The callback runs now and after every ColorScheme, after
---the transparency pass. Registering the same name again replaces the callback
---and keeps its position.
---@param name string
---@param callback fun()
function M.on_colorscheme(name, callback)
	-- Keep existing callers reload-safe during a gradual configuration reload.
	if type(name) == "function" and callback == nil then
		local info = debug.getinfo(name, "S")
		callback, name = name, info.source .. ":" .. info.linedefined
	end
	assert(type(name) == "string" and type(callback) == "function", "A highlight owner and callback are required")
	if not callbacks.by_name[name] then
		callbacks.order[#callbacks.order + 1] = name
	end
	callbacks.by_name[name] = callback
	invoke(name, callback)
end

function M.remove(name)
	callbacks.by_name[name] = nil
	for index, entry in ipairs(callbacks.order) do
		if entry == name then
			table.remove(callbacks.order, index)
			break
		end
	end
end

function M.count()
	return #callbacks.order
end

---Owner names in the order they run, for reports and checks.
function M.names()
	return vim.deepcopy(callbacks.order)
end

return M
