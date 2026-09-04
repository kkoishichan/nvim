-- Stable public entry point; parsing, overloads, drawing and Blink adaptation
-- have separate ownership so an upstream UI change cannot break call parsing.
local call = require("user.core.signature.call")
local parameters = require("user.core.signature.parameters")
local render = require("user.core.signature.render")

local function dispatch(method)
	return function(...)
		return require("user.core.signature.render")[method](...)
	end
end

return setmetatable({
	find_call_anchor = call.find_call_anchor,
	call_arguments = call.call_arguments,
	display_cursor = call.display_cursor,
	signature_help_view = parameters.signature_help_view,
	normalize_signature_help = parameters.normalize_signature_help,
	setup = dispatch("setup"),
	teardown = dispatch("teardown"),
	set_expanded = dispatch("set_expanded"),
	toggle = dispatch("toggle"),
}, { __index = render, __newindex = render })
