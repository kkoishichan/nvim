local map = vim.keymap.set

map({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

map("n", "<leader>w", "<cmd>write<cr>", { desc = "Write file" })
map("n", "<leader>q", "<cmd>quit<cr>", { desc = "Quit window" })
map("n", "<leader>Q", "<cmd>qa<cr>", { desc = "Quit all" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight", silent = true })

map("n", "<leader>-", "<cmd>split<cr>", { desc = "Split window below" })
map("n", "<leader>|", "<cmd>vsplit<cr>", { desc = "Split window right" })

map("n", "<C-h>", "<C-w>h", { desc = "Focus left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus right window" })

map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase width" })

map("n", "<leader>gD", "<cmd>DiffDisk<cr>", { desc = "Diff disk" })
map("n", "<leader>mo", "<cmd>PdfOpen<cr>", { desc = "Open PDF" })
map("n", "<leader>f.", "<cmd>FileDir<cr>", { desc = "File directory" })
map("n", "<leader>fd", "<cmd>DirectoryPick<cr>", { desc = "Find directory" })
map("n", "<leader>fp", "<cmd>ProjectPick<cr>", { desc = "Find project" })
map("n", "<leader>fr", "<cmd>ProjectRoot<cr>", { desc = "Project root" })

map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

map("n", "J", "mzJ`z", { desc = "Join lines" })
map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Previous search result" })

map("n", "]q", "<cmd>cnext<cr>zz", { desc = "Next quickfix item" })
map("n", "[q", "<cmd>cprev<cr>zz", { desc = "Previous quickfix item" })
map("n", "]Q", "<cmd>clast<cr>zz", { desc = "Last quickfix item" })
map("n", "[Q", "<cmd>cfirst<cr>zz", { desc = "First quickfix item" })
map("n", "]l", "<cmd>lnext<cr>zz", { desc = "Next location item" })
map("n", "[l", "<cmd>lprev<cr>zz", { desc = "Previous location item" })
map("n", "]L", "<cmd>llast<cr>zz", { desc = "Last location item" })
map("n", "[L", "<cmd>lfirst<cr>zz", { desc = "First location item" })

local function toggle_qf(kind)
	local prefix = kind == "loc" and "l" or "c"
	for _, win in ipairs(vim.fn.getwininfo()) do
		local open = kind == "loc" and (win.loclist == 1) or (win.quickfix == 1 and win.loclist == 0)
		if open then
			vim.cmd(prefix .. "close")
			return
		end
	end
	local ok = pcall(vim.cmd, (kind == "loc" and "botright lopen" or "botright copen"))
	if not ok then
		vim.notify((kind == "loc" and "Location" or "Quickfix") .. " list is empty", vim.log.levels.INFO)
	end
end

map("n", "<leader>xc", function()
	toggle_qf("qf")
end, { desc = "Quickfix window" })
map("n", "<leader>xC", function()
	toggle_qf("loc")
end, { desc = "Location window" })

map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })

map("n", "<leader>ul", function()
	vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = "Toggle relative line numbers" })

map("n", "<leader>uw", function()
	vim.opt.wrap = not vim.opt.wrap:get()
end, { desc = "Toggle wrap" })

map("n", "<leader>L", "<cmd>Lazy<cr>", { desc = "Lazy" })
map("n", "<leader>M", "<cmd>Mason<cr>", { desc = "Mason" })
