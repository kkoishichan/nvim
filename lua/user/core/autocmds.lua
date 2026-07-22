local augroup = function(name)
	return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end

-- Keep libuv resources owned by this module in a persistent lifecycle object.
-- Sourcing the module again first tears down the previous generation, instead
-- of leaving poll timers and file watchers alive with stale Lua closures.
local lifecycle_key = "_user_core_autocmds_lifecycle"
local previous_lifecycle = rawget(vim, lifecycle_key)
if type(previous_lifecycle) == "table" and type(previous_lifecycle.cleanup) == "function" then
	pcall(previous_lifecycle.cleanup)
end

local lifecycle = {
	closed = false,
	cleanup_callbacks = {},
	handles = {},
}
rawset(vim, lifecycle_key, lifecycle)

local function close_uv_handle(handle)
	if not handle then
		return
	end
	pcall(function()
		handle:stop()
	end)
	local ok, closing = pcall(function()
		return handle:is_closing()
	end)
	if not ok or not closing then
		pcall(function()
			handle:close()
		end)
	end
end

local function track_uv_handle(handle)
	if handle then
		lifecycle.handles[handle] = true
	end
	return handle
end

local function release_uv_handle(handle)
	close_uv_handle(handle)
	lifecycle.handles[handle] = nil
end

local function add_cleanup(callback)
	table.insert(lifecycle.cleanup_callbacks, callback)
end

local function cleanup_lifecycle()
	if lifecycle.closed then
		return
	end
	lifecycle.closed = true

	for index = #lifecycle.cleanup_callbacks, 1, -1 do
		pcall(lifecycle.cleanup_callbacks[index])
	end
	for handle in pairs(lifecycle.handles) do
		close_uv_handle(handle)
	end
	lifecycle.cleanup_callbacks = {}
	lifecycle.handles = {}
end

lifecycle.cleanup = cleanup_lifecycle

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = augroup("lifecycle"),
	once = true,
	callback = cleanup_lifecycle,
})

require("user.core.pdf")
require("user.core.sensitive").setup()

vim.api.nvim_create_autocmd("TextYankPost", {
	group = augroup("highlight_yank"),
	callback = function()
		vim.hl.on_yank({ timeout = 180 })
	end,
})

local panel_filetypes = {
	["neo-tree"] = true,
	Outline = true,
	OverseerList = true,
	OverseerOutput = true,
	qf = true,
	toggleterm = true,
	trouble = true,
}

local function is_fixed_panel(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local buftype = vim.bo[buf].buftype
	local filetype = vim.bo[buf].filetype
	return vim.wo[win].winfixwidth
		or vim.wo[win].winfixheight
		or buftype == "help"
		or buftype == "prompt"
		or buftype == "quickfix"
		or buftype == "terminal"
		or panel_filetypes[filetype]
		or filetype:match("^dap") ~= nil
		or vim.w[win].edgy_width ~= nil
		or vim.w[win].edgy_height ~= nil
end

local function equalize_tab_splits(tab)
	if not vim.api.nvim_tabpage_is_valid(tab) then
		return
	end

	local anchor
	local fixed = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			anchor = anchor or win
			if is_fixed_panel(win) then
				table.insert(fixed, {
					win = win,
					width = vim.wo[win].winfixwidth,
					height = vim.wo[win].winfixheight,
				})
				vim.wo[win].winfixwidth = true
				vim.wo[win].winfixheight = true
			end
		end
	end

	if anchor then
		-- nvim_win_call enters an inactive tab without changing the user's
		-- current tab/window after the callback returns.
		pcall(vim.api.nvim_win_call, anchor, function()
			vim.cmd("wincmd =")
		end)
	end

	for _, item in ipairs(fixed) do
		if vim.api.nvim_win_is_valid(item.win) then
			vim.wo[item.win].winfixwidth = item.width
			vim.wo[item.win].winfixheight = item.height
		end
	end
end

vim.api.nvim_create_autocmd("VimResized", {
	group = augroup("resize_splits"),
	callback = function()
		for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
			equalize_tab_splits(tab)
		end
	end,
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
--   * Detection is event-driven (focus / buffer / terminal switches give an
--     instant refresh). Optional focused polling covers the "window focused but
--     cursor idle" gap; :checktime then scans every loaded buffer.
--   * Reconciliation is decided in one place (FileChangedShell): clean buffers
--     reload silently; buffers with unsaved edits are never clobbered (warn
--     instead of the blocking W12 prompt); deleted files keep their buffer.
--   * Reload notices are coalesced/de-duplicated so a burst of edits is one line.
local external_changes = augroup("external_changes")

local function check_external_changes(bufnr)
	-- :checktime is illegal in the command-line window; harmless everywhere else.
	if vim.fn.getcmdwintype() ~= "" then
		return
	end
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.cmd.checktime, { args = { tostring(bufnr) } })
	else
		pcall(vim.cmd.checktime)
	end
end

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "TermLeave", "TermClose" }, {
	group = external_changes,
	callback = function(event)
		vim.schedule(function()
			-- Buffer switches check only the entered buffer; focus/terminal events
			-- intentionally reconcile every loaded file after external work.
			check_external_changes(event.event == "BufEnter" and event.buf or nil)
		end)
	end,
})

-- Event-driven checks cover normal use. Continuous polling is opt-in because
-- :checktime stats every loaded buffer; set g:user_external_change_poll_ms to a
-- positive interval if an external tool rewrites files while Neovim stays idle.
local poll_interval_ms = tonumber(vim.g.user_external_change_poll_ms) or 0
if poll_interval_ms > 0 then
	poll_interval_ms = math.max(250, math.floor(poll_interval_ms))
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

	local poll_timer = track_uv_handle(vim.uv.new_timer())
	if poll_timer then
		poll_timer:start(
			poll_interval_ms,
			poll_interval_ms,
			vim.schedule_wrap(function()
				if not lifecycle.closed and poll_focused then
					check_external_changes()
				end
			end)
		)
	end
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
local notice_timer = track_uv_handle(vim.uv.new_timer())
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = external_changes,
	callback = function(event)
		if lifecycle.closed then
			return
		end
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
				if lifecycle.closed then
					return
				end
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

-- `.v` is shared by Verilog and the V language. Native content detection gets
-- non-empty files right, but an initially empty file falls back to V. Mark only
-- that ambiguous empty-buffer case, then re-run the detector after an insert
-- session or normal-mode edit. Existing non-empty V files never pay this cost.
local ambiguous_v_filetype = augroup("ambiguous_v_filetype")
local function mark_empty_ambiguous_v(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr):lower()
	if
		name:match("%.v$")
		and vim.bo[bufnr].filetype == "v"
		and vim.api.nvim_buf_line_count(bufnr) == 1
		and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""
	then
		vim.b[bufnr].user_detect_ambiguous_v = true
	end
end

vim.api.nvim_create_autocmd("FileType", {
	group = ambiguous_v_filetype,
	pattern = "v",
	callback = function(event)
		mark_empty_ambiguous_v(event.buf)
	end,
})
for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_loaded(bufnr) then
		mark_empty_ambiguous_v(bufnr)
	end
end
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
	group = ambiguous_v_filetype,
	pattern = "*.v",
	callback = function(event)
		if not vim.b[event.buf].user_detect_ambiguous_v then
			return
		end
		if vim.bo[event.buf].filetype ~= "v" then
			vim.b[event.buf].user_detect_ambiguous_v = nil
			return
		end
		local detected = vim.filetype.match({ buf = event.buf })
		if detected == "verilog" then
			vim.b[event.buf].user_detect_ambiguous_v = nil
			vim.bo[event.buf].filetype = detected
		end
	end,
})

require("user.core.pdf_preview").setup({
	augroup = augroup,
	lifecycle = lifecycle,
	track_uv_handle = track_uv_handle,
	release_uv_handle = release_uv_handle,
	add_cleanup = add_cleanup,
})
