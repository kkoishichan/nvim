local M = {}
local owner_key = "_user_statusline_refresh"
local lifecycle_group = "user_lualine_theme"
local active, pending = false, nil

local function repair()
	local lualine = package.loaded.lualine
	if not lualine or not lualine.get_config().options.globalstatus then
		return 0
	end
	local group = "lualine_stl_refresh"
	local ok, registrations = pcall(vim.api.nvim_get_autocmds, { group = group })
	if not ok then
		return 0
	end
	local changed = 0
	for _, registration in ipairs(registrations) do
		local command = registration.command or ""
		-- The locked plugin's Vimscript registrations have no deletable ID.
		-- Rebuild its group only when every entry is its known statusline command;
		-- leave custom callbacks and future incompatible registrations untouched.
		if
			registration.buflocal
			or registration.pattern ~= "*"
			or not command:match("^call v:lua%.require'lualine'%.refresh%(")
			or not command:find("'place': ['statusline']", 1, true)
		then
			return 0
		end
		local count
		registration.command, count = command:gsub("'kind'%s*:%s*'window'", "'scope': 'window'", 1)
		changed = changed + count
	end
	if changed == 0 then
		return 0
	end
	-- Keep the existing event list and lualine's own queue, 16 ms coalescing,
	-- periodic fallback and rendering. Only correct the scope argument.
	vim.api.nvim_clear_autocmds({ group = group })
	for _, registration in ipairs(registrations) do
		vim.api.nvim_create_autocmd(registration.event, {
			group = group,
			pattern = registration.pattern,
			once = registration.once,
			desc = registration.desc,
			command = registration.command,
		})
	end
	return changed
end

function M.shutdown()
	active, pending = false, nil
	if rawget(vim, owner_key) == M then
		rawset(vim, owner_key, nil)
		vim.api.nvim_clear_autocmds({ group = lifecycle_group })
	end
end

local function after_theme()
	if not active or pending then
		return
	end
	local request = {}
	pending = request
	vim.schedule(function()
		if active and pending == request and rawget(vim, owner_key) == M then
			pending = nil
			repair()
		end
	end)
end

function M.setup()
	local previous = rawget(vim, owner_key)
	if previous ~= M then
		if previous then
			previous.shutdown()
		end
		active = true
		rawset(vim, owner_key, M)
		local group = vim.api.nvim_create_augroup(lifecycle_group, { clear = true })
		-- Lualine already rebuilds its theme on these events. Repair after all
		-- synchronous handlers finish, regardless of their registration order.
		vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = after_theme })
		vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = after_theme })
		vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.shutdown })
	end
	return repair()
end

return M
