-- Overload-aware signature rendering for the locked blink.cmp. The plugin
-- stacks every overload's label in its popup but computes the active
-- parameter range for the active signature alone and paints it on the first
-- line: when a server selects any overload but the first, the highlight lands
-- on the wrong text or the extmark call fails and the popup keeps stale
-- content. No server can choose an overload before the arguments decide it
-- (clangd and lua_ls never choose), so the editor also needs a way to cycle.
--
-- This adapter shows only the selected signature, with an "(n/m)" marker when
-- there are several, and lets <C-s> step through them. A manual choice is
-- kept for the current call as long as the server's own choice does not
-- change, and it is forwarded through `activeSignatureHelp` so servers that
-- honour the pin (vtsls) keep it on their side as well.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("user_signature_overloads")
-- The wrapper replaces window.open_with_signature_help and relies on the
-- signature handler calling it through the module table. A plugin update
-- keeps the native rendering until the adapter is revalidated.
local window_hash = "3eb92d64d9fc08127afd8cc94e514ce628e032ea3440fa2e1eda73c03c291c53"
local handler_hash = "b941e45bb7f113515af964697a5e77c567ef6dfd143face01bce1bb8fdf69f20"
local marker_format = "  (%d/%d)"

local state

local function has_source(fn, expected)
	if type(fn) ~= "function" then
		return false
	end
	local source = debug.getinfo(fn, "S").source
	local file = source:sub(1, 1) == "@" and io.open(source:sub(2), "rb") or nil
	if not file then
		return false
	end
	local text = file:read("*a")
	file:close()
	return vim.fn.sha256(text) == expected
end

local function clamp(value, count)
	if value < 1 or value > count then
		return 1
	end
	return value
end

local function server_index(help)
	return clamp((help.activeSignature or 0) + 1, #help.signatures)
end

---Render one signature of `help` through the native window. A manual choice
---for the same call survives while the server's own choice is unchanged.
local function render(context, help)
	local own = state
	if not own or not own.native_open then
		return
	end
	own.renders = (own.renders or 0) + 1
	if type(help) ~= "table" or type(help.signatures) ~= "table" or #help.signatures == 0 then
		own.last = nil
		return own.native_open(context, help)
	end
	local count = #help.signatures
	local server = server_index(help)
	local index = server
	local choice = own.choice
	if choice and context and choice.id == context.id and choice.server == server and choice.count == count then
		index = clamp(choice.index, count)
	else
		own.choice = nil
	end
	local chosen = vim.deepcopy(help.signatures[index])
	local marker = count > 1 and marker_format:format(index, count) or nil
	if marker then
		chosen.label = chosen.label .. marker
	end
	own.last = { context = context, help = help, index = index, count = count }
	own.native_open(context, {
		signatures = { chosen },
		activeSignature = 0,
		activeParameter = help.activeParameter,
	})
	local win = own.window.win
	if not win:is_open() then
		return
	end
	-- Blink rewrites the buffer but only clears its own marks; drop the
	-- previous marker before deciding whether this answer gets one.
	local buf = win:get_buf()
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if not marker then
		return
	end
	-- The marker shares the label's Tree-sitter colours; give it its own.
	local rows = vim.split(chosen.label, "\n", { plain = true })
	local row = #rows - 1
	local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	if line:sub(-#marker) == marker then
		local text = marker:match("%S.*$")
		api.nvim_buf_set_extmark(buf, ns, row, #line - #text, {
			end_col = #line,
			hl_group = "BlinkCmpSignatureHelpOverload",
			priority = vim.hl.priorities.user,
		})
	end
end

---Forward a manual choice for the next retrigger of the same call.
local function pin(help, index)
	local ok, trigger = pcall(require, "blink.cmp.signature.trigger")
	if ok and type(trigger.set_active_signature_help) == "function" then
		trigger.set_active_signature_help(vim.tbl_extend("force", help, { activeSignature = index - 1 }))
	end
end

---Step through the overloads of the signature currently shown.
---@param step integer|nil defaults to 1
---@return boolean handled
function M.cycle(step)
	local own = state
	local last = own and own.last
	if not last or last.count < 2 or not own.window.win:is_open() then
		return false
	end
	local ok, trigger = pcall(require, "blink.cmp.signature.trigger")
	if not ok or not trigger.context or trigger.context.id ~= last.context.id then
		return false
	end
	local index = (last.index - 1 + (step or 1)) % last.count + 1
	own.choice = { id = last.context.id, index = index, server = server_index(last.help), count = last.count }
	render(last.context, last.help)
	pin(last.help, index)
	return true
end

---What the popup currently shows, for reports and checks.
---@return { index: integer, count: integer }|nil
function M.shown()
	local last = state and state.last
	return last and { index = last.index, count = last.count } or nil
end

---How many answers the adapter has rendered, so checks can wait for one.
function M.renders()
	return state and state.renders or 0
end

function M.active()
	return state ~= nil and state.installed == true
end

local function install()
	local own = state
	if not own or own.installed then
		return
	end
	local window = require("blink.cmp.signature.window")
	if not has_source(window.open_with_signature_help, window_hash) then
		own.reason = "blink.cmp signature window changed"
		if own.reported then
			require("user.core.adapters").record("signature_overloads", false, own.reason)
		end
		return
	end
	own.window, own.native_open = window, window.open_with_signature_help
	window.open_with_signature_help = render
	window._user_signature_overloads = M
	own.installed = true
end

function M.shutdown()
	local own = state
	state = nil
	if not own then
		return
	end
	if own.window and own.window.open_with_signature_help == render then
		own.window.open_with_signature_help = own.native_open
	end
	if own.window and own.window._user_signature_overloads == M then
		own.window._user_signature_overloads = nil
	end
	if own.handler and own.handler.setup == own.wrapped_setup then
		own.handler.setup = own.native_setup
	end
	if own.handler and own.handler._user_signature_overloads == M then
		own.handler._user_signature_overloads = nil
	end
end

---Call after blink.cmp's setup. Its signature handler starts asynchronously,
---so the window is wrapped when that handler runs (or at once if it already
---has). Returns true when active, or false and a reason.
---@return boolean, string|nil
function M.setup()
	local handler = require("blink.cmp.signature")
	local previous = handler._user_signature_overloads
		or (package.loaded["blink.cmp.signature.window"] or {})._user_signature_overloads
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	if not has_source(handler.setup, handler_hash) then
		return false, "blink.cmp signature handler changed"
	end
	state = { handler = handler, native_setup = handler.setup }
	local own = state
	own.wrapped_setup = function(...)
		local result = own.native_setup(...)
		if state == own then
			install()
		end
		return result
	end
	handler.setup = own.wrapped_setup
	handler._user_signature_overloads = M
	if package.loaded["blink.cmp.signature.window"] then
		install()
		if not own.installed then
			local reason = own.reason
			M.shutdown()
			return false, reason
		end
	end
	-- The registry hears about the outcome now; a later hash failure in the
	-- asynchronous install re-records the adapter as inactive.
	own.reported = true
	return true
end

return M
