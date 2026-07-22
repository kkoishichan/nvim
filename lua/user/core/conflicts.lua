local M = {}
local namespace = vim.api.nvim_create_namespace("user_git_conflicts")
local refresh

local function apply_highlights()
	vim.api.nvim_set_hl(0, "UserConflictCurrent", { default = true, link = "DiffText" })
	vim.api.nvim_set_hl(0, "UserConflictBase", { default = true, link = "DiffChange" })
	vim.api.nvim_set_hl(0, "UserConflictIncoming", { default = true, link = "DiffAdd" })
	vim.api.nvim_set_hl(0, "UserConflictMarker", { default = true, link = "DiffDelete" })
end

local function set_line_highlight(bufnr, row, group)
	vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
		line_hl_group = group,
		priority = 90,
	})
end

local function render_conflicts(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

	local has_conflict = false
	local section
	if vim.bo[bufnr].buftype == "" and not vim.b[bufnr].bigfile then
		for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
			local row = index - 1
			if line:match("^<<<<<<<") then
				has_conflict = true
				section = "UserConflictCurrent"
				set_line_highlight(bufnr, row, "UserConflictMarker")
			elseif section and line:match("^|||||||") then
				section = "UserConflictBase"
				set_line_highlight(bufnr, row, "UserConflictMarker")
			elseif section and line:match("^=======$") then
				section = "UserConflictIncoming"
				set_line_highlight(bufnr, row, "UserConflictMarker")
			elseif section and line:match("^>>>>>>>") then
				section = nil
				set_line_highlight(bufnr, row, "UserConflictMarker")
			elseif section then
				set_line_highlight(bufnr, row, section)
			end
		end
	end

	vim.b[bufnr].user_has_conflicts = has_conflict
	if has_conflict and vim.diagnostic.is_enabled({ bufnr = bufnr }) then
		vim.diagnostic.enable(false, { bufnr = bufnr })
		vim.b[bufnr].user_conflict_disabled_diagnostics = true
	elseif not has_conflict and vim.b[bufnr].user_conflict_disabled_diagnostics then
		vim.b[bufnr].user_conflict_disabled_diagnostics = nil
		vim.diagnostic.enable(true, { bufnr = bufnr })
	end
end

local pending_refresh = {}
refresh = function(bufnr, delay)
	pending_refresh[bufnr] = (pending_refresh[bufnr] or 0) + 1
	local generation = pending_refresh[bufnr]
	vim.defer_fn(function()
		if pending_refresh[bufnr] == generation then
			pending_refresh[bufnr] = nil
			render_conflicts(bufnr)
		end
	end, delay or 0)
end

local function conflict_at_cursor()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)[1]
	local first
	for line = cursor, 1, -1 do
		if lines[line]:match("^<<<<<<<") then
			first = line
			break
		end
		if lines[line]:match("^>>>>>>>") then
			break
		end
	end
	if not first then
		return nil
	end

	local base
	local separator
	local last
	for line = first + 1, #lines do
		if not base and lines[line]:match("^|||||||") then
			base = line
		elseif lines[line]:match("^=======$") then
			separator = line
		elseif lines[line]:match("^>>>>>>>") then
			last = line
			break
		elseif lines[line]:match("^<<<<<<<") then
			break
		end
	end
	if not separator or not last or cursor > last then
		return nil
	end
	return { first = first, base = base, separator = separator, last = last, lines = lines }
end

local function range(lines, first, last)
	local result = {}
	for line = first, last do
		table.insert(result, lines[line])
	end
	return result
end

local function choose(kind)
	local conflict = conflict_at_cursor()
	if not conflict then
		vim.notify("Cursor is not inside a Git conflict", vim.log.levels.WARN, { title = "Git conflict" })
		return
	end

	local ours_last = (conflict.base or conflict.separator) - 1
	local ours = range(conflict.lines, conflict.first + 1, ours_last)
	local theirs = range(conflict.lines, conflict.separator + 1, conflict.last - 1)
	local replacement
	if kind == "ours" then
		replacement = ours
	elseif kind == "theirs" then
		replacement = theirs
	elseif kind == "both" then
		replacement = vim.list_extend(ours, theirs)
	else
		replacement = {}
	end

	vim.api.nvim_buf_set_lines(0, conflict.first - 1, conflict.last, false, replacement)
	vim.api.nvim_win_set_cursor(0, { math.min(conflict.first, vim.api.nvim_buf_line_count(0)), 0 })
	refresh(vim.api.nvim_get_current_buf())
end

local function jump(backward)
	local flags = backward and "b" or ""
	for _ = 1, vim.v.count1 do
		if vim.fn.search("^<<<<<<<", flags) == 0 then
			vim.notify("No Git conflict marker found", vim.log.levels.INFO, { title = "Git conflict" })
			return
		end
	end
	vim.cmd.normal({ "zz", bang = true })
end

local function populate_quickfix()
	local items = {}
	for line, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		if text:match("^<<<<<<<") then
			table.insert(items, {
				bufnr = vim.api.nvim_get_current_buf(),
				lnum = line,
				col = 1,
				text = text,
				type = "W",
			})
		end
	end
	vim.fn.setqflist({}, " ", { title = "Git conflicts", items = items })
	if #items > 0 then
		vim.cmd.copen()
	else
		vim.notify("No Git conflicts in the current buffer", vim.log.levels.INFO, { title = "Git conflict" })
	end
end

function M.setup()
	apply_highlights()
	local group = vim.api.nvim_create_augroup("user_git_conflicts", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = apply_highlights,
	})
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost", "FileChangedShellPost" }, {
		group = group,
		callback = function(event)
			refresh(event.buf, 20)
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(event)
			if vim.b[event.buf].user_has_conflicts then
				refresh(event.buf, 40)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			pending_refresh[event.buf] = nil
		end,
	})

	vim.api.nvim_create_user_command("GitConflictChooseOurs", function()
		choose("ours")
	end, { desc = "Keep the current side of this conflict" })
	vim.api.nvim_create_user_command("GitConflictChooseTheirs", function()
		choose("theirs")
	end, { desc = "Keep the incoming side of this conflict" })
	vim.api.nvim_create_user_command("GitConflictChooseBoth", function()
		choose("both")
	end, { desc = "Keep both sides of this conflict" })
	vim.api.nvim_create_user_command("GitConflictChooseNone", function()
		choose("none")
	end, { desc = "Remove both sides of this conflict" })
	vim.api.nvim_create_user_command("GitConflictListQf", populate_quickfix, {
		desc = "List conflicts in the current buffer",
	})

	vim.keymap.set("n", "]x", function()
		jump(false)
	end, { desc = "Next conflict" })
	vim.keymap.set("n", "[x", function()
		jump(true)
	end, { desc = "Previous conflict" })
	vim.keymap.set("n", "<leader>gxo", "<cmd>GitConflictChooseOurs<cr>", { desc = "Conflict choose ours" })
	vim.keymap.set("n", "<leader>gxt", "<cmd>GitConflictChooseTheirs<cr>", { desc = "Conflict choose theirs" })
	vim.keymap.set("n", "<leader>gxb", "<cmd>GitConflictChooseBoth<cr>", { desc = "Conflict choose both" })
	vim.keymap.set("n", "<leader>gx0", "<cmd>GitConflictChooseNone<cr>", { desc = "Conflict choose none" })
	vim.keymap.set("n", "<leader>gxl", "<cmd>GitConflictListQf<cr>", { desc = "Conflict quickfix list" })
end

return M
