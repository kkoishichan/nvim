-- Registry for the adapters that patch locked plugins (match-up cache, colour
-- preview, scrollbar refresh, ...). Each one verifies the plugin source it
-- depends on and falls back to the plugin's native behaviour when the source
-- changed. That fallback used to be silent; the registry makes it visible in
-- :ModeInfo and :checkhealth and raises one notice per session.
local M = {}
local entries, order = {}, {}
local notified = false

---@class user.AdapterEntry
---@field name string
---@field active boolean
---@field detail string|nil reason when inactive, note when active
---@field quiet boolean inactive is informational only (no notice)

---Record an adapter outcome. Returns `active` for convenient chaining.
---@param name string
---@param active boolean
---@param detail string|nil
---@param opts { quiet?: boolean }|nil
---@return boolean
function M.record(name, active, detail, opts)
	if not entries[name] then
		order[#order + 1] = name
	end
	local quiet = opts and opts.quiet == true or false
	entries[name] = { name = name, active = active == true, detail = detail, quiet = quiet }
	if active or quiet then
		return active == true
	end
	require("user.core.mode").degrade("adapter " .. name, detail or "plugin changed; using its native behaviour")
	if not notified then
		notified = true
		vim.schedule(function()
			vim.notify(
				("Optimisation adapter inactive: %s. :ModeInfo lists every adapter."):format(name),
				vim.log.levels.WARN,
				{ title = "Adapters" }
			)
		end)
	end
	return false
end

---Run an adapter's setup and record the outcome. `setup` returns true, or
---false and a reason; an error counts as inactive rather than failing the
---plugin that was being configured.
---@param name string
---@param setup fun(): boolean, string|nil
---@param opts { quiet?: boolean }|nil
---@return boolean
function M.run(name, setup, opts)
	local ok, active, detail = pcall(setup)
	if not ok then
		return M.record(name, false, "setup failed: " .. tostring(active), opts)
	end
	return M.record(name, active == true, type(detail) == "string" and detail or nil, opts)
end

---Entries in registration order, copied.
---@return user.AdapterEntry[]
function M.list()
	local result = {}
	for _, name in ipairs(order) do
		result[#result + 1] = vim.deepcopy(entries[name])
	end
	return result
end

---One line for :ModeInfo.
function M.summary()
	if #order == 0 then
		return "none loaded yet"
	end
	local parts = {}
	for _, entry in ipairs(M.list()) do
		local state = entry.active and "on" or "off"
		if not entry.active and entry.detail then
			state = state .. " (" .. entry.detail .. ")"
		end
		parts[#parts + 1] = entry.name .. " " .. state
	end
	return table.concat(parts, ", ")
end

---Only checks use this; a live session keeps its history.
function M.reset()
	entries, order, notified = {}, {}, false
end

return M
