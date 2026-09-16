local M = {}
local api = vim.api
local call = require("user.core.signature.call")
local split_arguments = call.split_arguments

---Put the LSP-selected overload first and optionally retain the alternatives.
---@param signature_help? lsp.SignatureHelp
---@param show_all boolean
---@return lsp.SignatureHelp?
function M.signature_help_view(signature_help, show_all)
	if type(signature_help) ~= "table" or type(signature_help.signatures) ~= "table" then
		return signature_help
	end

	local selected = type(signature_help.activeSignature) == "number" and signature_help.activeSignature or 0
	local active_index = selected + 1
	local active_signature = signature_help.signatures[active_index]
	if not active_signature then
		return signature_help
	end

	local signatures = { active_signature }
	if show_all then
		for index, candidate in ipairs(signature_help.signatures) do
			if index ~= active_index then
				table.insert(signatures, candidate)
			end
		end
	end

	-- Keep the server response untouched: Blink passes it back to the LSP as
	-- activeSignatureHelp when it asks again after another argument is typed.
	local view = {}
	for key, value in pairs(signature_help) do
		view[key] = value
	end
	view.signatures = signatures
	view.activeSignature = 0
	return view
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function offset_range(label, offsets)
	if
		type(label) ~= "string"
		or type(offsets) ~= "table"
		or type(offsets[1]) ~= "number"
		or type(offsets[2]) ~= "number"
		or offsets[1] < 0
		or offsets[2] <= offsets[1]
	then
		return nil
	end
	-- ParameterInformation.label offsets are UTF-16 code units, independent of
	-- the client's negotiated document position encoding. Keep newlines intact.
	local ok, first, last = pcall(function()
		return vim.str_byteindex(label, "utf-16", offsets[1], true),
			vim.str_byteindex(label, "utf-16", offsets[2], true)
	end)
	return ok and { first, last } or nil
end

local function parameter_label(signature, parameter)
	if type(parameter) ~= "table" then
		return ""
	end
	if type(parameter.label) == "string" then
		return parameter.label
	end
	local range = offset_range(signature.label, parameter.label)
	if range then
		return signature.label:sub(range[1] + 1, range[2])
	end
	return ""
end

local function label_parameter_list(label)
	local open = label:find("(", 1, true)
	if not open then
		return nil
	end
	local depth = 0
	for column = open, #label do
		local character = label:sub(column, column)
		if character == "(" then
			depth = depth + 1
		elseif character == ")" then
			depth = depth - 1
			if depth == 0 then
				local contents = label:sub(open + 1, column - 1)
				return trim(contents) == "" and {} or split_arguments(contents)
			end
		end
	end
end

local function signature_parameters(signature)
	local labels = {}
	if type(signature.parameters) == "table" then
		for _, parameter in ipairs(signature.parameters) do
			labels[#labels + 1] = parameter_label(signature, parameter)
		end
		return labels
	end
	if type(signature.label) == "string" then
		return label_parameter_list(signature.label)
	end
end

local function signature_descriptor(signature)
	local parameters = signature_parameters(signature)
	if not parameters then
		return { known_arity = false, parameters = {} }
	end
	local variadic_at
	for index, label in ipairs(parameters) do
		if label:find("...", 1, true) or label:match("^%s*%*%*?[%a_\128-\255]") then
			variadic_at = index - 1
			break
		end
	end
	return {
		known_arity = true,
		parameters = parameters,
		count = #parameters,
		variadic_at = variadic_at,
	}
end

local function signature_fit(descriptor, argument_count)
	if not descriptor.known_arity then
		return 2, math.huge
	end
	if descriptor.count >= argument_count then
		return 0, descriptor.count
	end
	if descriptor.variadic_at then
		return 1, descriptor.count
	end
	-- Nothing can make a fixed-arity overload valid once the call contains too
	-- many arguments. Still show the closest useful signature instead of an
	-- unrelated server fallback: the smallest shortfall is the largest arity.
	return 3, argument_count - descriptor.count
end

local function choose_signature(signature_help, argument_count)
	local server_index = type(signature_help.activeSignature) == "number" and signature_help.activeSignature or 0
	if server_index < 0 or server_index >= #signature_help.signatures then
		server_index = 0
	end
	local best_index
	local best_tier
	local best_rank
	for index, signature in ipairs(signature_help.signatures) do
		local descriptor = signature_descriptor(signature)
		local tier, rank = signature_fit(descriptor, argument_count)
		if
			tier
			and (
				not best_tier
				or tier < best_tier
				or (tier == best_tier and rank < best_rank)
				or (tier == best_tier and rank == best_rank and index - 1 == server_index)
			)
		then
			best_index = index - 1
			best_tier = tier
			best_rank = rank
		end
	end
	return best_index or server_index
end

local function active_parameter(signature_help, signature, call_state, filetype, server_index)
	local active = call_state.active_parameter
	local descriptor = signature_descriptor(signature)
	local argument = call_state.arguments[active + 1] or ""
	-- Python keyword order is independent of declaration order. Do not apply
	-- this to languages where `name = value` is an assignment expression.
	local name, remainder
	if filetype == "python" then
		name, remainder = argument:match("^%s*([%w_\128-\255]+)%s*=(.*)")
	end
	if name and remainder:sub(1, 1) ~= "=" then
		for index, label in ipairs(descriptor.parameters) do
			if label:match("^%s*%*?%*?([%w_\128-\255]+)") == name then
				return index - 1
			end
		end
		-- Preserve a useful server decision if its label format is unfamiliar.
		local server_parameter = signature.activeParameter
		if server_parameter == nil and (signature_help.activeSignature or 0) == server_index then
			server_parameter = signature_help.activeParameter
		end
		if
			type(server_parameter) == "number"
			and server_parameter >= 0
			and server_parameter < #descriptor.parameters
		then
			return server_parameter
		end
	end
	if descriptor.variadic_at and active >= descriptor.variadic_at then
		return descriptor.variadic_at
	end
	return active
end

---Correct stale parameter indices and select the shortest suitable
---signature that can hold the complete call. If none can, select the largest
---fixed arity as the closest useful hint. Equal candidates retain the server's
---selection, without client-side type guessing.
---@param context? blink.cmp.SignatureHelpContext
---@param signature_help? lsp.SignatureHelp
---@return lsp.SignatureHelp?
function M.normalize_signature_help(context, signature_help)
	if
		type(signature_help) ~= "table"
		or type(signature_help.signatures) ~= "table"
		or #signature_help.signatures == 0
	then
		return signature_help
	end
	local bufnr = context and context.bufnr
	if not bufnr or not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		return signature_help
	end
	local cursor = call.display_cursor(bufnr, context and context.cursor)
	local call_state = cursor and call.call_arguments(bufnr, cursor)
	if not call_state then
		return signature_help
	end

	local normalized = vim.deepcopy(signature_help)
	normalized.activeSignature = choose_signature(normalized, call_state.argument_count)
	local active_signature = normalized.signatures[normalized.activeSignature + 1]
	normalized.activeParameter = active_signature
			and active_parameter(
				signature_help,
				active_signature,
				call_state,
				vim.bo[bufnr].filetype,
				normalized.activeSignature
			)
		or call_state.active_parameter
	if active_signature then
		-- Neovim intentionally gives this signature-local field precedence over
		-- SignatureHelp.activeParameter, so both must describe the live cursor.
		active_signature.activeParameter = normalized.activeParameter
	end
	return normalized
end

---Return zero-based, end-exclusive byte offsets in the original label.
---The range can include newlines; display flattening belongs to the renderer.
function M.active_parameter_range(signature_help)
	if type(signature_help) ~= "table" or type(signature_help.signatures) ~= "table" then
		return nil
	end
	local index = type(signature_help.activeSignature) == "number" and signature_help.activeSignature or 0
	local signature = signature_help.signatures[index + 1] or signature_help.signatures[1]
	if not signature or type(signature.label) ~= "string" or type(signature.parameters) ~= "table" then
		return nil
	end
	local active = signature.activeParameter or signature_help.activeParameter
	if type(active) ~= "number" or active < 0 or active >= #signature.parameters then
		return nil
	end
	local parameter = signature.parameters[active + 1]
	if type(parameter) ~= "table" then
		return nil
	end
	if type(parameter.label) == "table" then
		return offset_range(signature.label, parameter.label)
	end
	-- Search in declaration order so repeated labels select the right instance.
	local open = signature.label:find("(", 1, true)
	local offset = open and open + 1 or 1
	for parameter_index = 1, active + 1 do
		local label = parameter_label(signature, signature.parameters[parameter_index])
		if label == "" then
			return nil
		end
		local first, last = signature.label:find(label, offset, true)
		if not first then
			return nil
		end
		if parameter_index == active + 1 then
			return { first - 1, last }
		end
		offset = last + 1
	end
end

return M
