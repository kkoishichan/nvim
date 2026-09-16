local M = {}
local api = vim.api

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

local function line_comment(character, following, filetype)
	return (character == "/" and following == "/" and filetype ~= "python" and filetype ~= "lua")
		or (character == "-" and following == "-" and (not filetype or filetype == "lua"))
		or (character == "#" and (not filetype or filetype == "python"))
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
	local filetype = vim.bo[bufnr].filetype
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
			elseif line_comment(character, following, filetype) then
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

local function split_arguments(text, filetype)
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
		elseif line_comment(character, following, filetype) then
			state = "line_comment"
			if character ~= "#" then
				column = column + 1
			end
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

local function node_arguments(bufnr, node, argument_start, cursor)
	local _, _, end_row, end_col = node:range()
	local last = node:child(node:child_count() - 1)
	local argument_end = last and last:type() == ")" and node_start(last) or { end_row + 1, end_col }
	local arguments, active = {}, 0
	local start = argument_start
	-- Direct comma tokens delimit arguments; commas inside strings, regexes,
	-- templates and nested expressions belong to child nodes instead.
	for child in node:iter_children() do
		if child:type() == "," then
			local separator = node_start(child)
			arguments[#arguments + 1] = text_between(bufnr, start, separator)
			local _, _, row, col = child:range()
			start = { row + 1, col }
			if position_before(separator, cursor) then
				active = active + 1
			end
		end
	end
	arguments[#arguments + 1] = text_between(bufnr, start, argument_end)
	return arguments, active
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

	local arguments, active
	if site.argument_node then
		arguments, active = node_arguments(bufnr, site.argument_node, argument_start, cursor)
	else
		arguments = split_arguments(text_between(bufnr, argument_start, cursor), vim.bo[bufnr].filetype)
		active = #arguments - 1
	end
	local argument_count = #arguments
	if argument_count == 1 and arguments[1]:match("^%s*$") then
		argument_count = 0
	end

	return {
		active_parameter = active,
		argument_count = argument_count,
		arguments = arguments,
		anchor = site.anchor,
		open = site.open,
	}
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

M.split_arguments = split_arguments

return M
