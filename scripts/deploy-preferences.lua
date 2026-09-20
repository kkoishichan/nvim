-- Record the deployed editor mode in the staged preferences, preserving every
-- other setting the host had. Writing the choice down is what makes a server
-- keep it after the SSH environment is gone, inside tmux for instance.
local path = assert(vim.env.NVIM_DEPLOY_PREFERENCES, "NVIM_DEPLOY_PREFERENCES is required")
local mode = assert(vim.env.NVIM_DEPLOY_EDITOR_MODE, "NVIM_DEPLOY_EDITOR_MODE is required")
assert(mode == "full" or mode == "fast", "Unknown editor mode: " .. mode)
local values = {}
if vim.uv.fs_stat(path) then
	local ok, parsed = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	assert(ok and type(parsed) == "table", "Existing preferences.json is not a JSON object: " .. path)
	values = parsed
end
values.runtime = type(values.runtime) == "table" and values.runtime or {}
values.runtime.mode = mode
assert(vim.fn.writefile({ vim.json.encode(values) }, path) == 0, "Could not write " .. path)
print("Recorded editor mode " .. mode .. " in " .. path)
