local layout = require("user.core.layout")

-- VSCode-like terminal management on top of toggleterm:
--   * a bottom panel that holds multiple terminals
--   * new / split (side-by-side) / next / prev / select / kill / rename
--   * a floating terminal as a bonus
-- One bottom terminal is shown at a time (switch via next/prev/select), except
-- after `split`, which keeps the current one open and tiles a new one beside it.

local state = {
	bottom = {}, -- list of bottom Terminal objects
	active = 1, -- index into state.bottom
	next_count = 1, -- toggleterm count allocator for bottom terminals
	float = nil,
	float_count = 100,
}

local function bottom_size()
	return math.max(10, math.min(18, math.floor((vim.o.lines or 40) * 0.28)))
end

local function float_width()
	return math.max(1, math.ceil((vim.o.columns or 80) * layout.float_scale))
end

local function float_height()
	return math.max(1, math.ceil((vim.o.lines or 40) * layout.float_scale) - 1)
end

local function Terminal()
	return require("toggleterm.terminal").Terminal
end

local function forget(term)
	for index, t in ipairs(state.bottom) do
		if t.id == term.id then
			table.remove(state.bottom, index)
			break
		end
	end
	if state.active > #state.bottom then
		state.active = math.max(1, #state.bottom)
	end
end

local function make_bottom()
	local term = Terminal():new({
		count = state.next_count,
		direction = "horizontal",
		display_name = "term " .. state.next_count,
		size = bottom_size(),
		on_exit = function(t)
			forget(t)
		end,
	})
	state.next_count = state.next_count + 1
	table.insert(state.bottom, term)
	state.active = #state.bottom
	return term
end

local function any_open()
	for _, t in ipairs(state.bottom) do
		if t:is_open() then
			return true
		end
	end
	return false
end

local function close_all()
	for _, t in ipairs(state.bottom) do
		if t:is_open() then
			t:close()
		end
	end
end

local function show(term, keep_others)
	if not keep_others then
		close_all()
	end
	term:open(bottom_size(), "horizontal")
	for index, t in ipairs(state.bottom) do
		if t.id == term.id then
			state.active = index
		end
	end
end

local M = {}

function M.toggle()
	if any_open() then
		close_all()
		return
	end
	show(state.bottom[state.active] or make_bottom(), false)
end

function M.new()
	show(make_bottom(), false)
end

function M.split()
	if not any_open() then
		show(state.bottom[state.active] or make_bottom(), false)
	end
	show(make_bottom(), true)
end

local function cycle(step)
	if #state.bottom == 0 then
		M.new()
		return
	end
	state.active = ((state.active - 1 + step) % #state.bottom) + 1
	show(state.bottom[state.active], false)
end

function M.next()
	cycle(1)
end

function M.prev()
	cycle(-1)
end

function M.select()
	vim.cmd("TermSelect")
end

function M.kill()
	local term = state.bottom[state.active]
	if not term then
		return
	end
	pcall(function()
		term:shutdown()
	end)
	forget(term)
	if state.bottom[state.active] then
		show(state.bottom[state.active], false)
	end
end

function M.rename()
	local term = state.bottom[state.active]
	if not term then
		return
	end
	vim.ui.input({ prompt = "Terminal name: ", default = term.display_name }, function(name)
		if name and name ~= "" then
			term.display_name = name
		end
	end)
end

function M.float()
	if not state.float then
		state.float = Terminal():new({
			count = state.float_count,
			direction = "float",
			display_name = "float",
			float_opts = {
				border = "rounded",
				width = float_width,
				height = float_height,
				title_pos = "center",
			},
		})
		state.float_count = state.float_count + 1
	end
	state.float:toggle(nil, "float")
end

local function set_terminal_keymaps(term)
	local opts = { buffer = term.bufnr, silent = true }
	local function map(lhs, rhs, desc)
		vim.keymap.set("t", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
	end

	map("<Esc><Esc>", "<C-\\><C-n>", "Leave terminal mode")
	map("<C-h>", "<C-\\><C-n><C-w>h", "Focus left window")
	map("<C-j>", "<C-\\><C-n><C-w>j", "Focus lower window")
	map("<C-k>", "<C-\\><C-n><C-w>k", "Focus upper window")
	map("<C-l>", "<C-\\><C-n><C-w>l", "Focus right window")
	map("<C-Up>", "<C-\\><C-n><cmd>resize +2<cr>", "Increase height")
	map("<C-Down>", "<C-\\><C-n><cmd>resize -2<cr>", "Decrease height")
	map("<C-Left>", "<C-\\><C-n><cmd>vertical resize -2<cr>", "Decrease width")
	map("<C-Right>", "<C-\\><C-n><cmd>vertical resize +2<cr>", "Increase width")
	map("<C-/>", function()
		M.toggle()
	end, "Toggle terminal")
	vim.keymap.set("n", "q", function()
		term:close()
	end, vim.tbl_extend("force", opts, { desc = "Hide terminal" }))
end

return {
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		cmd = {
			"TermExec",
			"TermSelect",
			"ToggleTerm",
			"ToggleTermSendCurrentLine",
			"ToggleTermSendVisualLines",
			"ToggleTermSendVisualSelection",
			"ToggleTermSetName",
		},
		opts = {
			auto_scroll = true,
			close_on_exit = true,
			direction = "horizontal",
			hide_numbers = true,
			insert_mappings = false,
			open_mapping = false,
			persist_mode = true,
			persist_size = true,
			shade_terminals = false,
			shell = vim.o.shell,
			size = bottom_size(),
			start_in_insert = true,
			terminal_mappings = false,
			float_opts = {
				border = "rounded",
				width = float_width,
				height = float_height,
				title_pos = "center",
			},
			on_open = set_terminal_keymaps,
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)
		end,
		keys = {
			{
				"<C-/>",
				function()
					M.toggle()
				end,
				desc = "Toggle terminal",
			},
			{
				"<leader>tt",
				function()
					M.toggle()
				end,
				desc = "Toggle terminal",
			},
			{
				"<leader>tn",
				function()
					M.new()
				end,
				desc = "New terminal",
			},
			{
				"<leader>ts",
				function()
					M.split()
				end,
				desc = "Split terminal",
			},
			{
				"<leader>t]",
				function()
					M.next()
				end,
				desc = "Next terminal",
			},
			{
				"<leader>t[",
				function()
					M.prev()
				end,
				desc = "Previous terminal",
			},
			{
				"<leader>tl",
				function()
					M.select()
				end,
				desc = "Select terminal",
			},
			{
				"<leader>tk",
				function()
					M.kill()
				end,
				desc = "Kill terminal",
			},
			{
				"<leader>tr",
				function()
					M.rename()
				end,
				desc = "Rename terminal",
			},
			{
				"<leader>tf",
				function()
					M.float()
				end,
				desc = "Float terminal",
			},
		},
	},
}
