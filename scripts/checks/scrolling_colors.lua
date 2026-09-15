return function(tmp)
	local api = vim.api
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "all"
	require("lazy").load({ plugins = { "nvim-highlight-colors" } })
	local plugin = require("nvim-highlight-colors")
	local bridge = require("user.core.color_preview")
	local utils = require("nvim-highlight-colors.utils")
	local colors = require("nvim-highlight-colors.color.utils")
	local buffer_utils = require("nvim-highlight-colors.buffer_utils")
	local opts = require("lazy.core.config").plugins["nvim-highlight-colors"].opts
	local namespace = assert(api.nvim_get_namespaces()["nvim-highlight-colors"], "Color namespace is missing")
	local original_rows, original_lsp = utils.get_visible_rows_by_buffer_id, utils.highlight_with_lsp
	local original_css = colors.get_css_var_color
	local counts = { lsp = {}, css = {} }
	local function drain()
		vim.wait(120, function()
			return false
		end, 5)
	end
	local function buffer(name)
		local buf = api.nvim_create_buf(true, false)
		api.nvim_buf_set_name(buf, tmp .. "/" .. name .. ".lua")
		local lines = {}
		for index = 1, 600 do
			lines[index] = "do local color = '#abcdef' end"
		end
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = "lua"
		return buf
	end
	local function view(win, row)
		api.nvim_win_call(win, function()
			vim.wo.wrap, vim.wo.foldenable, vim.wo.scrolloff = false, false, 0
			api.nvim_win_set_cursor(win, { row, 0 })
			vim.cmd.normal({ "zt", bang = true })
		end)
	end
	local function scroll(win)
		local events = api.nvim_get_autocmds({ group = "user_color_preview", event = "WinScrolled" })
		assert(#events == 1, "Color scroll handler duplicated after setup")
		events[1].callback({ match = tostring(win), buf = api.nvim_get_current_buf() })
	end
	local function marks(buf)
		return api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
	end
	local function check_viewports(buf, windows)
		local expected, actual = {}, {}
		for _, win in ipairs(windows) do
			api.nvim_win_call(win, function()
				for row = vim.fn.line("w0") - 1, vim.fn.line("w$") - 1 do
					expected[row] = true
				end
			end)
		end
		for _, mark in ipairs(marks(buf)) do
			assert(not actual[mark[2]], "Scroll accumulated duplicate color extmarks")
			actual[mark[2]] = true
		end
		assert(vim.deep_equal(actual, expected), "Color marks did not match the visible viewport union")
		assert(utils.get_visible_rows_by_buffer_id == original_rows, "Viewport helper was left replaced")
		assert(utils.highlight_with_lsp == original_lsp, "LSP helper was left replaced")
		assert(colors.get_css_var_color == original_css, "CSS helper was left replaced")
	end
	vim.cmd.tabnew()
	local first_win = api.nvim_get_current_win()
	local first = buffer("colors-first")
	api.nvim_win_set_buf(first_win, first)
	view(first_win, 1)
	bridge.setup(opts)
	drain()
	check_viewports(first, { first_win })
	local source = debug.getinfo(plugin.setup, "S").source
	local changed
	for _, event in ipairs(api.nvim_get_autocmds({ event = "TextChanged" })) do
		if type(event.callback) == "function" and debug.getinfo(event.callback, "S").source == source then
			changed = event.callback
		end
	end
	assert(changed, "Original immediate text-change callback was removed")
	api.nvim_buf_set_lines(first, 0, 1, false, { "do local color = '#fedcba' end" })
	changed({ buf = first })
	local updated = false
	for _, mark in ipairs(marks(first)) do
		if mark[2] == 0 then
			updated = api.nvim_get_hl(0, { name = mark[4].hl_group }).bg == 0xfedcba
		end
	end
	assert(updated, "Editing a color did not immediately update its highlight")
	check_viewports(first, { first_win })
	local scan, scans = buffer_utils.get_positions_by_regex, 0
	buffer_utils.get_positions_by_regex = function(...)
		scans = scans + 1
		return scan(...)
	end
	for index = 1, 40 do
		view(first_win, index % 2 == 0 and 1 or 100)
		scroll(first_win)
	end
	assert(scans == 0, "Wheel events synchronously scanned colors")
	drain()
	buffer_utils.get_positions_by_regex = scan
	assert(scans == 1, "A wheel burst was not coalesced into one viewport scan")
	check_viewports(first, { first_win })
	view(first_win, 400)
	scroll(first_win)
	drain()
	check_viewports(first, { first_win })

	vim.cmd.vsplit()
	local second_win = api.nvim_get_current_win()
	view(first_win, 1)
	view(second_win, 450)
	api.nvim_set_current_win(first_win)
	local lsp_passes, requests, capable, attached = 0, 0, false, false
	local get_clients = vim.lsp.get_clients
	local client = {
		supports_method = function(_, method, buf)
			assert(method == "textDocument/documentColor" and buf == first, "Incorrect color capability query")
			return capable
		end,
		request = function(_, method, _, callback, buf)
			assert(method == "textDocument/documentColor" and buf == first, "Incorrect color request context")
			requests = requests + 1
			callback(nil, {})
		end,
	}
	vim.lsp.get_clients = function(filter)
		if filter.bufnr ~= first or filter.name or not attached then
			return {}
		end
		if filter.method and not client:supports_method(filter.method, filter.bufnr) then
			return {}
		end
		return { client }
	end
	utils.highlight_with_lsp = function(...)
		lsp_passes = lsp_passes + 1
		return original_lsp(...)
	end
	scroll(second_win)
	drain()
	counts.lsp.without_client = lsp_passes
	assert(lsp_passes == 0, "No-client viewport invoked the upstream LSP pass")
	attached = true
	scroll(second_win)
	drain()
	counts.lsp.without_capability = lsp_passes
	assert(lsp_passes == 0, "A client without documentColor invoked the upstream LSP pass")
	capable = true
	scroll(second_win)
	drain()
	counts.lsp.with_capability = lsp_passes
	assert(requests == 1, "Dynamic documentColor registration did not issue exactly one request")
	capable = false
	scroll(second_win)
	drain()
	counts.lsp.after_capability_removed = lsp_passes - counts.lsp.with_capability
	assert(requests == 1 and lsp_passes == 1, "Removed documentColor capability still invoked an LSP pass")
	utils.highlight_with_lsp = original_lsp
	vim.lsp.get_clients = get_clients
	-- Upstream documentColor callbacks can still arrive after a newer batch.
	-- This check prevents multiple requests caused by our split rendering only.
	assert(lsp_passes == 1, "Two viewports issued multiple whole-document LSP passes")
	check_viewports(first, { first_win, second_win })
	assert(api.nvim_get_current_win() == first_win, "Scrolling another split changed focus")
	local second = buffer("colors-second")
	api.nvim_win_set_buf(second_win, second)
	view(second_win, 300)
	scroll(second_win)
	drain()
	check_viewports(second, { second_win })
	assert(api.nvim_get_current_win() == first_win, "Background buffer refresh changed focus")

	plugin.turnOff()
	scroll(second_win)
	drain()
	assert(#marks(first) == 0 and #marks(second) == 0 and not plugin.is_active(), "Pending scroll defeated toggle off")
	plugin.turnOn()
	scroll(second_win)
	drain()
	check_viewports(second, { second_win })

	local create, notify, errors = utils.create_highlight, vim.notify, 0
	utils.create_highlight = function()
		error("injected color preview error")
	end
	vim.notify = function(message, ...)
		if tostring(message):find("injected color preview error", 1, true) then
			errors = errors + 1
		else
			notify(message, ...)
		end
	end
	scroll(second_win)
	drain()
	utils.create_highlight, vim.notify = create, notify
	assert(errors == 1, "Injected renderer failure was not reported")
	assert(
		utils.get_visible_rows_by_buffer_id == original_rows
			and utils.highlight_with_lsp == original_lsp
			and colors.get_css_var_color == original_css,
		"Renderer failure leaked a temporary helper"
	)
	scroll(second_win)
	drain()
	check_viewports(second, { second_win })

	-- Count the real resolver's whole-buffer scans, keeping its parser intact.
	-- The variable definition is outside both viewports, and missing variables
	-- must be memoized too. Content edits, undo and reload must discard results.
	local function css_buffer(name, color)
		local buf = buffer(name)
		local lines = { ":root { --brand: " .. color .. "; }" }
		for index = 2, 600 do
			lines[index] = ".sample { color: var(--brand); background: var(--missing); }"
		end
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = "css"
		return buf
	end
	local function check_color(buf, win, color)
		check_viewports(buf, { win })
		for _, mark in ipairs(marks(buf)) do
			assert(
				api.nvim_get_hl(0, { name = mark[4].hl_group }).bg == color,
				"CSS variable resolved stale/wrong buffer text"
			)
		end
	end
	local css = css_buffer("colors-vars", "#123456")
	api.nvim_win_set_buf(second_win, css)
	view(second_win, 200)
	local full_reads = {}
	buffer_utils.get_positions_by_regex = function(patterns, first_row, last_row, buf, offset)
		local current = api.nvim_get_current_buf()
		if buf == 0 and first_row == 0 and last_row == api.nvim_buf_line_count(current) then
			full_reads[current] = (full_reads[current] or 0) + 1
		end
		return scan(patterns, first_row, last_row, buf, offset)
	end
	api.nvim_win_call(second_win, function()
		changed({ buf = css })
	end)
	counts.css.original_one_viewport = full_reads[css]
	assert(full_reads[css] > 2, "CSS fixture did not exercise repeated upstream variable resolution")
	full_reads[css] = 0
	scroll(second_win)
	drain()
	counts.css.cached_cold = full_reads[css]
	assert(full_reads[css] == 2, "Repeated CSS uses did not reuse one result per variable, including nil")
	check_color(css, second_win, 0x123456)
	for index = 1, 6 do
		view(second_win, 200 + index * 20)
		scroll(second_win)
		drain()
	end
	counts.css.cached_warm_six_viewports = full_reads[css] - counts.css.cached_cold
	assert(full_reads[css] == 2, "Unchanged CSS was rescanned after scrolling")
	check_color(css, second_win, 0x123456)
	api.nvim_buf_set_lines(css, 0, 1, false, { ":root { --brand: #654321; }" })
	scroll(second_win)
	drain()
	check_color(css, second_win, 0x654321)
	assert(full_reads[css] == 4, "A changed CSS definition reused the previous text version")
	api.nvim_win_call(second_win, function()
		vim.cmd("let &l:undolevels = &l:undolevels")
		vim.cmd.normal({ 'gg"_dd', bang = true })
	end)
	view(second_win, 200)
	scroll(second_win)
	drain()
	assert(#marks(css) == 0, "Deleting a CSS definition retained its cached color")
	local after_delete = full_reads[css]
	scroll(second_win)
	drain()
	assert(full_reads[css] == after_delete, "A missing CSS definition was not memoized")
	api.nvim_win_call(second_win, function()
		vim.cmd("silent undo")
	end)
	view(second_win, 200)
	scroll(second_win)
	drain()
	check_color(css, second_win, 0x654321)
	local other_css = css_buffer("colors-other-vars", "#aa55cc")
	api.nvim_win_set_buf(first_win, other_css)
	view(first_win, 200)
	scroll(first_win)
	scroll(second_win)
	drain()
	check_color(other_css, first_win, 0xaa55cc)
	check_color(css, second_win, 0x654321)
	assert(api.nvim_get_current_buf() == other_css, "CSS resolution changed the focused buffer")
	local reload_lines = api.nvim_buf_get_lines(css, 0, -1, false)
	reload_lines[1] = ":root { --brand: #13579b; }"
	vim.fn.writefile(reload_lines, api.nvim_buf_get_name(css))
	api.nvim_win_call(second_win, function()
		vim.cmd.edit({ bang = true })
	end)
	view(second_win, 200)
	scroll(second_win)
	drain()
	check_color(css, second_win, 0x13579b)
	bridge.shutdown()
	bridge.setup(opts)
	local before_setup_drain = full_reads[css]
	drain()
	assert(full_reads[css] - before_setup_drain == 2, "Setup/shutdown retained CSS cache entries")
	check_color(css, second_win, 0x13579b)
	buffer_utils.get_positions_by_regex = scan
	api.nvim_win_set_buf(first_win, first)
	api.nvim_win_set_buf(second_win, second)
	api.nvim_buf_delete(css, { force = true })
	api.nvim_buf_delete(other_css, { force = true })
	view(first_win, 1)
	view(second_win, 300)

	-- Adapter reload must reuse the actual plugin instance's captured handlers
	-- and invalidate the previous adapter's already queued callback.
	scroll(second_win)
	package.loaded["user.core.color_preview"] = nil
	bridge = require("user.core.color_preview")
	bridge.setup(opts)
	bridge.setup(opts)
	drain()
	scroll(second_win)
	drain()
	check_viewports(second, { second_win })
	for _, event in ipairs(api.nvim_get_autocmds({ event = { "WinScrolled", "VimResized" } })) do
		assert(
			type(event.callback) ~= "function" or debug.getinfo(event.callback, "S").source ~= source,
			"Original synchronous color scroll callback survived"
		)
	end

	-- Unloading/wiping a queued target and shutting down must not read it later.
	scans = 0
	buffer_utils.get_positions_by_regex = function(...)
		scans = scans + 1
		return scan(...)
	end
	scroll(second_win)
	api.nvim_buf_delete(second, { force = true })
	bridge.shutdown()
	drain()
	buffer_utils.get_positions_by_regex = scan
	assert(scans == 0, "Queued color work survived buffer deletion/shutdown")
	assert(
		utils.get_visible_rows_by_buffer_id == original_rows
			and utils.highlight_with_lsp == original_lsp
			and colors.get_css_var_color == original_css,
		"Cleanup leaked a helper"
	)
	bridge.setup(opts)
	drain()
	vim.o.eventignore = old_ignore
	if vim.env.NVIM_COLOR_COUNTS then
		vim.fn.writefile({ vim.json.encode(counts) }, vim.env.NVIM_COLOR_COUNTS)
	end
	print("Scrolling colors passed: coalescing, bounded marks, split viewports, dynamic LSP, CSS cache and cleanup")
end
