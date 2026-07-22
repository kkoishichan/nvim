local M = {}

local sensitive_extensions = {
	asc = true,
	gpg = true,
	key = true,
	p12 = true,
	pem = true,
	pfx = true,
}

local sensitive_names = {
	[".env"] = true,
	[".envrc"] = true,
	[".netrc"] = true,
	credentials = true,
	password = true,
	passwords = true,
	secret = true,
	secrets = true,
}

local template_names = {
	[".env.dist"] = true,
	[".env.example"] = true,
	[".env.sample"] = true,
	[".env.template"] = true,
}

local template_suffixes = {
	dist = true,
	example = true,
	sample = true,
	template = true,
}

local active_clipboard_snapshot

local function clear_unchanged_registers(snapshots)
	for register, snapshot in pairs(snapshots or {}) do
		local ok, current = pcall(vim.fn.getreginfo, register)
		if ok and vim.deep_equal(current, snapshot) then
			pcall(vim.fn.setreg, register, "")
		end
	end
end

local function is_sensitive(path)
	if type(path) ~= "string" or path == "" then
		return false
	end
	path = vim.fs.normalize(path):lower():gsub("\\", "/")
	path = "/" .. path:gsub("^/+", "")
	local name = vim.fs.basename(path)
	local extension = name:match("%.([^.]*)$")
	local template_stem, template_suffix = name:match("^(.+)%.([^.]+)$")
	local named_template = template_suffixes[template_suffix]
		and (
			template_stem == ".env"
			or template_stem:match("^%.env%.") ~= nil
			or sensitive_names[template_stem] == true
		)
	if template_names[name] or named_template then
		return false
	end

	return sensitive_names[name] == true
		or name:match("^%.env%.") ~= nil
		or sensitive_extensions[extension] == true
		or path:match("/%.ssh/") ~= nil
		or path:match("/%.aws/credentials$") ~= nil
		or path:match("/secrets?/") ~= nil
		or name:match("^credentials%.[^.]+$") ~= nil
		or name:match("^passwords?%.[^.]+$") ~= nil
		or name:match("^secrets?%.[^.]+$") ~= nil
end

local function expire_clipboard(bufnr, yank)
	local timeout = tonumber(vim.g.user_sensitive_clipboard_timeout_ms)
	if timeout == nil then
		timeout = 60000
	end
	if timeout <= 0 then
		return
	end

	local registers = { '"', "+", "*", "-" }
	for index = 0, 9 do
		table.insert(registers, tostring(index))
	end
	local explicit = type(yank.regname) == "string" and yank.regname:lower() or ""
	if explicit:match("^[a-z]$") then
		table.insert(registers, explicit)
	end

	local snapshots = {}
	for _, register in ipairs(registers) do
		local ok, value = pcall(vim.fn.getreginfo, register)
		local contains_yank = ok
			and vim.deep_equal(value.regcontents, yank.regcontents)
			and value.regtype == yank.regtype
		if ok and (contains_yank or register == explicit) then
			snapshots[register] = value
		end
	end
	if not next(snapshots) then
		return
	end
	active_clipboard_snapshot = snapshots

	if not vim.b[bufnr].user_sensitive_clipboard_notice then
		vim.b[bufnr].user_sensitive_clipboard_notice = true
		vim.notify(
			("Sensitive register/clipboard content will expire in %d seconds if unchanged"):format(
				math.floor(timeout / 1000)
			),
			vim.log.levels.WARN,
			{ title = "Sensitive buffer" }
		)
	end

	vim.defer_fn(function()
		clear_unchanged_registers(snapshots)
		if active_clipboard_snapshot == snapshots then
			active_clipboard_snapshot = nil
		end
	end, timeout)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_sensitive_buffers", { clear = true })

	vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
		group = group,
		callback = function(event)
			if not is_sensitive(event.match) then
				return
			end
			vim.b[event.buf].user_sensitive = true
			vim.bo[event.buf].undofile = false
			vim.bo[event.buf].swapfile = false
		end,
	})

	vim.api.nvim_create_autocmd("TextYankPost", {
		group = group,
		callback = function(event)
			-- The black-hole register deliberately retains nothing, so there is
			-- no sensitive clipboard value to expire.
			if vim.b[event.buf].user_sensitive and vim.v.event.regname ~= "_" then
				expire_clipboard(event.buf, {
					regcontents = vim.deepcopy(vim.v.event.regcontents),
					regname = vim.v.event.regname,
					regtype = vim.v.event.regtype,
				})
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			clear_unchanged_registers(active_clipboard_snapshot)
			active_clipboard_snapshot = nil
		end,
	})
end

M.is_sensitive = is_sensitive

return M
