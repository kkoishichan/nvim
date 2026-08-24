-- Tree-sitter rendering for lsp_signature.nvim. The plugin's built-in virtual
-- hint accepts one highlight group for the whole string; this module consumes
-- its documented status_line() data and renders syntax-coloured virtual text.

local M = {}

local namespace = vim.api.nvim_create_namespace("user_signature_hint")
local generations = {}
local last_hints = {}
local rendered_keys = {}
local requested_float_buffers = {}
local attached_float_windows = {}
local cached_chunks_key
local cached_chunks
local card_background = "LspSignatureVirtual"
local card_left_padding = " "
local card_prefix = card_left_padding .. "󰊕 "
local card_suffix = " "

local function append_chunk(chunks, text, highlight)
	if text == "" then
		return
	end
	local previous = chunks[#chunks]
	if previous and previous[2] == highlight then
		previous[1] = previous[1] .. text
	else
		chunks[#chunks + 1] = { text, highlight }
	end
end

local function fallback_chunks(text, fallback)
	return text == "" and {} or { { text, fallback } }
end

---Split a signature fragment into Tree-sitter-highlighted virtual-text chunks.
---@param text string
---@param filetype string
---@param fallback? string
---@return table[]
function M.syntax_chunks(text, filetype, fallback)
	fallback = fallback or "Normal"
	local language = vim.treesitter.language.get_lang(filetype)
	if not language or text == "" then
		return fallback_chunks(text, fallback)
	end

	local cache_key = table.concat({ language, fallback, text }, "\0")
	if cache_key == cached_chunks_key then
		return vim.deepcopy(cached_chunks)
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
	if not ok or #spans == 0 then
		return fallback_chunks(text, fallback)
	end

	local boundary_set = { [0] = true, [#text] = true }
	for _, span in ipairs(spans) do
		boundary_set[span.start_col] = true
		boundary_set[span.end_col] = true
	end
	local boundaries = vim.tbl_keys(boundary_set)
	table.sort(boundaries)

	local chunks = {}
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
		append_chunk(chunks, text:sub(start_col + 1, end_col), winner and winner.highlight or fallback)
	end

	cached_chunks_key = cache_key
	cached_chunks = chunks
	return vim.deepcopy(chunks)
end

---Build a compact signature card while keeping each Tree-sitter foreground.
---@param hint string
---@param filetype string
---@return table[]
function M.virtual_chunks(hint, filetype)
	local chunks = {
		{ card_prefix, { "LspSignatureHint", card_background } },
	}
	for _, chunk in ipairs(M.syntax_chunks(hint, filetype, "LspSignatureHint")) do
		chunks[#chunks + 1] = { chunk[1], { chunk[2], card_background } }
	end
	chunks[#chunks + 1] = { card_suffix, { card_background } }
	return chunks
end

---Extract only the active parameter label. lsp_signature appends parameter
---documentation to `hint`; the range still points at the unadorned text in the
---full signature label.
---@param status table
---@return string
function M.parameter_text(status)
	local label = status.label
	local range = status.range
	if type(label) == "string" and type(range) == "table" then
		local start_col = tonumber(range.start)
		local end_col = tonumber(range["end"])
		if start_col and end_col and start_col >= 1 and end_col >= start_col and end_col <= #label then
			local parameter = vim.trim(label:sub(start_col, end_col))
			if parameter ~= "" then
				return parameter
			end
		end
	end
	return vim.trim(status.hint or "")
end

local function completion_visible()
	local blink = package.loaded["blink.cmp"]
	return blink and blink.is_menu_visible()
end

local function virtual_position(bufnr, hint_width)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_row = cursor[1] - 1
	local cursor_line = vim.api.nvim_get_current_line()
	local line_to_cursor = cursor_line:sub(1, cursor[2])
	local previous_line = current_row > 0 and vim.api.nvim_buf_get_lines(bufnr, current_row - 1, current_row, false)[1]
	local next_line = vim.api.nvim_buf_get_lines(bufnr, current_row + 1, current_row + 2, false)[1]
	local show_at = current_row
	local placement_line = ""

	if previous_line and vim.fn.strdisplaywidth(previous_line) < cursor[2] then
		show_at = current_row - 1
		placement_line = previous_line
	elseif next_line and vim.fn.strdisplaywidth(next_line) < cursor[2] + 2 and not completion_visible() then
		show_at = current_row + 1
		placement_line = next_line
	end

	local pad = ""
	local cursor_width = vim.fn.strdisplaywidth(line_to_cursor)
	local placement_width = vim.fn.strdisplaywidth(placement_line)
	local target_padding = cursor_width - placement_width - vim.fn.strdisplaywidth(card_left_padding)
	if show_at ~= current_row and target_padding > 0 then
		local available = vim.api.nvim_win_get_width(0) - placement_width - hint_width - 6
		pad = string.rep(" ", math.max(0, math.min(target_padding, available)))
	end
	return show_at, pad
end

local function clear_virtual(bufnr)
	rendered_keys[bufnr] = nil
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	end
end

---Render the active parameter with language-aware Tree-sitter captures.
---@param bufnr integer
---@return boolean
function M.highlight_virtual(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
		return false
	end
	local signature = package.loaded["lsp_signature"]
	if not signature then
		return false
	end

	-- Request the untruncated label because the active range indexes into it.
	local status = signature.status_line(math.huge)
	local hint = M.parameter_text(status)
	if hint ~= "" then
		last_hints[bufnr] = hint
	elseif requested_float_buffers[bufnr] then
		hint = last_hints[bufnr] or ""
	end
	if hint == "" then
		clear_virtual(bufnr)
		return false
	end

	local chunks = M.virtual_chunks(hint, vim.bo[bufnr].filetype)
	local show_at, pad = virtual_position(bufnr, vim.fn.strdisplaywidth(card_prefix .. hint .. card_suffix))
	local render_key = table.concat({ vim.bo[bufnr].filetype, hint, tostring(show_at), pad }, "\0")
	if rendered_keys[bufnr] == render_key then
		return true
	end
	if pad ~= "" then
		table.insert(chunks, 1, { pad, "Normal" })
	end

	clear_virtual(bufnr)
	vim.api.nvim_buf_set_extmark(bufnr, namespace, show_at, 0, {
		virt_text = chunks,
		virt_text_pos = "eol",
		hl_mode = "combine",
	})
	rendered_keys[bufnr] = render_key
	return true
end

local function highlight_float(bufnr)
	if not requested_float_buffers[bufnr] then
		return false
	end
	local preview = vim.b[bufnr].lsp_floating_preview
	if type(preview) ~= "number" or not vim.api.nvim_win_is_valid(preview) then
		local previous = attached_float_windows[bufnr]
		if previous and not vim.api.nvim_win_is_valid(previous) then
			M.stop_float(bufnr)
		end
		return false
	end
	if attached_float_windows[bufnr] == preview then
		return true
	end

	local language = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
	if not language then
		return false
	end
	local float_buffer = vim.api.nvim_win_get_buf(preview)
	local ok = pcall(vim.treesitter.start, float_buffer, language)
	if ok then
		attached_float_windows[bufnr] = preview
	end
	return ok
end

---Schedule repainting around lsp_signature's asynchronous LSP response.
---@param bufnr integer
function M.refresh(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	generations[bufnr] = (generations[bufnr] or 0) + 1
	local generation = generations[bufnr]
	local attempts = 0
	local function repaint()
		if generations[bufnr] ~= generation or not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		attempts = attempts + 1
		M.highlight_virtual(bufnr)
		highlight_float(bufnr)
		if attempts < 10 then
			vim.defer_fn(repaint, 120)
		end
	end
	vim.defer_fn(repaint, 40)
end

function M.request_float(bufnr)
	requested_float_buffers[bufnr] = true
	M.refresh(bufnr)
end

function M.stop_float(bufnr)
	requested_float_buffers[bufnr] = nil
	attached_float_windows[bufnr] = nil
end

function M.clear(bufnr)
	generations[bufnr] = (generations[bufnr] or 0) + 1
	last_hints[bufnr] = nil
	M.stop_float(bufnr)
	clear_virtual(bufnr)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("user_signature_treesitter", { clear = true })
	vim.api.nvim_create_autocmd({ "InsertEnter", "TextChangedI", "CursorMovedI", "CursorHoldI" }, {
		group = group,
		desc = "Render signature hints with Tree-sitter",
		callback = function(event)
			M.refresh(event.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufWipeout" }, {
		group = group,
		desc = "Clear Tree-sitter signature hints",
		callback = function(event)
			M.clear(event.buf)
		end,
	})
end

return M
