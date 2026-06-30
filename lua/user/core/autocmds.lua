local augroup = function(name)
	return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end

require("user.core.pdf")

vim.api.nvim_create_autocmd("TextYankPost", {
	group = augroup("highlight_yank"),
	callback = function()
		vim.highlight.on_yank({ timeout = 180 })
	end,
})

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
	group = augroup("disable_secrets_persistence"),
	pattern = {
		".env",
		".env.*",
		"*.env",
		"*.pem",
		"*.key",
		"*.crt",
		"*.gpg",
		"*.asc",
		"*/.ssh/*",
		"*/.aws/credentials",
		"*/.netrc",
		"*secret*",
		"*password*",
		"*credentials*",
	},
	callback = function()
		vim.opt_local.undofile = false
		vim.opt_local.swapfile = false
	end,
})

vim.api.nvim_create_autocmd("VimResized", {
	group = augroup("resize_splits"),
	command = "tabdo wincmd =",
})

-- Native spell only for prose. Code spelling is left to typos-lsp, which has far
-- fewer false positives on identifiers than the dictionary check.
vim.api.nvim_create_autocmd("FileType", {
	group = augroup("prose_spell"),
	pattern = { "markdown", "text", "tex", "plaintex", "typst", "gitcommit", "rst", "asciidoc" },
	callback = function()
		vim.opt_local.spell = true
	end,
})

-- External file changes (e.g. an AI agent rewriting files during "vibe coding")
-- are picked up promptly and reconciled safely. Design:
--   * Detection is both event-driven (focus / buffer / terminal switches give an
--     instant refresh) and timer-driven while focused (covers the "window
--     focused but cursor idle" gap that CursorHold alone misses). :checktime
--     scans every loaded buffer, so a multi-file rewrite all lands at once.
--   * Reconciliation is decided in one place (FileChangedShell): clean buffers
--     reload silently; buffers with unsaved edits are never clobbered (warn
--     instead of the blocking W12 prompt); deleted files keep their buffer.
--   * Reload notices are coalesced/de-duplicated so a burst of edits is one line.
local external_changes = augroup("external_changes")

local function check_external_changes()
	-- :checktime is illegal in the command-line window; harmless everywhere else.
	if vim.fn.getcmdwintype() ~= "" then
		return
	end
	pcall(vim.cmd.checktime)
end

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "TermLeave", "TermClose" }, {
	group = external_changes,
	callback = function()
		vim.schedule(check_external_changes)
	end,
})

-- Poll fallback, gated on focus to avoid waking an idle/background editor.
local poll_focused = true
vim.api.nvim_create_autocmd("FocusLost", {
	group = external_changes,
	callback = function()
		poll_focused = false
	end,
})
vim.api.nvim_create_autocmd("FocusGained", {
	group = external_changes,
	callback = function()
		poll_focused = true
	end,
})

local poll_timer = vim.uv.new_timer()
if poll_timer then
	poll_timer:start(
		2000,
		2000,
		vim.schedule_wrap(function()
			if poll_focused then
				check_external_changes()
			end
		end)
	)
end

vim.api.nvim_create_autocmd("FileChangedShell", {
	group = external_changes,
	callback = function(event)
		local reason = vim.v.fcs_reason
		local name = vim.fn.fnamemodify(event.match, ":~:.")

		if reason == "deleted" then
			vim.v.fcs_choice = "" -- keep the buffer; an agent may recreate the file
			vim.notify("Gone on disk (buffer kept): " .. name, vim.log.levels.WARN, {
				title = "External change",
			})
			return
		end

		if vim.bo[event.buf].modified then
			vim.v.fcs_choice = "" -- never discard unsaved edits automatically
			vim.notify(
				"Changed on disk, but you have unsaved edits: " .. name .. "  (:e! discards yours, :w keeps them)",
				vim.log.levels.WARN,
				{ title = "External change" }
			)
			return
		end

		vim.v.fcs_choice = "reload"
	end,
})

-- Coalesce reload notices: a multi-file rewrite becomes a single summary.
local reloaded = {}
local reloaded_count = 0
local notice_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = external_changes,
	callback = function(event)
		local name = vim.fn.fnamemodify(event.match, ":~:.")
		if not reloaded[name] then
			reloaded[name] = true
			reloaded_count = reloaded_count + 1
		end

		if not notice_timer then
			return
		end
		notice_timer:stop()
		notice_timer:start(
			250,
			0,
			vim.schedule_wrap(function()
				local first = next(reloaded)
				local count = reloaded_count
				reloaded = {}
				reloaded_count = 0
				if not first then
					return
				end
				local message = count == 1 and ("Reloaded: " .. first) or ("Reloaded %d files"):format(count)
				vim.notify(message, vim.log.levels.INFO, { title = "External change" })
			end)
		)
	end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
	group = augroup("create_missing_dirs"),
	callback = function(event)
		if vim.bo[event.buf].buftype ~= "" then
			return
		end

		local file = vim.uv.fs_realpath(event.match) or event.match
		local dir = vim.fn.fnamemodify(file, ":p:h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = augroup("close_with_q"),
	pattern = {
		"checkhealth",
		"help",
		"lspinfo",
		"man",
		"qf",
		"query",
		"startuptime",
	},
	callback = function(event)
		vim.bo[event.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true, desc = "Close window" })
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = augroup("local_indents"),
	pattern = { "go", "make", "gitconfig", "tsv" },
	callback = function()
		vim.opt_local.expandtab = false
	end,
})

-- Quick inline PDF preview via image.nvim. This is a lightweight glance tool,
-- not a reader: image.nvim's inline rendering flickers ("black flash") on page
-- and zoom changes because it clears and redraws across redraw ticks. That is
-- accepted here. For real reading use the external viewer (o / <leader>mo /
-- :PdfOpen -> zathura). No prefetch: warming the cache does not shorten the
-- flash, so pages are rendered on demand only.
local pdf_base_dpi = 144
local pdf_min_zoom = 50
local pdf_max_zoom = 300
local pdf_zoom_step = 25
local pdf_min_scroll_lines = 500
local pdf_min_scroll_columns = 500

local active_pdf_preview_images = {}
local pending_pdf_conversions = {}

local function refresh_pdf_statusline()
	pcall(vim.cmd.redrawstatus)

	local lualine = package.loaded["lualine"]
	if lualine then
		pcall(lualine.refresh, { force = true, place = { "statusline" } })
	end
end

local pdf_lualine_loading = false
local pdf_image_loading = false

local function load_pdf_statusline()
	if package.loaded["lualine"] or pdf_lualine_loading then
		return
	end

	pdf_lualine_loading = true
	vim.schedule(function()
		pcall(function()
			require("lazy").load({ plugins = { "lualine.nvim" } })
		end)
		pdf_lualine_loading = false
		refresh_pdf_statusline()
	end)
end

local function load_pdf_image_plugin()
	if package.loaded["image"] or pdf_image_loading then
		return
	end

	pdf_image_loading = true
	vim.schedule(function()
		pcall(function()
			require("lazy").load({ plugins = { "image.nvim" } })
		end)
		pdf_image_loading = false
	end)
end

local function clamp_pdf_page(bufnr, page)
	page = math.max(1, math.floor(tonumber(page) or 1))

	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	if pages and pages > 0 then
		page = math.min(page, pages)
	end

	return page
end

local function clamp_pdf_zoom(zoom)
	zoom = math.floor(tonumber(zoom) or 100)
	return math.min(math.max(zoom, pdf_min_zoom), pdf_max_zoom)
end

local function pdf_cache_file(file, page, zoom)
	local stat = vim.uv.fs_stat(file)
	local fingerprint = table.concat({
		vim.fn.fnamemodify(file, ":p"),
		stat and stat.size or 0,
		stat and stat.mtime.sec or 0,
		stat and stat.mtime.nsec or 0,
		page,
		zoom,
	}, ":")
	local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "user", "pdf-preview")
	vim.fn.mkdir(cache_dir, "p")

	return vim.fs.joinpath(cache_dir, vim.fn.sha256(fingerprint) .. ".png")
end

local function convert_pdf_preview(file, page, zoom, png, callback, opts)
	opts = opts or {}
	callback = callback or function() end
	local notify_on_error = not opts.silent

	if vim.uv.fs_stat(png) then
		callback(png)
		return
	end

	if pending_pdf_conversions[png] then
		table.insert(pending_pdf_conversions[png].callbacks, callback)
		pending_pdf_conversions[png].notify_on_error = pending_pdf_conversions[png].notify_on_error or notify_on_error
		return
	end

	if vim.fn.executable("pdftoppm") == 0 then
		vim.notify("Missing pdftoppm for PDF preview", vim.log.levels.ERROR, { title = "PDF preview" })
		return
	end

	pending_pdf_conversions[png] = { callbacks = { callback }, notify_on_error = notify_on_error }
	local dpi = math.floor(pdf_base_dpi * zoom / 100 + 0.5)
	local output_base = png:gsub("%.png$", "")
	vim.system({
		"pdftoppm",
		"-f",
		tostring(page),
		"-l",
		tostring(page),
		"-singlefile",
		"-png",
		"-r",
		tostring(dpi),
		file,
		output_base,
	}, { text = true }, function(result)
		vim.schedule(function()
			local pending = pending_pdf_conversions[png] or { callbacks = {}, notify_on_error = notify_on_error }
			pending_pdf_conversions[png] = nil

			if result.code ~= 0 or not vim.uv.fs_stat(png) then
				if pending.notify_on_error then
					local stderr = vim.trim(result.stderr or "")
					local message = stderr ~= "" and stderr or ("Failed to render PDF page " .. page)
					vim.notify(message, vim.log.levels.ERROR, { title = "PDF preview" })
				end
				return
			end

			for _, queued_callback in ipairs(pending.callbacks) do
				queued_callback(png)
			end
		end)
	end)
end

local function clear_pdf_image_set(images, ids)
	if type(images) == "table" then
		for _, img in pairs(images) do
			pcall(function()
				img:clear()
			end)
		end
	end

	if type(ids) == "table" then
		local ok, image = pcall(require, "image")
		if ok then
			for _, id in pairs(ids) do
				pcall(image.clear, id)
			end
		end
	end
end

local function clear_pdf_preview_images(bufnr)
	clear_pdf_image_set(active_pdf_preview_images[bufnr], vim.b[bufnr].pdf_preview_image_ids)
	active_pdf_preview_images[bufnr] = nil
	vim.b[bufnr].pdf_preview_image_ids = nil
end

local function pdf_preview_scroll_size()
	local lines = math.max(pdf_min_scroll_lines, (vim.o.lines or 40) * 8)
	local columns = math.max(pdf_min_scroll_columns, (vim.o.columns or 80) * 4)
	return lines, columns
end

local function ensure_pdf_preview_scroll_space(bufnr)
	local lines, columns = pdf_preview_scroll_size()
	if
		vim.b[bufnr].pdf_preview_scroll_lines == lines
		and vim.b[bufnr].pdf_preview_scroll_columns == columns
		and vim.api.nvim_buf_line_count(bufnr) == lines
	then
		return lines, columns
	end

	local line = string.rep(" ", columns)
	local content = {}
	for i = 1, lines do
		content[i] = line
	end

	local modifiable = vim.bo[bufnr].modifiable
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
	vim.bo[bufnr].modifiable = modifiable
	vim.bo[bufnr].modified = false
	vim.b[bufnr].pdf_preview_scroll_lines = lines
	vim.b[bufnr].pdf_preview_scroll_columns = columns

	return lines, columns
end

local function apply_pdf_preview_window_options(bufnr)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		for option, value in pairs({
			colorcolumn = "",
			cursorline = false,
			foldcolumn = "0",
			list = false,
			number = false,
			relativenumber = false,
			signcolumn = "no",
			wrap = false,
		}) do
			pcall(vim.api.nvim_set_option_value, option, value, { win = win })
		end
	end
end

local function reset_pdf_preview_view(bufnr)
	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
		pcall(vim.api.nvim_win_call, win, function()
			vim.cmd("normal! zt")
		end)
	end
end

-- Warm the cache for the neighbouring pages so flipping has no pdftoppm wait.
-- Only fills the PNG cache (no draw), deduped via convert_pdf_preview.
local function prefetch_pdf_adjacent(bufnr, file, page, zoom)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	for _, target in ipairs({ page + 1, page - 1 }) do
		if target >= 1 and (not pages or target <= pages) then
			local png = pdf_cache_file(file, target, zoom)
			if not vim.uv.fs_stat(png) and not pending_pdf_conversions[png] then
				convert_pdf_preview(file, target, zoom, png, nil, { silent = true })
			end
		end
	end
end

local function render_pdf_preview(bufnr, opts)
	opts = opts or {}
	if not vim.api.nvim_buf_is_valid(bufnr) or #vim.api.nvim_list_uis() == 0 then
		return
	end

	local file = vim.b[bufnr].pdf_preview_file
	if type(file) ~= "string" or file == "" then
		return
	end

	local stat = vim.uv.fs_stat(file)
	if not stat or stat.type ~= "file" then
		vim.notify("PDF not found: " .. file, vim.log.levels.ERROR, { title = "PDF preview" })
		return
	end

	local page = clamp_pdf_page(bufnr, vim.b[bufnr].pdf_preview_page)
	local zoom = clamp_pdf_zoom(vim.b[bufnr].pdf_preview_zoom)
	vim.b[bufnr].pdf_preview_page = page
	vim.b[bufnr].pdf_preview_zoom = zoom
	local token = (tonumber(vim.b[bufnr].pdf_preview_render_token) or 0) + 1
	vim.b[bufnr].pdf_preview_render_token = token
	refresh_pdf_statusline()

	apply_pdf_preview_window_options(bufnr)
	local png = pdf_cache_file(file, page, zoom)
	if opts.force and not pending_pdf_conversions[png] then
		pcall(vim.fn.delete, png)
	end

	local overlap = ensure_pdf_preview_scroll_space(bufnr)
	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	convert_pdf_preview(file, page, zoom, png, function(png_file)
		if
			not vim.api.nvim_buf_is_valid(bufnr)
			or vim.b[bufnr].pdf_preview_file ~= file
			or vim.b[bufnr].pdf_preview_page ~= page
			or vim.b[bufnr].pdf_preview_zoom ~= zoom
			or vim.b[bufnr].pdf_preview_render_token ~= token
		then
			return
		end

		local ok, image = pcall(require, "image")
		if not ok then
			vim.notify("image.nvim is not available for PDF preview", vim.log.levels.ERROR, { title = "PDF preview" })
			return
		end

		if opts.reset_view then
			reset_pdf_preview_view(bufnr)
		end

		-- Draw the new image, then clear the previous one, so the swap is as
		-- seamless as image.nvim allows.
		local previous_images = active_pdf_preview_images[bufnr]
		local previous_ids = vim.b[bufnr].pdf_preview_image_ids
		local ids = {}
		local images = {}
		for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
			local id = ("pdf-preview-%d-%d-%d"):format(bufnr, win, token)
			local ok_image, img = pcall(image.from_file, png_file, {
				buffer = bufnr,
				id = id,
				inline = true,
				max_height_window_percentage = math.floor(95 * zoom / 100),
				max_width_window_percentage = math.floor(100 * zoom / 100),
				overlap = overlap,
				render_offset_top = -1,
				window = win,
				with_virtual_padding = false,
				x = 0,
				y = 0,
			})
			if ok_image and img then
				local ok_render, render_error = pcall(function()
					img:render()
				end)
				if ok_render then
					ids[tostring(win)] = img.id
					images[tostring(win)] = img
				else
					vim.notify(tostring(render_error), vim.log.levels.ERROR, { title = "PDF preview" })
				end
			elseif not ok_image then
				vim.notify(tostring(img), vim.log.levels.ERROR, { title = "PDF preview" })
			end
		end
		vim.b[bufnr].pdf_preview_image_ids = ids
		active_pdf_preview_images[bufnr] = images
		clear_pdf_image_set(previous_images, previous_ids)
		refresh_pdf_statusline()
		vim.defer_fn(function()
			if
				vim.api.nvim_buf_is_valid(bufnr)
				and vim.b[bufnr].pdf_preview_file == file
				and vim.b[bufnr].pdf_preview_zoom == zoom
			then
				prefetch_pdf_adjacent(bufnr, file, page, zoom)
			end
		end, 100)
	end, { silent = not (pages and pages > 0) })
end

local function request_pdf_page_count(bufnr, file)
	vim.b[bufnr].pdf_preview_pages = nil
	refresh_pdf_statusline()

	if vim.fn.executable("pdfinfo") == 0 then
		return
	end

	local token = (tonumber(vim.b[bufnr].pdf_preview_page_count_token) or 0) + 1
	vim.b[bufnr].pdf_preview_page_count_token = token
	vim.system({ "pdfinfo", file }, { text = true }, function(result)
		vim.schedule(function()
			if
				not vim.api.nvim_buf_is_valid(bufnr)
				or vim.b[bufnr].pdf_preview_file ~= file
				or vim.b[bufnr].pdf_preview_page_count_token ~= token
			then
				return
			end

			if result.code ~= 0 then
				refresh_pdf_statusline()
				return
			end

			local pages = tonumber(
				(result.stdout or ""):match("\nPages:%s*(%d+)") or (result.stdout or ""):match("^Pages:%s*(%d+)")
			)
			if not pages or pages < 1 then
				refresh_pdf_statusline()
				return
			end

			vim.b[bufnr].pdf_preview_pages = pages
			local clamped_page = clamp_pdf_page(bufnr, vim.b[bufnr].pdf_preview_page)
			if clamped_page ~= vim.b[bufnr].pdf_preview_page then
				vim.b[bufnr].pdf_preview_page = clamped_page
				render_pdf_preview(bufnr, { reset_view = true })
			else
				refresh_pdf_statusline()
			end
		end)
	end)
end

local function set_pdf_page(bufnr, page)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	page = clamp_pdf_page(bufnr, page)
	if page == vim.b[bufnr].pdf_preview_page then
		return
	end

	vim.b[bufnr].pdf_preview_page = page
	render_pdf_preview(bufnr, { reset_view = true })
end

local function prompt_pdf_page(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local current = tonumber(vim.b[bufnr].pdf_preview_page) or 1
	local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
	local prompt = pages and pages > 0 and ("Page 1-" .. pages .. ": ") or "Page: "
	vim.ui.input({ prompt = prompt, default = tostring(current) }, function(input)
		if not input then
			return
		end

		local page = tonumber(vim.trim(input))
		if not page then
			return
		end

		set_pdf_page(bufnr, page)
	end)
end

local function set_pdf_zoom(bufnr, zoom)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	zoom = clamp_pdf_zoom(zoom)
	if zoom == vim.b[bufnr].pdf_preview_zoom then
		return
	end

	vim.b[bufnr].pdf_preview_zoom = zoom
	render_pdf_preview(bufnr)
end

local function setup_pdf_preview_keymaps(bufnr, file)
	local function map(lhs, callback, desc)
		vim.keymap.set("n", lhs, callback, { buffer = bufnr, silent = true, desc = desc })
	end

	local function next_page()
		set_pdf_page(bufnr, (tonumber(vim.b[bufnr].pdf_preview_page) or 1) + 1)
	end

	local function previous_page()
		set_pdf_page(bufnr, (tonumber(vim.b[bufnr].pdf_preview_page) or 1) - 1)
	end

	local function rerender_current_image()
		local images = active_pdf_preview_images[bufnr]
		local img = type(images) == "table" and images[tostring(vim.api.nvim_get_current_win())]
		if img then
			pcall(function()
				img:render()
			end)
		end
	end

	local function pan(delta_line, delta_column)
		local win = vim.api.nvim_get_current_win()
		if vim.api.nvim_win_get_buf(win) ~= bufnr then
			return
		end

		ensure_pdf_preview_scroll_space(bufnr)
		local line_count = vim.api.nvim_buf_line_count(bufnr)
		local win_height = vim.api.nvim_win_get_height(win)
		local win_width = vim.api.nvim_win_get_width(win)
		local columns = tonumber(vim.b[bufnr].pdf_preview_scroll_columns) or pdf_min_scroll_columns
		local max_topline = math.max(1, line_count - win_height + 1)
		local max_leftcol = math.max(0, columns - win_width)
		local view = vim.fn.winsaveview()
		local old_topline = view.topline
		local old_leftcol = view.leftcol
		view.topline = math.min(max_topline, math.max(1, view.topline + delta_line))
		view.leftcol = math.min(max_leftcol, math.max(0, view.leftcol + delta_column))

		if view.topline == old_topline and view.leftcol == old_leftcol then
			return
		end

		local cursor_line = math.min(line_count, math.max(1, view.topline + 1))
		local cursor_column = math.min(math.max(0, columns - 1), view.leftcol)
		pcall(vim.api.nvim_win_set_cursor, win, { cursor_line, cursor_column })
		vim.fn.winrestview(view)
		rerender_current_image()
	end

	local pan_lines = 5
	local pan_columns = 8

	for _, lhs in ipairs({ "j", "<Down>" }) do
		map(lhs, function()
			pan(pan_lines, 0)
		end, "Pan PDF down")
	end
	for _, lhs in ipairs({ "k", "<Up>" }) do
		map(lhs, function()
			pan(-pan_lines, 0)
		end, "Pan PDF up")
	end
	for _, lhs in ipairs({ "h", "<Left>" }) do
		map(lhs, function()
			pan(0, -pan_columns)
		end, "Pan PDF left")
	end
	for _, lhs in ipairs({ "l", "<Right>" }) do
		map(lhs, function()
			pan(0, pan_columns)
		end, "Pan PDF right")
	end
	for _, lhs in ipairs({ "<PageDown>", "<Space>" }) do
		map(lhs, function()
			pan(math.max(1, math.floor(vim.api.nvim_win_get_height(0) / 2)), 0)
		end, "Scroll PDF down")
	end
	for _, lhs in ipairs({ "<PageUp>" }) do
		map(lhs, function()
			pan(-math.max(1, math.floor(vim.api.nvim_win_get_height(0) / 2)), 0)
		end, "Scroll PDF up")
	end

	for _, lhs in ipairs({ "]p", "J" }) do
		map(lhs, next_page, "Next PDF page")
	end
	for _, lhs in ipairs({ "[p", "K" }) do
		map(lhs, previous_page, "Previous PDF page")
	end

	map("gg", function()
		set_pdf_page(bufnr, 1)
	end, "First PDF page")
	map("G", function()
		local pages = tonumber(vim.b[bufnr].pdf_preview_pages)
		if pages and pages > 0 then
			set_pdf_page(bufnr, pages)
		else
			vim.notify("PDF page count not ready yet", vim.log.levels.INFO, { title = "PDF preview" })
		end
	end, "Last PDF page")
	map("g", function()
		prompt_pdf_page(bufnr)
	end, "Go to PDF page")
	map("+", function()
		set_pdf_zoom(bufnr, (tonumber(vim.b[bufnr].pdf_preview_zoom) or 100) + pdf_zoom_step)
	end, "Zoom in PDF")
	map("=", function()
		set_pdf_zoom(bufnr, (tonumber(vim.b[bufnr].pdf_preview_zoom) or 100) + pdf_zoom_step)
	end, "Zoom in PDF")
	map("-", function()
		set_pdf_zoom(bufnr, (tonumber(vim.b[bufnr].pdf_preview_zoom) or 100) - pdf_zoom_step)
	end, "Zoom out PDF")
	map("0", function()
		set_pdf_zoom(bufnr, 100)
	end, "Reset PDF zoom")
	map("q", "<cmd>bd<cr>", "Close PDF preview")
	map("o", function()
		vim.api.nvim_cmd({ cmd = "PdfOpen", args = { file } }, {})
	end, "Open PDF externally")
	map("r", function()
		render_pdf_preview(bufnr, { force = true })
	end, "Refresh PDF preview")
end

local pdf_file_watchers = {}
local pdf_watch_pending = {}

local function stop_pdf_watcher(bufnr)
	local handle = pdf_file_watchers[bufnr]
	if handle then
		pcall(function()
			handle:stop()
		end)
		pcall(function()
			handle:close()
		end)
		pdf_file_watchers[bufnr] = nil
	end
	pdf_watch_pending[bufnr] = nil
end

local function watch_pdf_file(bufnr, file)
	stop_pdf_watcher(bufnr)

	local handle = vim.uv.new_fs_event()
	if not handle then
		return
	end
	pdf_file_watchers[bufnr] = handle

	local function on_change()
		if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].pdf_preview_file ~= file then
			stop_pdf_watcher(bufnr)
			return
		end

		request_pdf_page_count(bufnr, file)
		render_pdf_preview(bufnr, { force = true })
		watch_pdf_file(bufnr, file)
	end

	local ok = pcall(function()
		handle:start(
			file,
			{},
			vim.schedule_wrap(function(err)
				if err then
					stop_pdf_watcher(bufnr)
					return
				end

				if pdf_watch_pending[bufnr] then
					return
				end
				pdf_watch_pending[bufnr] = true
				vim.defer_fn(function()
					pdf_watch_pending[bufnr] = nil
					on_change()
				end, 200)
			end)
		)
	end)

	if not ok then
		stop_pdf_watcher(bufnr)
	end
end

vim.api.nvim_create_autocmd("BufReadCmd", {
	group = augroup("pdf_preview"),
	pattern = { "*.pdf", "*.PDF" },
	callback = function(event)
		local bufnr = event.buf
		local file = vim.fn.fnamemodify(event.match, ":p")

		vim.b[bufnr].pdf_preview_file = file
		vim.b[bufnr].pdf_preview_page = 1
		vim.b[bufnr].pdf_preview_pages = nil
		vim.b[bufnr].pdf_preview_zoom = 100
		vim.b[bufnr].pdf_preview_render_token = 0
		vim.bo[bufnr].bufhidden = "hide"
		vim.bo[bufnr].buflisted = true
		vim.bo[bufnr].buftype = "nofile"
		vim.bo[bufnr].filetype = "pdf"
		vim.bo[bufnr].modified = false
		vim.bo[bufnr].modifiable = true
		vim.bo[bufnr].readonly = true
		vim.bo[bufnr].swapfile = false
		ensure_pdf_preview_scroll_space(bufnr)
		vim.bo[bufnr].modifiable = false
		vim.bo[bufnr].modified = false

		load_pdf_statusline()
		load_pdf_image_plugin()
		apply_pdf_preview_window_options(bufnr)
		setup_pdf_preview_keymaps(bufnr, file)
		request_pdf_page_count(bufnr, file)
		watch_pdf_file(bufnr, file)

		vim.schedule(function()
			render_pdf_preview(bufnr)
		end)
	end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "VimResized" }, {
	group = augroup("pdf_preview_refresh"),
	callback = function(event)
		if event.event == "VimResized" then
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if type(vim.b[bufnr].pdf_preview_file) == "string" then
					vim.schedule(function()
						render_pdf_preview(bufnr)
					end)
				end
			end
			return
		end

		local bufnr = event.buf or vim.api.nvim_get_current_buf()
		if bufnr == 0 then
			bufnr = vim.api.nvim_get_current_buf()
		end

		if type(vim.b[bufnr].pdf_preview_file) == "string" then
			vim.schedule(function()
				render_pdf_preview(bufnr)
			end)
		end
	end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
	group = augroup("pdf_preview_clear"),
	callback = function(event)
		clear_pdf_preview_images(event.buf)
		stop_pdf_watcher(event.buf)
	end,
})
