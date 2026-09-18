local M = {
	compact_height = 1,
	indicator = "󰊕",
	virtual_indicator = "◀",
}

local api = vim.api
local adapter = require("user.core.signature.adapter")
local call = require("user.core.signature.call")
local compact = require("user.core.signature.compact")
local layout = require("user.core.signature.layout")
local parameters = require("user.core.signature.parameters")
M.signature_help_view = parameters.signature_help_view
M.normalize_signature_help = parameters.normalize_signature_help
M.find_call_anchor = call.find_call_anchor
M.display_cursor = call.display_cursor
M.virtual_position = layout.virtual_position
local active_parameter_range = parameters.active_parameter_range
local virtual_namespace = api.nvim_create_namespace("user_blink_signature")
local anchor_namespace = api.nvim_create_namespace("user_blink_signature_anchor")
local full_indicator_namespace = api.nvim_create_namespace("user_blink_signature_full_indicator")
local full_parameter_namespace = api.nvim_create_namespace("user_blink_signature_full_parameter")
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
local discovery_timer
local lifecycle_generation = 0
local active = false
local last_text_change
local redraw_current_signature

local function schedule(callback, allow_inactive)
	local generation = lifecycle_generation
	vim.schedule(function()
		if generation == lifecycle_generation and (active or allow_inactive) then
			callback()
		end
	end)
end

local function cancel_discovery()
	discovery_generation = discovery_generation + 1
	if discovery_timer and not discovery_timer:is_closing() then
		discovery_timer:stop()
		discovery_timer:close()
	end
	discovery_timer = nil
end

local function full_height()
	return math.max(1, vim.api.nvim_win_get_height(0))
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
---@param max_width? integer Available display cells, including card padding.
---@return table[]
function M.virtual_chunks(label, filetype, active_range, max_width)
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
	local body = {}
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
		append_chunk(body, label:sub(start_col + 1, end_col), highlights)
	end
	local chrome_width = vim.fn.strdisplaywidth(M.virtual_indicator) + 3
	if max_width then
		if max_width <= chrome_width then
			return compact.fit_chunks(body, max_width)
		end
		body = compact.fit_chunks(body, max_width - chrome_width)
	end
	local chunks = {
		{ " ", "BlinkCmpSignatureVirtual" },
		{
			M.virtual_indicator .. " ",
			{ "BlinkCmpSignatureVirtualIndicator", "BlinkCmpSignatureVirtual" },
		},
	}
	vim.list_extend(chunks, body)
	append_chunk(chunks, " ", "BlinkCmpSignatureVirtual")
	return chunks
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
		api.nvim_buf_clear_namespace(full_indicator_buffer, full_parameter_namespace, 0, -1)
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
	local docs = adapter.current().docs
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
	local range = active_parameter_range(signature_help)
	local selected = signature_help.signatures[1]
	if not range or not selected then
		return
	end
	-- Blink drops empty lines and CR/LF separators from labels. Map the raw
	-- byte range into those displayed lines, including multiline parameters.
	row = 0
	for offset, line in selected.label:gmatch("()([^\r\n]+)") do
		local start_col = math.max(0, range[1] - offset + 1)
		local end_col = math.min(#line, range[2] - offset + 1)
		if end_col > start_col then
			api.nvim_buf_set_extmark(bufnr, full_parameter_namespace, row, start_col, {
				end_col = end_col,
				hl_group = "BlinkCmpSignatureHelpActiveParameter",
				priority = vim.hl.priorities.user,
			})
		end
		row = row + 1
	end
end

local function full_render_view(view)
	if not view or not view.signatures or not view.signatures[1] then
		return view
	end
	-- Native signature rendering currently interprets LSP's UTF-16 label
	-- offsets as bytes. Suppress only its active mark and draw our shared byte
	-- range above; this view never becomes the next LSP request's context.
	local rendered = vim.tbl_extend("force", {}, view)
	rendered.signatures = vim.list_extend({}, view.signatures)
	rendered.signatures[1] = vim.tbl_extend("force", {}, view.signatures[1], { activeParameter = vim.NIL })
	return rendered
end

local function clear_anchor()
	if signature_anchor and api.nvim_buf_is_valid(signature_anchor.bufnr) then
		api.nvim_buf_clear_namespace(signature_anchor.bufnr, anchor_namespace, 0, -1)
	end
	signature_anchor = nil
end

local function cleanup()
	active = false
	lifecycle_generation = lifecycle_generation + 1
	cancel_discovery()
	refresh_scheduled = false
	clear_virtual()
	clear_full_indicators()
	clear_anchor()
	last_context = nil
	last_signature_help = nil
	last_text_change = nil
	cached_syntax_key = nil
	cached_syntax_spans = nil
	expanded = false
	local current = adapter.current()
	if current and type(current.window.close) == "function" then
		pcall(current.window.close)
	end
	pcall(api.nvim_del_augroup_by_name, "user_blink_signature_virtual")
end

function M.teardown()
	adapter.teardown()
	cleanup()
end

local function source_window(bufnr)
	local current = api.nvim_get_current_win()
	if api.nvim_win_get_buf(current) == bufnr then
		return current
	end
	local winid = vim.fn.bufwinid(bufnr)
	return winid ~= -1 and winid or nil
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
	local menu = adapter.menu()
	if menu and menu.win:is_open() then
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
			local placement = win:get_vertical_direction_and_height({ direction }, win.config.max_height)
			if placement then
				signature_anchor.full_direction = opposite_direction
				signature_anchor.full_height = placement.height
				win:set_height(placement.height)
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
	local range = active_parameter_range(view, filetype)
	label, range = compact.flatten(label, range)
	local preferred_side = signature_anchor and signature_anchor.virtual_side or nil
	local show_row, padding, side, width = M.virtual_position(bufnr, anchor, preferred_side, live_row)
	if signature_anchor then
		signature_anchor.virtual_side = side
	end
	local chunks = M.virtual_chunks(label, filetype, range, width)
	if #chunks == 0 then
		return false
	end
	if side ~= 0 and padding ~= "" then
		table.insert(chunks, 1, { padding, "Normal" })
	end
	local placement_line = api.nvim_buf_get_lines(bufnr, show_row, show_row + 1, false)[1] or ""
	api.nvim_buf_set_extmark(bufnr, virtual_namespace, show_row, #placement_line, {
		virt_text = chunks,
		-- Paint over unused cells at EOL without widening the source line.
		-- Inline text moves the insertion cursor's display column past the
		-- whole card, triggering horizontal scroll/reflow feedback while typing.
		virt_text_pos = "overlay",
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
	schedule(function()
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
	cancel_discovery()
	local generation = discovery_generation
	discovery_timer = vim.defer_fn(function()
		if not active or generation ~= discovery_generation or api.nvim_get_current_buf() ~= bufnr then
			return
		end
		discovery_timer = nil
		local mode = api.nvim_get_mode().mode:sub(1, 1)
		if mode ~= "i" and mode ~= "s" then
			return
		end
		if #vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/signatureHelp" }) == 0 then
			return
		end

		local trigger = adapter.current().trigger
		if not trigger.context then
			trigger.show({ force = true })
		end
	end, 60)
end

redraw_current_signature = function()
	local signature_window = adapter.current().window
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
	local signature_config = adapter.current().config
	local signature_window = adapter.current().window

	-- Blink copies max_height into its generic window object during setup, while
	-- its positioning code keeps reading the signature config. Keep both in sync.
	signature_config.max_height = height
	signature_window.win.config.max_height = height
	return signature_window
end

---@param value boolean
function M.set_expanded(value)
	if not active or not adapter.current() then
		return false
	end
	expanded = value
	local signature_window = apply_height()
	if not redraw_current_signature() and signature_window.win:is_open() then
		schedule(signature_window.update_position)
	end
end

---@param cmp blink.cmp.API
---@return boolean?
function M.toggle(cmp)
	if not active or not adapter.current() then
		schedule(function()
			adapter.fallback(cmp)
		end, true)
		return true
	end
	cmp = cmp or {}
	if type(cmp.is_signature_visible) == "function" and cmp.is_signature_visible() then
		-- Blink keymaps are expression mappings. Opening or closing a window from
		-- inside that callback hits Neovim's textlock, so only update the desired
		-- state here and touch the UI after the mapping has returned.
		expanded = false
		schedule(function()
			M.set_expanded(false)
		end)
		return true
	end

	if last_context and last_signature_help then
		expanded = true
		schedule(function()
			M.set_expanded(true)
		end)
		return true
	end

	expanded = true
	schedule(function()
		M.set_expanded(true)
		local shown = cmp.show_signature()
		if not shown then
			M.set_expanded(false)
		end
	end)
	return true
end

function M.setup()
	local capabilities, reason = adapter.probe()
	if not capabilities then
		M.teardown()
		return false, reason
	end
	local signature_window = capabilities.window
	local trigger = capabilities.trigger
	local function update(original_update)
		if expanded and signature_anchor then
			return position_full_window(signature_window, original_update)
		end
		return original_update()
	end

	local function open(original_open, context, signature_help)
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
			local result = original_open(context, full_render_view(view))
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

	local function hide()
		cancel_discovery()
		clear_virtual()
		clear_full_indicators()
		clear_anchor()
		last_context = nil
		last_signature_help = nil
		if expanded then
			M.set_expanded(false)
		end
	end
	adapter.install(capabilities, { open = open, update = update, hide = hide, teardown = cleanup })
	active = true

	local refresh_group = api.nvim_create_augroup("user_blink_signature_virtual", { clear = true })
	api.nvim_create_autocmd("TextChangedI", {
		group = refresh_group,
		desc = "Refresh signature help while typing arguments",
		callback = function(event)
			cancel_discovery()
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
	api.nvim_create_autocmd({ "WinResized", "WinScrolled" }, {
		group = refresh_group,
		desc = "Reflow virtual signature in the visible window",
		callback = function()
			if not expanded and last_context and api.nvim_get_current_buf() == last_context.bufnr then
				schedule_signature_refresh()
			end
		end,
	})
	return true
end

return M
