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

map("n", "<leader>k", function()
	require("user.core.dict").lookup()
end, { desc = "Dictionary" })
map("x", "<leader>k", function()
	require("user.core.dict").lookup_visual()
end, { desc = "Dictionary" })

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
	local info
	if kind == "loc" then
		-- Location lists belong to a window. Querying the current window also
		-- works while focused in its location-list window.
		info = vim.fn.getloclist(0, { winid = 0 })
	else
		-- getqflist({ winid = 0 }) only reports the quickfix window in the
		-- current tab, so a list displayed in another tab is left untouched.
		info = vim.fn.getqflist({ winid = 0 })
	end

	local winid = type(info) == "table" and tonumber(info.winid) or 0
	if winid and winid > 0 and vim.api.nvim_win_is_valid(winid) then
		vim.cmd(kind == "loc" and "lclose" or "cclose")
		return
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

-- Parse $TERMINAL into argv without invoking a shell. Supports the quoting and
-- backslash escaping normally needed for terminal options, but intentionally
-- performs no expansion or command substitution.
local function command_argv(command)
	local argv = {}
	local current = {}
	local quote
	local escaped = false
	local started = false

	for index = 1, #command do
		local char = command:sub(index, index)
		if escaped then
			table.insert(current, char)
			escaped = false
			started = true
		elseif quote then
			if char == quote then
				quote = nil
			elseif char == "\\" and quote == '"' then
				escaped = true
			else
				table.insert(current, char)
			end
		elseif char == "'" or char == '"' then
			quote = char
			started = true
		elseif char == "\\" then
			escaped = true
			started = true
		elseif char:match("%s") then
			if started then
				table.insert(argv, table.concat(current))
				current = {}
				started = false
			end
		else
			table.insert(current, char)
			started = true
		end
	end

	if escaped or quote then
		return nil
	end
	if started then
		table.insert(argv, table.concat(current))
	end
	return argv
end

local function open_external_terminal(dir)
	local configured = vim.env.TERMINAL
	local argv
	if configured and configured ~= "" then
		local parsed = command_argv(configured)
		if not parsed or #parsed == 0 then
			vim.notify("Invalid $TERMINAL: " .. configured, vim.log.levels.ERROR)
			return
		end
		argv = parsed
	else
		for _, candidate in ipairs({
			"kitty",
			"wezterm",
			"alacritty",
			"footclient",
			"foot",
			"gnome-terminal",
			"konsole",
			"xfce4-terminal",
			"xterm",
		}) do
			if vim.fn.executable(candidate) == 1 then
				argv = { candidate }
				break
			end
		end
	end

	if not argv or vim.fn.executable(argv[1]) == 0 then
		vim.notify("Terminal not found: " .. (argv and argv[1] or "no supported terminal"), vim.log.levels.ERROR)
		return
	end

	dir = vim.fs.normalize(dir)
	local executable = vim.fn.fnamemodify(argv[1], ":t"):lower():gsub("%.exe$", "")
	local cwd_args = {
		alacritty = { "--working-directory", dir },
		foot = { "--working-directory=" .. dir },
		footclient = { "--working-directory=" .. dir },
		["gnome-terminal"] = { "--working-directory=" .. dir },
		kitty = { "--directory", dir },
		konsole = { "--workdir", dir },
		["xfce4-terminal"] = { "--working-directory", dir },
	}

	if executable == "wezterm" then
		if #argv == 1 then
			vim.list_extend(argv, { "start", "--cwd", dir })
		elseif vim.tbl_contains(argv, "start") then
			vim.list_extend(argv, { "--cwd", dir })
		end
	elseif cwd_args[executable] then
		vim.list_extend(argv, cwd_args[executable])
	end

	-- `cwd` is a safe, terminal-agnostic fallback (and also covers terminals
	-- such as xterm); known terminals additionally receive their native flag
	-- for single-instance/server modes that may not inherit the child cwd.
	local ok, job = pcall(vim.fn.jobstart, argv, { cwd = dir, detach = true })
	if not ok or type(job) ~= "number" or job <= 0 then
		vim.notify("Failed to start terminal: " .. argv[1], vim.log.levels.ERROR)
	end
end

map("n", "<leader>te", function()
	-- Current file's directory, falling back to cwd for unnamed/scratch buffers.
	local file = vim.api.nvim_buf_get_name(0)
	local dir = (file ~= "" and vim.fn.filereadable(file) == 1) and vim.fn.fnamemodify(file, ":p:h") or vim.fn.getcwd()
	open_external_terminal(dir)
end, { desc = "External terminal here" })

map("n", "<leader>tE", function()
	open_external_terminal(vim.fn.getcwd())
end, { desc = "External terminal cwd" })

map("n", "<leader>ul", function()
	vim.opt.relativenumber = not vim.opt.relativenumber:get()
end, { desc = "Toggle relative line numbers" })

map("n", "<leader>uw", function()
	vim.opt.wrap = not vim.opt.wrap:get()
end, { desc = "Toggle wrap" })

map("n", "<leader>ut", function()
	require("user.core.theme").pick()
end, { desc = "Theme picker" })

map("n", "<leader>L", "<cmd>Lazy<cr>", { desc = "Lazy" })
map("n", "<leader>M", "<cmd>Mason<cr>", { desc = "Mason" })

local ai = require("user.core.ai")

map("n", "<leader>ap", ai.pick, { desc = "AI provider" })
map("n", "<leader>aa", ai.toggle, { desc = "AI chat" })
map("n", "<leader>af", ai.focus, { desc = "AI focus" })
map("n", "<leader>ab", ai.add_buffer, { desc = "AI add buffer" })
map("n", "<leader>as", ai.send_context, { desc = "AI send context" })
map("x", "<leader>as", ai.send_selection, { desc = "AI send selection" })
map("n", "<leader>at", ai.attach_file, { desc = "AI attach file" })
map("n", "<leader>ai", ai.interrupt, { desc = "AI interrupt" })
map("n", "<leader>ar", ai.resume, { desc = "AI resume" })
map("n", "<leader>ac", ai.continue, { desc = "AI continue" })
map("n", "<leader>am", ai.model, { desc = "AI model" })
map("n", "<leader>ay", ai.accept, { desc = "AI accept change" })
map("n", "<leader>an", ai.deny, { desc = "AI reject change" })
