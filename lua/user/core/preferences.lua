local M = {}
local defaults = {
	tools = { prefer_mason = false },
	ui = { min_editor_width = 40, min_editor_height = 8 },
	format = { timeout_ms = 800 },
}
local cached
local errors = {}

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
				if expected == nil or type(expected) ~= type(value) or (type(value) == "number" and value < 1) then
					table.insert(errors, "Invalid preference: " .. section .. "." .. key)
				else
					result[section][key] = value
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

function M.refresh()
	cached, errors = nil, {}
end

return M
