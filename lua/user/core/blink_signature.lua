local M = {
	compact_height = 1,
	indicator = "󰊕",
	virtual_indicator = "◀",
}

local api = vim.api
local virtual_namespace = api.nvim_create_namespace("user_blink_signature")
local anchor_namespace = api.nvim_create_namespace("user_blink_signature_anchor")
local full_indicator_namespace = api.nvim_create_namespace("user_blink_signature_full_indicator")
local expanded = false
local last_context
local last_signature_help
local virtual_buffer
local full_indicator_buffer
local signature_anchor
local cached_syntax_key
local cached_syntax_spans
local refresh_scheduled = false
local discovery_generation = 0
local last_text_change
local redraw_current_signature

local function full_height()
	return math.max(1, vim.api.nvim_win_get_height(0))
end

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

local function append_chunk(chunks, text, highlights)
	if text == "" then
		return
	end
	local previous = chunks[#chunks]
	if previous and vim.deep_equal(previous[2], highlights) then
		previous[1] = previous[1] .. text
	else
		chunks[#chunks + 1] = { text, highlights }
	end
end

local function syntax_spans(text, filetype)
	local language = vim.treesitter.language.get_lang(filetype)
	if not language or text == "" then
		return {}
	end

	local cache_key = language .. "\0" .. text
	if cache_key == cached_syntax_key then
		return cached_syntax_spans
	end

	local ok, spans = pcall(function()
		local parser = vim.treesitter.get_string_parser(text, language)
		local tree = parser:parse()[1]
		local query = vim.treesitter.query.get(language, "highlights")
		if not tree or not query then
			return {}
		end

		local captures = {}
		local order = 0
		for capture, node, metadata in query:iter_captures(tree:root(), text, 0, -1) do
			local name = query.captures[capture]
			if name and not vim.startswith(name, "_") then
				order = order + 1
				local capture_metadata = metadata and metadata[capture]
				local range = vim.treesitter.get_range(node, text, capture_metadata)
				local start_row, start_col = range[1], range[2]
				local end_row, end_col = range[4], range[5]
				if start_row == 0 and end_row == 0 and end_col > start_col then
					captures[#captures + 1] = {
						start_col = start_col,
						end_col = end_col,
						highlight = "@" .. name .. "." .. language,
						priority = tonumber(
							(capture_metadata and capture_metadata.priority) or (metadata and metadata.priority)
						) or vim.hl.priorities.treesitter,
						order = order,
					}
				end
			end
		end
		return captures
	end)

	cached_syntax_key = cache_key
	cached_syntax_spans = ok and spans or {}
	return cached_syntax_spans
end

---Build syntax-coloured virtual text and retain Blink's active-parameter mark.
---@param label string
---@param filetype string
---@param active_range? integer[] Zero-based, end-exclusive byte range.
---@return table[]
function M.virtual_chunks(label, filetype, active_range)
	local spans = syntax_spans(label, filetype)
	local boundary_set = { [0] = true, [#label] = true }
	for _, span in ipairs(spans) do
		boundary_set[span.start_col] = true
		boundary_set[span.end_col] = true
	end

	local active_start
	local active_end
	if
		type(active_range) == "table"
		and type(active_range[1]) == "number"
		and type(active_range[2]) == "number"
		and active_range[1] >= 0
		and active_range[2] > active_range[1]
		and active_range[2] <= #label
	then
		active_start = active_range[1]
		active_end = active_range[2]
		boundary_set[active_start] = true
		boundary_set[active_end] = true
	end

	local boundaries = vim.tbl_keys(boundary_set)
	table.sort(boundaries)
	local chunks = {
		{ " ", "BlinkCmpSignatureVirtual" },
		{
			M.virtual_indicator .. " ",
			{ "BlinkCmpSignatureVirtualIndicator", "BlinkCmpSignatureVirtual" },
		},
	}
	for index = 1, #boundaries - 1 do
		local start_col = boundaries[index]
		local end_col = boundaries[index + 1]
		local winner
		for _, span in ipairs(spans) do
			if span.start_col <= start_col and span.end_col >= end_col then
				if
					not winner
					or span.priority > winner.priority
					or (span.priority == winner.priority and span.order > winner.order)
				then
					winner = span
				end
			end
		end

		local highlights = {
			winner and winner.highlight or "BlinkCmpSignatureHelp",
			"BlinkCmpSignatureVirtual",
		}
		if active_start and start_col >= active_start and end_col <= active_end then
			highlights[#highlights + 1] = "BlinkCmpSignatureHelpActiveParameter"
		end
		append_chunk(chunks, label:sub(start_col + 1, end_col), highlights)
	end
	append_chunk(chunks, " ", "BlinkCmpSignatureVirtual")
	return chunks
end

local function completion_visible()
	local blink = package.loaded["blink.cmp"]
	if not blink or type(blink.is_menu_visible) ~= "function" then
		return false
	end
	local ok, visible = pcall(blink.is_menu_visible)
	return ok and visible or false
end

---Choose a nearby physical line and pad its EOL to align the card with the
---stable call anchor. A neighbouring line is available when the anchor
---cell itself is empty; the remaining width of the window is deliberately not
---part of this decision.
---@param bufnr integer
---@param anchor integer[]
---@param preferred_side? integer -1 above, 0 current line, 1 below.
---@param fallback_row? integer Zero-based live cursor row for the inline case.
---@return integer row
---@return string padding
---@return integer side
function M.virtual_position(bufnr, anchor, preferred_side, fallback_row)
	local anchor_row = anchor[1] - 1
	local line_count = api.nvim_buf_line_count(bufnr)
	local anchor_line = api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)[1] or ""
	local anchor_width = vim.fn.strdisplaywidth(anchor_line:sub(1, anchor[2]))
	fallback_row = fallback_row or anchor_row

	local function candidate(side)
		local row = anchor_row + side
		if row < 0 or row >= line_count then
			return nil
		end
		local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
		local line_width = vim.fn.strdisplaywidth(line)
		if line_width > anchor_width then
			return nil
		end
		return string.rep(" ", anchor_width - line_width)
	end

	if preferred_side == 0 then
		return fallback_row, "", 0
	end
	if preferred_side == -1 or preferred_side == 1 then
		local padding = candidate(preferred_side)
		if padding then
			return anchor_row + preferred_side, padding, preferred_side
		end
	end

	local padding = candidate(-1)
	if padding then
		return anchor_row - 1, padding, -1
	end
	if not completion_visible() then
		padding = candidate(1)
		if padding then
			return anchor_row + 1, padding, 1
		end
	end
	return fallback_row, "", 0
end

local function clear_virtual()
	if virtual_buffer and api.nvim_buf_is_valid(virtual_buffer) then
		api.nvim_buf_clear_namespace(virtual_buffer, virtual_namespace, 0, -1)
	end
	virtual_buffer = nil
end

local function clear_full_indicators()
	if full_indicator_buffer and api.nvim_buf_is_valid(full_indicator_buffer) then
		api.nvim_buf_clear_namespace(full_indicator_buffer, full_indicator_namespace, 0, -1)
	end
	full_indicator_buffer = nil
end

---Add the function marker to the first physical line of every rendered
---overload. Multiline signature continuations and documentation remain plain.
local function render_full_indicators(signature_window, signature_help)
	clear_full_indicators()
	if
		not signature_window.win:is_open()
		or type(signature_help) ~= "table"
		or type(signature_help.signatures) ~= "table"
	then
		return
	end

	local bufnr = signature_window.win:get_buf()
	local docs = require("blink.cmp.lib.window.docs")
	local seen = {}
	local row = 0
	for _, signature in ipairs(signature_help.signatures) do
		local label = signature.label
		if type(label) == "string" and not seen[label] then
			seen[label] = true
			local lines = docs.split_lines(label)
			if #lines > 0 then
				api.nvim_buf_set_extmark(bufnr, full_indicator_namespace, row, 0, {
					virt_text = { { M.indicator .. " ", "BlinkCmpSignatureIndicator" } },
					virt_text_pos = "inline",
					hl_mode = "combine",
					priority = vim.hl.priorities.user,
				})
				row = row + #lines
			end
		end
	end
	full_indicator_buffer = bufnr
end

local function clear_anchor()
	if signature_anchor and api.nvim_buf_is_valid(signature_anchor.bufnr) then
		api.nvim_buf_clear_namespace(signature_anchor.bufnr, anchor_namespace, 0, -1)
	end
	signature_anchor = nil
end

local function source_window(bufnr)
	local current = api.nvim_get_current_win()
	if api.nvim_win_get_buf(current) == bufnr then
		return current
	end
	local winid = vim.fn.bufwinid(bufnr)
	return winid ~= -1 and winid or nil
end

local function node_start(node)
	local row, col = node:range()
	return { row + 1, col }
end

local function node_field(node, name)
	local ok, nodes = pcall(node.field, node, name)
	return ok and nodes and nodes[1] or nil
end

local function position_before(left, right)
	return left[1] < right[1] or (left[1] == right[1] and left[2] < right[2])
end

---Find the syntax node immediately before an opening parenthesis. This also
---covers a just-typed, temporarily incomplete call such as `torch.arange(`.
local function callee_before_parenthesis(root, bufnr, row, open_col)
	if open_col <= 0 then
		return nil
	end

	local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	local probe_col = open_col - 1
	while probe_col > 0 and line:sub(probe_col + 1, probe_col + 1):match("%s") do
		probe_col = probe_col - 1
	end
	if root then
		local candidate = root:named_descendant_for_range(row, probe_col, row, probe_col)
		while candidate do
			local _, _, end_row, end_col = candidate:range()
			if end_row < row or (end_row == row and end_col <= open_col) then
				local parent = candidate:parent()
				if not parent then
					break
				end
				local _, _, parent_end_row, parent_end_col = parent:range()
				if parent_end_row < row or (parent_end_row == row and parent_end_col <= open_col) then
					candidate = parent
				else
					return node_start(candidate)
				end
			else
				break
			end
		end
	end

	-- If the parser has not recovered from the new `(` yet, retain common
	-- qualified names as one callable (`torch.arange`, `object:method`).
	local prefix = line:sub(1, open_col)
	local start_col = prefix:find("[%a_][%w_%.:]*%s*$")
	return start_col and { row + 1, start_col - 1 } or nil
end

local function lexical_call_site(bufnr, cursor)
	local cursor_row = cursor[1] - 1
	local first_row = math.max(0, cursor_row - 199)
	local lines = api.nvim_buf_get_lines(bufnr, first_row, cursor_row + 1, false)
	local stack = {}
	local state = "code"
	local quote
	local escaped = false

	for line_index, line in ipairs(lines) do
		local row = first_row + line_index - 1
		local limit = row == cursor_row and math.min(cursor[2], #line) or #line
		local column = 1
		while column <= limit do
			local character = line:sub(column, column)
			local following = line:sub(column + 1, column + 1)
			if state == "block_comment" then
				if character == "*" and following == "/" then
					state = "code"
					column = column + 1
				end
			elseif state == "string" then
				if escaped then
					escaped = false
				elseif character == "\\" then
					escaped = true
				elseif character == quote then
					state = "code"
					quote = nil
				end
			elseif
				(character == "/" and following == "/")
				or (character == "-" and following == "-")
				or character == "#"
			then
				break
			elseif character == "/" and following == "*" then
				state = "block_comment"
				column = column + 1
			elseif character == '"' or character == "'" or character == "`" then
				state = "string"
				quote = character
				escaped = false
			elseif character == "(" or character == "[" or character == "{" then
				local anchor
				if character == "(" then
					local prefix = line:sub(1, column - 1)
					local start_col = prefix:find("[%a_][%w_%.:]*%s*$")
					if start_col then
						anchor = { row + 1, start_col - 1 }
					end
				end
				stack[#stack + 1] = {
					character = character,
					open = { row + 1, column - 1 },
					anchor = anchor,
				}
			elseif character == ")" or character == "]" or character == "}" then
				local matching = character == ")" and "(" or character == "]" and "[" or "{"
				if stack[#stack] and stack[#stack].character == matching then
					table.remove(stack)
				end
			end
			column = column + 1
		end
		if state == "string" then
			state = "code"
			quote = nil
			escaped = false
		end
	end

	for index = #stack, 1, -1 do
		local candidate = stack[index]
		if candidate.character == "(" and candidate.anchor then
			return candidate
		end
	end
end

local function find_call_site(bufnr, cursor)
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		return nil
	end
	local row = cursor[1] - 1
	local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
	if not line then
		return nil
	end
	local node_col = math.max(0, math.min(cursor[2], math.max(0, #line - 1)))
	local ok, root, node = pcall(function()
		local parser = vim.treesitter.get_parser(bufnr)
		local tree = parser:parse()[1]
		local tree_root = tree and tree:root() or nil
		return tree_root, tree_root and tree_root:named_descendant_for_range(row, node_col, row, node_col) or nil
	end)
	if not ok then
		root = nil
		node = nil
	end

	while node do
		local node_type = node:type()
		if node_type == "arguments" or node_type:find("argument", 1, true) then
			local start_row, start_col = node:range()
			local opening = api.nvim_buf_get_text(bufnr, start_row, start_col, start_row, start_col + 1, {})[1]
			if opening == "(" then
				local parent = node:parent()
				local callee = parent and (node_field(parent, "function") or node_field(parent, "name"))
				callee = callee or node:prev_named_sibling()
				local anchor = callee and node_start(callee)
					or callee_before_parenthesis(root, bufnr, start_row, start_col)
				if anchor then
					return {
						anchor = anchor,
						open = { start_row + 1, start_col },
						argument_node = node,
					}
				end
			end
		end
		node = node:parent()
	end

	-- A just-typed `(` may not have an argument-list node yet. The lexical
	-- fallback also covers multiline calls when a parser is unavailable.
	return lexical_call_site(bufnr, cursor)
end

---Find the innermost call containing the cursor and return the beginning of
---its callable expression (for example `inner` or `torch` in `torch.arange`).
---@param bufnr integer
---@param cursor integer[] (1,0)-indexed buffer cursor.
---@return integer[]?
function M.find_call_anchor(bufnr, cursor)
	local site = find_call_site(bufnr, cursor)
	return site and site.anchor or nil
end

local function text_between(bufnr, start_position, end_position)
	if position_before(end_position, start_position) then
		return ""
	end
	local lines =
		api.nvim_buf_get_text(bufnr, start_position[1] - 1, start_position[2], end_position[1] - 1, end_position[2], {})
	return table.concat(lines, "\n")
end

local function looks_like_template_open(text, column)
	local previous = text:sub(column - 1, column - 1)
	if not previous:match("[%w_:>]") then
		return false
	end
	local following = text:sub(column + 1):match("^%s*(.)")
	return following ~= nil and following:match("[%w_:]") ~= nil and text:find(">", column + 1, true) ~= nil
end

local function split_arguments(text)
	local arguments = {}
	local start_col = 1
	local stack = {}
	local state = "code"
	local quote
	local escaped = false
	local column = 1

	while column <= #text do
		local character = text:sub(column, column)
		local following = text:sub(column + 1, column + 1)
		if state == "line_comment" then
			if character == "\n" then
				state = "code"
			end
		elseif state == "block_comment" then
			if character == "*" and following == "/" then
				state = "code"
				column = column + 1
			end
		elseif state == "string" then
			if escaped then
				escaped = false
			elseif character == "\\" then
				escaped = true
			elseif character == quote then
				state = "code"
				quote = nil
			end
		elseif (character == "/" and following == "/") or (character == "-" and following == "-") then
			state = "line_comment"
			column = column + 1
		elseif character == "#" then
			state = "line_comment"
		elseif character == "/" and following == "*" then
			state = "block_comment"
			column = column + 1
		elseif character == '"' or character == "'" or character == "`" then
			state = "string"
			quote = character
			escaped = false
		elseif character == ">" and stack[#stack] == "<" then
			table.remove(stack)
		elseif
			character == "("
			or character == "["
			or character == "{"
			or (character == "<" and looks_like_template_open(text, column))
		then
			stack[#stack + 1] = character
		elseif character == ")" or character == "]" or character == "}" then
			local matching = character == ")" and "(" or character == "]" and "[" or "{"
			if stack[#stack] == matching then
				table.remove(stack)
			end
		elseif character == "," and #stack == 0 then
			arguments[#arguments + 1] = text:sub(start_col, column - 1)
			start_col = column + 1
		end
		column = column + 1
	end

	arguments[#arguments + 1] = text:sub(start_col)
	return arguments
end

---Read both the cursor's parameter index and the complete argument list.
---They must remain independent: moving inside an existing call changes the
---highlighted parameter, but must not make later arguments disappear when an
---overload is chosen.
---@param bufnr integer
---@param cursor integer[] (1,0)-indexed buffer cursor.
---@return { active_parameter: integer, argument_count: integer, arguments: string[], anchor: integer[], open: integer[] }?
function M.call_arguments(bufnr, cursor)
	local site = find_call_site(bufnr, cursor)
	if not site then
		return nil
	end
	local argument_start = { site.open[1], site.open[2] + 1 }
	if position_before(cursor, argument_start) then
		return nil
	end

	local cursor_arguments = split_arguments(text_between(bufnr, argument_start, cursor))
	local arguments = cursor_arguments
	if site.argument_node then
		local node_text = vim.treesitter.get_node_text(site.argument_node, bufnr)
		if type(node_text) == "string" and node_text:sub(1, 1) == "(" then
			node_text = node_text:sub(2)
			if node_text:sub(-1) == ")" then
				node_text = node_text:sub(1, -2)
			end
			arguments = split_arguments(node_text)
		end
	end
	local argument_count = #arguments
	if argument_count == 1 and arguments[1]:match("^%s*$") then
		argument_count = 0
	end

	return {
		active_parameter = #cursor_arguments - 1,
		argument_count = argument_count,
		arguments = arguments,
		anchor = site.anchor,
		open = site.open,
	}
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parameter_label(signature, parameter)
	if type(parameter) ~= "table" then
		return ""
	end
	if type(parameter.label) == "string" then
		return parameter.label
	end
	if
		type(parameter.label) == "table"
		and type(parameter.label[1]) == "number"
		and type(parameter.label[2]) == "number"
		and type(signature.label) == "string"
	then
		return signature.label:sub(parameter.label[1] + 1, parameter.label[2])
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
		if label:find("...", 1, true) or label:match("^%s*%*%*?[%a_]") then
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
		if tier and (not best_tier or tier < best_tier or (tier == best_tier and rank < best_rank)) then
			best_index = index - 1
			best_tier = tier
			best_rank = rank
		end
	end
	return best_index or server_index
end

---Correct stale parameter indices and select the shortest server-ordered
---signature that can hold the complete call. If none can, select the largest
---fixed arity as the closest useful hint. No client-side type guessing is
---performed.
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
	local cursor = M.display_cursor(bufnr, context and context.cursor)
	local call = cursor and M.call_arguments(bufnr, cursor)
	if not call then
		return signature_help
	end

	local normalized = vim.deepcopy(signature_help)
	normalized.activeParameter = call.active_parameter
	normalized.activeSignature = choose_signature(normalized, call.argument_count)
	local active_signature = normalized.signatures[normalized.activeSignature + 1]
	if active_signature then
		-- Neovim intentionally gives this signature-local field precedence over
		-- SignatureHelp.activeParameter, so both must describe the live cursor.
		active_signature.activeParameter = call.active_parameter
	end
	return normalized
end

local function anchor_position()
	if not signature_anchor or not api.nvim_buf_is_valid(signature_anchor.bufnr) then
		return nil
	end
	local position = api.nvim_buf_get_extmark_by_id(signature_anchor.bufnr, anchor_namespace, signature_anchor.mark, {})
	if #position ~= 2 then
		return nil
	end
	return { position[1] + 1, position[2] }
end

local function same_position(left, right)
	return left and right and left[1] == right[1] and left[2] == right[2]
end

local function set_signature_anchor(context, cursor)
	clear_anchor()
	local bufnr = context.bufnr
	local row = math.max(0, math.min(cursor[1] - 1, api.nvim_buf_line_count(bufnr) - 1))
	local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	local col = math.max(0, math.min(cursor[2], #line))
	signature_anchor = {
		bufnr = bufnr,
		context_id = context.id,
		mark = api.nvim_buf_set_extmark(bufnr, anchor_namespace, row, col, {
			right_gravity = false,
		}),
		source_win = source_window(bufnr),
	}
	return { row + 1, col }
end

local function active_parameter_range(signature_help, filetype)
	local ok, _, range = pcall(vim.lsp.util.convert_signature_help_to_markdown_lines, signature_help, filetype, {})
	if
		ok
		and type(range) == "table"
		and range[1] == 1
		and range[3] == 1
		and type(range[2]) == "number"
		and type(range[4]) == "number"
	then
		return { range[2], range[4] }
	end
end

---Use the live insertion cursor when the signature belongs to the active
---buffer. Blink's context cursor is a request snapshot and remains stale while
---ordinary argument characters are typed.
---@param bufnr integer
---@param fallback? integer[]
---@return integer[]?
function M.display_cursor(bufnr, fallback)
	local winid = api.nvim_get_current_win()
	if api.nvim_win_get_buf(winid) == bufnr then
		return api.nvim_win_get_cursor(winid)
	end
	return fallback
end

local function update_signature_anchor(context)
	if type(context) ~= "table" or not api.nvim_buf_is_valid(context.bufnr) then
		return nil
	end
	local live_cursor = M.display_cursor(context.bufnr, context.cursor)
	local candidate = live_cursor and M.find_call_anchor(context.bufnr, live_cursor)
	if not candidate and context.cursor and not same_position(context.cursor, live_cursor) then
		candidate = M.find_call_anchor(context.bufnr, context.cursor)
	end

	local existing = anchor_position()
	local same_context = signature_anchor
		and signature_anchor.bufnr == context.bufnr
		and signature_anchor.context_id == context.id
	if same_context then
		if candidate and not same_position(candidate, existing) then
			return set_signature_anchor(context, candidate)
		end
		return existing
	end

	return set_signature_anchor(context, candidate or live_cursor or context.cursor)
end

local function reset_full_layout()
	if signature_anchor then
		signature_anchor.full_win = nil
		signature_anchor.full_direction = nil
		signature_anchor.full_height = nil
	end
end

local function infer_full_direction(winid, source_win)
	local config = api.nvim_win_get_config(winid)
	if config.relative == "cursor" then
		return config.row < 0 and -1 or 1
	end
	local popup_top = api.nvim_win_get_position(winid)[1]
	local source_top = api.nvim_win_get_position(source_win)[1]
	local cursor_row = api.nvim_win_call(source_win, vim.fn.winline) - 1
	return popup_top < source_top + cursor_row and -1 or 1
end

---Return the completion menu side relative to the source cursor.
---@return integer? side -1 above, 1 below.
local function completion_direction(source_win)
	local cursor = api.nvim_win_get_cursor(source_win)
	local cursor_screen_row = vim.fn.screenpos(source_win, cursor[1], cursor[2] + 1).row
	local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")
	if ok and menu.win:is_open() then
		local menu_top = api.nvim_win_get_position(menu.win:get_win())[1] + 1
		return menu_top < cursor_screen_row and -1 or 1
	end

	local popupmenu = vim.fn.pum_getpos()
	if vim.fn.pumvisible() == 1 and popupmenu.row ~= nil then
		return popupmenu.row + 1 < cursor_screen_row and -1 or 1
	end
end

local function update_full_window_size(win)
	win:update_size()
	if full_indicator_buffer ~= win:get_buf() then
		return
	end

	local width = win:get_content_width() + vim.fn.strdisplaywidth(M.indicator .. " ")
	width = math.max(width, win.config.min_width or 1)
	if win.config.max_width then
		width = math.min(width, win.config.max_width)
	end
	win:set_width(width)
	win:set_height(math.max(1, math.min(win:get_content_height(), win.config.max_height)))
end

---Let Blink choose the full window's size and side once, then convert its
---cursor-relative position into a buffer-relative call anchor. Later cursor
---movement may update the contents but cannot move the window.
local function position_full_window(signature_window, original_update)
	local position = anchor_position()
	local win = signature_window.win
	if not position or not signature_anchor or not win:is_open() then
		return original_update()
	end

	local source_win = signature_anchor.source_win
	if
		not source_win
		or not api.nvim_win_is_valid(source_win)
		or api.nvim_win_get_buf(source_win) ~= signature_anchor.bufnr
	then
		source_win = source_window(signature_anchor.bufnr)
		signature_anchor.source_win = source_win
	end
	if not source_win then
		return original_update()
	end

	local winid = win:get_win()
	local menu_direction = completion_direction(source_win)
	local opposite_direction = menu_direction and -menu_direction or nil
	local needs_fresh_layout = signature_anchor.full_win ~= winid or not signature_anchor.full_direction
	if needs_fresh_layout then
		original_update()
		if not win:is_open() then
			return
		end
		winid = win:get_win()
		local constrained_height = api.nvim_win_get_height(winid)
		update_full_window_size(win)
		win:set_height(math.min(constrained_height, api.nvim_win_get_height(winid)))
		signature_anchor.full_win = winid
		signature_anchor.full_direction = opposite_direction or infer_full_direction(winid, source_win)
		signature_anchor.full_height = api.nvim_win_get_height(winid)
	else
		update_full_window_size(win)
		if opposite_direction then
			local direction = opposite_direction == -1 and "n" or "s"
			local layout = win:get_vertical_direction_and_height({ direction }, win.config.max_height)
			if layout then
				signature_anchor.full_direction = opposite_direction
				signature_anchor.full_height = layout.height
				win:set_height(layout.height)
			end
		else
			win:set_height(math.min(signature_anchor.full_height, api.nvim_win_get_height(winid)))
		end
	end

	local above = signature_anchor.full_direction == -1
	api.nvim_win_set_config(winid, {
		relative = "win",
		win = source_win,
		bufpos = { position[1] - 1, position[2] },
		anchor = above and "SW" or "NW",
		row = above and 0 or 1,
		col = 0,
	})
end

local function render_virtual(context, signature_help, already_normalized)
	clear_virtual()
	if not already_normalized then
		signature_help = M.normalize_signature_help(context, signature_help)
	end
	local view = M.signature_help_view(signature_help, false)
	local active_signature = view and view.signatures and view.signatures[1]
	if not active_signature or type(active_signature.label) ~= "string" then
		return false
	end

	local bufnr = context and context.bufnr or api.nvim_get_current_buf()
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		return false
	end
	local cursor = M.display_cursor(bufnr, context and context.cursor)
	if not cursor then
		return false
	end
	local live_row = cursor[1] - 1
	if live_row < 0 or live_row >= api.nvim_buf_line_count(bufnr) then
		return false
	end
	local anchor = anchor_position() or update_signature_anchor(context)
	if not anchor then
		return false
	end

	local label = active_signature.label
	local filetype = vim.bo[bufnr].filetype
	local range = not label:find("[\r\n]") and active_parameter_range(view, filetype) or nil
	label = label:gsub("\r\n", " "):gsub("[\r\n]", " ")
	local preferred_side = signature_anchor and signature_anchor.virtual_side or nil
	local show_row, padding, side = M.virtual_position(bufnr, anchor, preferred_side, live_row)
	if signature_anchor then
		signature_anchor.virtual_side = side
	end
	local chunks = M.virtual_chunks(label, filetype, range)
	if side ~= 0 and padding ~= "" then
		table.insert(chunks, 1, { padding, "Normal" })
	end
	local placement_line = api.nvim_buf_get_lines(bufnr, show_row, show_row + 1, false)[1] or ""
	api.nvim_buf_set_extmark(bufnr, virtual_namespace, show_row, #placement_line, {
		virt_text = chunks,
		-- "eol" renders after Neovim's EOL screen cell, leaving a visible gap
		-- outside the card. Inline at the final byte column starts immediately.
		virt_text_pos = "inline",
		hl_mode = "combine",
		priority = vim.hl.priorities.user,
	})
	virtual_buffer = bufnr
	return true
end

local function redraw_virtual_at_cursor()
	if not last_context or not last_signature_help then
		return false
	end
	if api.nvim_get_current_buf() ~= last_context.bufnr then
		return false
	end
	if expanded then
		return redraw_current_signature()
	end
	return render_virtual(last_context, last_signature_help)
end

local function schedule_signature_refresh()
	if refresh_scheduled then
		return
	end
	refresh_scheduled = true
	vim.schedule(function()
		refresh_scheduled = false
		redraw_virtual_at_cursor()
	end)
end

---Ask Blink to discover signature help after moving into an existing call.
---Blink normally requests automatically only after an LSP trigger character,
---so a short debounce fills the cursor-navigation gap without requesting on
---every character typed.
---@param bufnr integer
local function schedule_signature_discovery(bufnr)
	discovery_generation = discovery_generation + 1
	local generation = discovery_generation
	vim.defer_fn(function()
		if generation ~= discovery_generation or api.nvim_get_current_buf() ~= bufnr then
			return
		end
		local mode = api.nvim_get_mode().mode:sub(1, 1)
		if mode ~= "i" and mode ~= "s" then
			return
		end
		if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/signatureHelp" }) == 0 then
			return
		end

		local trigger = require("blink.cmp.signature.trigger")
		if not trigger.context then
			trigger.show({ force = true })
		end
	end, 60)
end

redraw_current_signature = function()
	local signature_window = require("blink.cmp.signature.window")
	if not last_context or not last_signature_help then
		return false
	end

	-- Blink otherwise skips rendering when the active signature object did not
	-- change, even though we switched between the compact and complete views.
	signature_window.shown_signature = nil
	signature_window.open_with_signature_help(last_context, last_signature_help)
	return true
end

local function apply_height()
	local height = expanded and full_height() or M.compact_height
	local signature_config = require("blink.cmp.config").signature.window
	local signature_window = require("blink.cmp.signature.window")

	-- Blink copies max_height into its generic window object during setup, while
	-- its positioning code keeps reading the signature config. Keep both in sync.
	signature_config.max_height = height
	signature_window.win.config.max_height = height
	return signature_window
end

---@param value boolean
function M.set_expanded(value)
	expanded = value
	local signature_window = apply_height()
	if not redraw_current_signature() and signature_window.win:is_open() then
		vim.schedule(signature_window.update_position)
	end
end

---@param cmp blink.cmp.API
---@return boolean?
function M.toggle(cmp)
	if cmp.is_signature_visible() then
		-- Blink keymaps are expression mappings. Opening or closing a window from
		-- inside that callback hits Neovim's textlock, so only update the desired
		-- state here and touch the UI after the mapping has returned.
		expanded = false
		vim.schedule(function()
			M.set_expanded(false)
		end)
		return true
	end

	if last_context and last_signature_help then
		expanded = true
		vim.schedule(function()
			M.set_expanded(true)
		end)
		return true
	end

	expanded = true
	vim.schedule(function()
		M.set_expanded(true)
		local shown = cmp.show_signature()
		if not shown then
			M.set_expanded(false)
		end
	end)
	return true
end

function M.setup()
	local signature_window = require("blink.cmp.signature.window")
	local trigger = require("blink.cmp.signature.trigger")
	-- Preserve Blink's renderer across config reloads instead of wrapping our own
	-- wrapper repeatedly.
	signature_window._user_original_open_with_signature_help = signature_window._user_original_open_with_signature_help
		or signature_window.open_with_signature_help
	local original_open = signature_window._user_original_open_with_signature_help
	signature_window._user_original_update_position = signature_window._user_original_update_position
		or signature_window.update_position
	local original_update = signature_window._user_original_update_position

	signature_window.update_position = function()
		if expanded and signature_anchor then
			return position_full_window(signature_window, original_update)
		end
		return original_update()
	end

	signature_window.open_with_signature_help = function(context, signature_help)
		update_signature_anchor(context)
		last_context = context
		last_signature_help = signature_help
		local normalized = M.normalize_signature_help(context, signature_help)
		if normalized and context then
			context.active_signature_help = normalized
			if trigger.context and trigger.context.id == context.id then
				trigger.set_active_signature_help(normalized)
			end
		end
		if expanded then
			clear_virtual()
			clear_full_indicators()
			local view = M.signature_help_view(normalized, true)
			local result = original_open(context, view)
			render_full_indicators(signature_window, view)
			signature_window.update_position()
			return result
		end

		clear_full_indicators()
		reset_full_layout()
		signature_window.context = nil
		signature_window.shown_signature = nil
		signature_window.close()
		return render_virtual(context, normalized, true)
	end

	if trigger._user_signature_reset then
		trigger.hide_emitter:off(trigger._user_signature_reset)
	end
	trigger._user_signature_reset = function()
		discovery_generation = discovery_generation + 1
		clear_virtual()
		clear_full_indicators()
		clear_anchor()
		last_context = nil
		last_signature_help = nil
		if expanded then
			M.set_expanded(false)
		end
	end
	trigger.hide_emitter:on(trigger._user_signature_reset)

	local refresh_group = api.nvim_create_augroup("user_blink_signature_virtual", { clear = true })
	api.nvim_create_autocmd("TextChangedI", {
		group = refresh_group,
		desc = "Refresh signature help while typing arguments",
		callback = function(event)
			discovery_generation = discovery_generation + 1
			last_text_change = {
				bufnr = event.buf,
				tick = api.nvim_buf_get_changedtick(event.buf),
				cursor = api.nvim_win_get_cursor(0),
			}
			if last_context and event.buf == last_context.bufnr then
				schedule_signature_refresh()
			end
		end,
	})
	api.nvim_create_autocmd("CursorMovedI", {
		group = refresh_group,
		desc = "Refresh or discover signature help after cursor movement",
		callback = function(event)
			if last_context and event.buf == last_context.bufnr then
				schedule_signature_refresh()
			end
			local cursor = api.nvim_win_get_cursor(0)
			local follows_text_change = last_text_change
				and last_text_change.bufnr == event.buf
				and last_text_change.tick == api.nvim_buf_get_changedtick(event.buf)
				and last_text_change.cursor[1] == cursor[1]
				and last_text_change.cursor[2] == cursor[2]
			if not trigger.context and not follows_text_change then
				schedule_signature_discovery(event.buf)
			end
		end,
	})
	api.nvim_create_autocmd("User", {
		group = refresh_group,
		pattern = { "BlinkCmpShow", "BlinkCmpHide" },
		desc = "Keep virtual signature clear of the completion menu",
		callback = schedule_signature_refresh,
	})
	api.nvim_create_autocmd("WinResized", {
		group = refresh_group,
		desc = "Reflow virtual signature after resizing",
		callback = schedule_signature_refresh,
	})
end

return M
