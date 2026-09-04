-- All Blink internals used by the custom renderer are checked at this boundary.
local M = {}
local installed
local marker = "_user_signature_adapter"

local function methods(value, names)
	if type(value) ~= "table" then
		return false
	end
	for _, name in ipairs(names) do
		if type(value[name]) ~= "function" then
			return false
		end
	end
	return true
end

function M.probe()
	local ok, capabilities = pcall(function()
		local window = require("blink.cmp.signature.window")
		local trigger = require("blink.cmp.signature.trigger")
		local config = require("blink.cmp.config").signature.window
		local docs = require("blink.cmp.lib.window.docs")
		assert(methods(window, { "open_with_signature_help", "update_position", "close" }))
		assert(methods(window.win, {
			"is_open",
			"get_buf",
			"get_win",
			"update_size",
			"get_content_width",
			"get_content_height",
			"set_width",
			"set_height",
			"get_vertical_direction_and_height",
		}))
		assert(type(window.win.config) == "table" and type(config) == "table", "Missing Blink window configuration")
		assert(methods(trigger, { "show", "set_active_signature_help" }))
		assert(methods(trigger.hide_emitter, { "on", "off" }))
		assert(methods(docs, { "split_lines" }))
		return { window = window, trigger = trigger, config = config, docs = docs }
	end)
	if not ok then
		return nil, "Blink signature internals unavailable; using standard signature help"
	end
	return capabilities
end

function M.current()
	return installed
end

function M.menu()
	local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")
	if ok and type(menu) == "table" and methods(menu.win, { "is_open", "get_win" }) then
		return menu
	end
end

function M.install(capabilities, hooks)
	local window, trigger = capabilities.window, capabilities.trigger
	-- The marker survives reloading this module: the previous owner can release
	-- its callbacks before a new one captures the unmodified Blink functions.
	local previous = window[marker]
	if previous then
		previous.teardown()
	end
	M.teardown()
	local original_open, original_update = window.open_with_signature_help, window.update_position
	local config_height, window_height = capabilities.config.max_height, window.win.config.max_height
	local open = function(...)
		return hooks.open(original_open, ...)
	end
	local update = function(...)
		return hooks.update(original_update, ...)
	end
	local released = false
	local state = capabilities
	state.teardown = function()
		if released then
			return
		end
		released = true
		hooks.teardown()
		trigger.hide_emitter:off(hooks.hide)
		if window.open_with_signature_help == open then
			window.open_with_signature_help = original_open
		end
		if window.update_position == update then
			window.update_position = original_update
		end
		capabilities.config.max_height = config_height
		window.win.config.max_height = window_height
		if window[marker] == state then
			window[marker] = nil
		end
		if installed == state then
			installed = nil
		end
	end
	window.open_with_signature_help = open
	window.update_position = update
	trigger.hide_emitter:on(hooks.hide)
	window[marker] = state
	installed = state
	return state
end

function M.teardown()
	if installed then
		installed.teardown()
	else
		local window = package.loaded["blink.cmp.signature.window"]
		if type(window) == "table" and window[marker] then
			window[marker].teardown()
		end
	end
end

-- Called from a scheduled mapping callback, so both public fallbacks are safe
-- from expression-map textlock. No internal module is needed for this path.
function M.fallback(cmp)
	if type(cmp) == "table" and type(cmp.show_signature) == "function" then
		local ok, shown = pcall(cmp.show_signature)
		if ok and shown then
			return true
		end
	end
	vim.lsp.buf.signature_help()
	return true
end

return M
