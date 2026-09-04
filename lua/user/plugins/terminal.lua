local layout = require("user.core.layout")

-- Each project keeps its own terminals and active selection. Hiding a panel
-- preserves its process and cwd; switching projects never sends a shell `cd`.
local states = {}
local next_count = 1

local function state_for(root)
	root = root or require("user.core.project").root()
	if not states[root] then
		states[root] = { root = root, bottom = {}, active = 1 }
	end
	return states[root]
end

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

local function allocate_count()
	local terminals = require("toggleterm.terminal")
	while terminals.get(next_count, true) do
		next_count = next_count + 1
	end
	local count = next_count
	next_count = next_count + 1
	return count
end

local function visible(term)
	if not term or not term.bufnr then
		return false
	end
	for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(window) == term.bufnr then
			return true
		end
	end
	return false
end

local function forget(state, term)
	local removed
	for index, candidate in ipairs(state.bottom) do
		if candidate == term then
			table.remove(state.bottom, index)
			removed = index
			break
		end
	end
	if removed then
		if removed < state.active then
			state.active = state.active - 1
		else
			state.active = math.max(1, math.min(state.active, #state.bottom))
		end
	end
end

local function label(name, state)
	return name .. " · " .. vim.fn.fnamemodify(state.root, ":~")
end

local function make_bottom(state)
	local count = allocate_count()
	local term = Terminal():new({
		count = count,
		dir = state.root,
		direction = "horizontal",
		display_name = label("term " .. count, state),
		user_terminal_name = "term " .. count,
		size = bottom_size(),
		on_create = function(created)
			vim.b[created.bufnr].user_project_root = state.root
		end,
		on_exit = function(exited)
			forget(state, exited)
		end,
	})
	table.insert(state.bottom, term)
	state.active = #state.bottom
	return term
end

local function any_open(state)
	for _, term in ipairs(state.bottom) do
		if visible(term) then
			return true
		end
	end
	return false
end

local function close_all(only)
	for _, state in pairs(only and { only } or states) do
		for _, term in ipairs(state.bottom) do
			if visible(term) then
				term:close()
			end
		end
	end
end

local function close_floats()
	for _, state in pairs(states) do
		if visible(state.float) then
			state.float:close()
		end
	end
end

local function show(state, term, keep_others)
	close_floats()
	if not keep_others then
		close_all()
	end
	term:open(bottom_size(), "horizontal")
	for index, candidate in ipairs(state.bottom) do
		if candidate == term then
			state.active = index
		end
	end
end

local M = {}

function M.toggle()
	local state = state_for()
	if visible(state.float) and state.float:is_focused() then
		close_floats()
		show(state, state.bottom[state.active] or make_bottom(state), false)
	elseif any_open(state) then
		close_all(state)
	else
		show(state, state.bottom[state.active] or make_bottom(state), false)
	end
end

function M.new()
	local state = state_for()
	show(state, make_bottom(state), false)
end

function M.split()
	local state = state_for()
	if not any_open(state) then
		show(state, state.bottom[state.active] or make_bottom(state), false)
	end
	show(state, make_bottom(state), true)
end

local function cycle(step)
	local state = state_for()
	if #state.bottom == 0 then
		M.new()
		return
	end
	state.active = ((state.active - 1 + step) % #state.bottom) + 1
	show(state, state.bottom[state.active], false)
end

function M.next()
	cycle(1)
end

function M.prev()
	cycle(-1)
end

function M.select()
	local state = state_for()
	if #state.bottom == 0 then
		M.new()
		return
	end
	vim.ui.select(vim.list_slice(state.bottom), {
		prompt = "Terminal · " .. vim.fn.fnamemodify(state.root, ":~"),
		format_item = function(term)
			local marker = state.bottom[state.active] == term and "  (current)" or ""
			return ("%s  (#%d)%s"):format(term.display_name, term.id, marker)
		end,
	}, function(term)
		if term and require("user.core.project").root() == state.root then
			for _, candidate in ipairs(state.bottom) do
				if candidate == term then
					show(state, term, false)
					break
				end
			end
		end
	end)
end

function M.kill()
	local state = state_for()
	local term = state.bottom[state.active]
	if not term then
		return
	end
	local ok = pcall(term.shutdown, term)
	if not ok then
		return
	end
	forget(state, term)
	if state.bottom[state.active] then
		show(state, state.bottom[state.active], false)
	end
end

function M.rename()
	local state = state_for()
	local term = state.bottom[state.active]
	if term then
		vim.ui.input({ prompt = "Terminal name: ", default = term.user_terminal_name or "terminal" }, function(name)
			if name and name ~= "" then
				term.user_terminal_name = name
				term.display_name = label(name, state)
			end
		end)
	end
end

function M.float()
	local state = state_for()
	if not state.float then
		state.float = Terminal():new({
			count = allocate_count(),
			dir = state.root,
			direction = "float",
			display_name = label("terminal", state),
			on_create = function(created)
				vim.b[created.bufnr].user_project_root = state.root
			end,
			on_exit = function()
				state.float = nil
			end,
			float_opts = { border = "rounded", width = float_width, height = float_height, title_pos = "center" },
		})
	end
	if not visible(state.float) then
		close_floats()
	end
	state.float:toggle(nil, "float")
	if visible(state.float) then
		require("user.core.backdrop").open(state.float.window)
	end
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
	-- Legacy xterm/SSH sends Ctrl-/ as the US byte, decoded as Ctrl-_.
	map("<C-_>", function()
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
			-- The application-sized float terminal keeps the shared accent frame.
			highlights = {
				FloatBorder = { link = "FloatBorder" },
				NormalFloat = { link = "NormalFloat" },
			},
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
				"<C-_>",
				function()
					M.toggle()
				end,
				desc = "Toggle terminal (legacy terminal)",
			},
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
