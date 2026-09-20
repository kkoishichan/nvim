local M = {}
local defaults = {
	tools = { prefer_mason = false },
	ui = { min_editor_width = 40, min_editor_height = 8 },
	format = { timeout_ms = 800 },
	-- An empty state_dir means "use the standard state path"; a server pointing
	-- at local disk avoids writing recovery data to a network home.
	runtime = { mode = "full", state_dir = "", persistent_undo = false },
}
-- Settings whose value is one name out of a fixed set. Anything else is a
-- configuration mistake and must not silently pick a neighbouring behaviour.
local choices = {
	runtime = { mode = { "full", "fast", "auto" } },
}
local cached
local errors = {}
-- Which settings the host actually wrote, so callers can tell a deliberate
-- choice from a default that happens to have the same value.
local provided = {}

local function load()
	local path = vim.fs.joinpath(vim.fn.stdpath("config"), "preferences.json")
	local values = {}
	if vim.uv.fs_stat(path) then
		local ok_read, lines = pcall(vim.fn.readfile, path)
		local ok, parsed = false, nil
		if ok_read then
			ok, parsed = pcall(vim.json.decode, table.concat(lines, "\n"))
		end
		if ok and type(parsed) == "table" then
			values = parsed
		else
			table.insert(errors, "Invalid JSON in " .. path)
		end
	end
	local result = vim.deepcopy(defaults)
	for section, settings in pairs(values) do
		if type(settings) ~= "table" or not defaults[section] then
			table.insert(errors, "Unknown preference section: " .. section)
		else
			for key, value in pairs(settings) do
				local expected = defaults[section][key]
				local allowed = choices[section] and choices[section][key]
				if expected == nil or type(expected) ~= type(value) or (type(value) == "number" and value < 1) then
					table.insert(errors, "Invalid preference: " .. section .. "." .. key)
				elseif allowed and not vim.tbl_contains(allowed, value) then
					table.insert(
						errors,
						("Invalid preference: %s.%s must be one of %s"):format(
							section,
							key,
							table.concat(allowed, ", ")
						)
					)
				else
					result[section][key] = value
					provided[section .. "." .. key] = true
				end
			end
		end
	end
	return result
end

function M.get(section)
	cached = cached or load()
	return vim.deepcopy(section and cached[section] or cached)
end

function M.errors()
	M.get()
	return vim.deepcopy(errors)
end

---True when `preferences.json` set this `section.key` itself.
function M.provided(path)
	M.get()
	return provided[path] == true
end

function M.refresh()
	cached, errors, provided = nil, {}, {}
end

return M
