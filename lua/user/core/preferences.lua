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

---Persist one preference without replacing other settings or invalid JSON.
---The temporary file lives beside the destination so rename is atomic.
function M.set(section, key, value)
	local expected = defaults[section] and defaults[section][key]
	local allowed = choices[section] and choices[section][key]
	assert(expected ~= nil and type(value) == type(expected), "Invalid preference value")
	assert(not allowed or vim.tbl_contains(allowed, value), "Invalid preference choice")
	local path = vim.fs.joinpath(vim.fn.stdpath("config"), "preferences.json")
	path = vim.uv.fs_realpath(path) or path
	local values = {}
	if vim.uv.fs_stat(path) then
		local read, lines = pcall(vim.fn.readfile, path)
		local raw = read and table.concat(lines, "\n") or ""
		local parsed, result = pcall(vim.json.decode, raw)
		if not parsed or type(result) ~= "table" or not raw:match("^%s*{") then
			return nil, "Cannot update invalid or unreadable preferences: " .. path
		end
		values = result
	end
	values[section] = type(values[section]) == "table" and values[section] or {}
	values[section][key] = value
	local fd, temporary = vim.uv.fs_mkstemp(path .. ".XXXXXX")
	if not fd then
		return nil, "Cannot save preferences: " .. tostring(temporary)
	end
	local data = vim.json.encode(values) .. "\n"
	local written, err = vim.uv.fs_write(fd, data, 0)
	vim.uv.fs_close(fd)
	local ok
	if written == #data then
		ok, err = vim.uv.fs_rename(temporary, path)
	end
	if not ok then
		vim.uv.fs_unlink(temporary)
		return nil, "Cannot save preferences: " .. tostring(err or "incomplete write")
	end
	M.refresh()
	return true
end

return M
