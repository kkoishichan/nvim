-- One semantic Escape action for short-lived UI. Prefer each plugin's own
-- lifecycle API; the constrained floating-window fallback covers native LSP
-- windows and third-party previews that expose no close function.

local M = {}
local api = vim.api

local function loaded(name)
	local module = package.loaded[name]
	return type(module) == "table" and module or nil
end

local function call(object, method, ...)
	if not object or type(object[method]) ~= "function" then
		return false
	end
	return pcall(object[method], ...)
end

local function close_blink(cmp)
	cmp = cmp or loaded("blink.cmp")
	if not cmp then
		return false
	end

	local closed = false
	local ok, visible = pcall(cmp.is_documentation_visible)
	if ok and visible then
		closed = call(cmp, "hide_documentation") or closed
	end
	ok, visible = pcall(cmp.is_signature_visible)
	if ok and visible then
		closed = call(cmp, "hide_signature") or closed
	end
	ok, visible = pcall(cmp.is_visible)
	if ok and visible then
		-- cancel() also removes ghost text and undoes an auto-insert preview.
		closed = call(cmp, "cancel") or closed
	end
	return closed
end

local function close_which_key()
	local view = loaded("which-key.view")
	if not view or type(view.valid) ~= "function" then
		return false
	end
	local ok, visible = pcall(view.valid)
	if not ok or not visible then
		return false
	end
	return call(view, "hide")
end

local function close_dictionary()
	local dictionary = loaded("user.core.dict")
	if not dictionary or type(dictionary.close) ~= "function" then
		return false
	end
	local ok, closed = pcall(dictionary.close)
	return ok and closed or false
end

local function close_transient_floats()
	local float_style = require("user.core.float_style")
	local closed = false
	for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_is_valid(winid) then
			local filetype = vim.bo[api.nvim_win_get_buf(winid)].filetype
			-- Blink and notification APIs close asynchronously and own extra state.
			local plugin_owned = vim.startswith(filetype, "blink-cmp-")
				or filetype == "notify"
				or filetype == "snacks_notif"
			if not plugin_owned and float_style.is_transient(winid) then
				local ok = pcall(api.nvim_win_close, winid, true)
				closed = ok or closed
			end
		end
	end
	return closed
end

---Dismiss every visible transient popup in the current tab.
---@param opts? { blink?: table }
---@return boolean closed
function M.close(opts)
	opts = opts or {}
	local closed = false
	closed = close_blink(opts.blink) or closed
	closed = close_dictionary() or closed
	closed = close_which_key() or closed
	closed = close_transient_floats() or closed
	return closed
end

return M
