local M = {}

local providers = {
	codex = {
		label = "Codex",
		command = "codex",
		terminal = "codex",
		count = 201,
	},
	claude = {
		label = "Claude Code",
		plugin = "claudecode.nvim",
		executable = "claude",
	},
	opencode = {
		label = "OpenCode",
		plugin = "opencode.nvim",
		command = "opencode",
		-- --port 0 (the CLI default) = listen on a random port so opencode.nvim
		-- can attach; explicit because a bare "--port" is ambiguous.
		terminal = "opencode --port 0",
		count = 202,
	},
}

local order = { "claude", "codex", "opencode" }

-- Persist the picked provider across restarts (same pattern as core/theme.lua:
-- a one-line state file). vim.g still wins within a running session.
local state_file = vim.fn.stdpath("state") .. "/ai-provider.txt"

local function saved_provider()
	local ok, lines = pcall(vim.fn.readfile, state_file)
	local name = ok and lines and lines[1]
	if name and providers[name] then
		return name
	end
	return nil
end

local function save_provider(name)
	pcall(vim.fn.mkdir, vim.fn.fnamemodify(state_file, ":h"), "p")
	pcall(vim.fn.writefile, { name }, state_file)
end

local current = vim.g.user_ai_provider or saved_provider() or "claude"
local chat_open = vim.g.user_ai_chat_open == true
local chat_provider = vim.g.user_ai_chat_provider

local tree_filetypes = {
	NvimTree = true,
	["neo-tree"] = true,
	oil = true,
	minifiles = true,
	netrw = true,
	snacks_picker_list = true,
}

local function provider()
	if not providers[current] then
		current = "claude"
	end
	vim.g.user_ai_provider = current
	return current, providers[current]
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "AI" })
end

local function unsupported(action)
	local _, p = provider()
	notify(("%s does not support %s"):format(p.label, action), vim.log.levels.WARN)
end

local function load(plugin)
	local ok, lazy = pcall(require, "lazy")
	if ok then
		pcall(lazy.load, { plugins = { plugin } })
	end
end

local terminals = require("user.core.ai_terminal").new({
	providers = providers,
	notify = notify,
	load = load,
})

local function opencode_api()
	load(providers.opencode.plugin)
	local ok, opencode = pcall(require, "opencode")
	if ok then
		return opencode
	end
	notify("opencode.nvim is not available", vim.log.levels.ERROR)
	return nil
end

local function opencode_prompt(prompt)
	local opencode = opencode_api()
	if opencode then
		opencode.prompt(prompt)
	end
end

local function opencode_command(command)
	local opencode = opencode_api()
	if opencode then
		opencode.command(command)
	end
end

local function is_cli(id)
	return providers[id] and providers[id].command ~= nil
end

local function set_chat_state(open, id)
	chat_open = open
	chat_provider = open and (id or current) or nil
	vim.g.user_ai_chat_open = open
	vim.g.user_ai_chat_provider = chat_provider
end

-- Best-effort interrupt of a provider's in-flight generation, so switching away
-- does not leave the previous agent working in the background.
local function stop_generation(id)
	if id == "claude" then
		pcall(vim.cmd, "ClaudeCodeStop")
	elseif id == "opencode" then
		opencode_command("session.interrupt")
	elseif id == "codex" then
		local chan = terminals.channel(id)
		if chan then
			pcall(vim.api.nvim_chan_send, chan, "\003")
		end
	end
end

local function provider_chat_visible(id)
	if id == "claude" and package.loaded["claudecode.terminal"] then
		local ok, terminal = pcall(require, "claudecode.terminal")
		if not ok then
			return false
		end
		if type(terminal.get_active_terminal_bufnr) == "function" then
			return terminals.visible_buffer(terminal.get_active_terminal_bufnr())
		end
	elseif is_cli(id) then
		return terminals.visible(id)
	end

	return false
end

local function route_chat_visible(id)
	if provider_chat_visible(id) then
		set_chat_state(true, id)
		return true
	end
	if chat_open and (not chat_provider or chat_provider == id) then
		set_chat_state(false)
	end
	return false
end

local function active_chat_provider()
	if chat_provider and providers[chat_provider] and route_chat_visible(chat_provider) then
		return chat_provider
	end

	local id = provider()
	if route_chat_visible(id) then
		return id
	end

	for _, candidate in ipairs(order) do
		if candidate ~= id and route_chat_visible(candidate) then
			return candidate
		end
	end
	return nil
end

local function close_chat(id)
	if id == "claude" then
		load(providers.claude.plugin)
		return pcall(vim.cmd, "ClaudeCodeClose")
	elseif is_cli(id) then
		return terminals.close(id)
	end
	return false
end

local function open_chat(id, focus)
	local ok = false
	local p = providers[id]
	local executable = p and (p.executable or p.command)
	if executable and vim.fn.executable(executable) == 0 then
		notify(executable .. " is not executable", vim.log.levels.ERROR)
		return false
	end

	if id == "claude" then
		load(providers.claude.plugin)
		ok = pcall(vim.cmd, focus and "ClaudeCodeFocus" or "ClaudeCode")
	elseif is_cli(id) then
		ok = terminals.open(id, focus) ~= nil
	end
	if ok then
		set_chat_state(true, id)
	end
	return ok
end

local function paste_submit(text)
	return "\27[200~" .. text .. "\27[201~\r"
end

local function current_file()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		notify("Current buffer has no file path", vim.log.levels.WARN)
		return nil
	end
	return path
end

local function send_file_reference(id)
	local path = current_file()
	if not path then
		return
	end
	terminals.send(id, paste_submit("Use this file as context: " .. path))
end

local function visual_selection_text()
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	if start_line <= 0 or end_line <= 0 then
		return nil
	end
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	if #lines == 0 then
		return nil
	end

	local path = vim.api.nvim_buf_get_name(0)
	local ft = vim.bo.filetype
	local header = ("Context from %s:%d-%d"):format(path ~= "" and path or "[No Name]", start_line, end_line)
	return table.concat({
		header,
		"```" .. (ft ~= "" and ft or "text"),
		table.concat(lines, "\n"),
		"```",
	}, "\n")
end

local function cli_send_selection(id)
	local text = visual_selection_text()
	if not text then
		notify("No visual selection to send", vim.log.levels.WARN)
		return
	end
	terminals.send(id, paste_submit(text))
end

local function cli_mention_file(id)
	vim.ui.input({
		prompt = "File for " .. providers[id].label .. ": ",
		default = vim.api.nvim_buf_get_name(0),
		completion = "file",
	}, function(path)
		if not path or path == "" then
			return
		end
		terminals.send(id, paste_submit("Use this file as context: " .. vim.fn.fnamemodify(path, ":p")))
	end)
end

local function opencode_mention_file()
	vim.ui.input({
		prompt = "File for OpenCode: ",
		default = vim.api.nvim_buf_get_name(0),
		completion = "file",
	}, function(path)
		if not path or path == "" then
			return
		end

		local opencode = opencode_api()
		if opencode then
			opencode.prompt(opencode.format({ path = vim.fn.fnamemodify(path, ":p") }) .. " ")
		end
	end)
end

local function feed_buffer_keymap(lhs)
	local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
	vim.api.nvim_feedkeys(keys, "m", false)
end

local function has_buffer_keymap(lhs)
	for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
		if keymap.lhs == lhs then
			return true
		end
	end
	return false
end

function M.pick()
	local active = provider()
	local open_provider = active_chat_provider()
	vim.ui.select(order, {
		prompt = "Select AI",
		format_item = function(id)
			local marker = id == active and "* " or "  "
			return marker .. providers[id].label
		end,
	}, function(id)
		if not id then
			return
		end

		if open_provider and id ~= open_provider then
			local previous = current
			-- Stop the outgoing agent's in-flight work, then close its panel
			-- before opening the new one so only one panel exists at a time.
			stop_generation(open_provider)
			close_chat(open_provider)
			if provider_chat_visible(open_provider) then
				notify(("Could not close %s panel"):format(providers[open_provider].label), vim.log.levels.WARN)
			end
			set_chat_state(false)
			if not open_chat(id, true) then
				-- Reopen the previous agent so a failed switch is atomic.
				current = previous
				vim.g.user_ai_provider = previous
				open_chat(open_provider, true)
				notify(("Could not switch to %s"):format(providers[id].label), vim.log.levels.ERROR)
				return
			end
		end

		current = id
		vim.g.user_ai_provider = id
		save_provider(id)
		notify("Current AI: " .. providers[id].label)
		if open_provider then
			set_chat_state(true, id)
		end
	end)
end

function M.toggle()
	-- Close whichever panel is actually visible (even if it is not `current`)
	-- rather than blindly toggling `current` and stacking a second panel.
	local visible = active_chat_provider()
	if visible then
		close_chat(visible)
		if not provider_chat_visible(visible) then
			set_chat_state(false)
		end
		return
	end
	open_chat(provider(), false)
end

function M.focus()
	local id = provider()
	open_chat(id, true)
end

function M.open_cli(id, focus)
	if not is_cli(id) then
		return nil
	end
	return terminals.open(id, focus ~= false)
end

function M.add_buffer()
	local id = provider()
	if id == "opencode" then
		opencode_prompt("@buffer ")
		return
	end
	if is_cli(id) then
		send_file_reference(id)
		return
	end

	local path = current_file()
	if not path then
		return
	end
	vim.cmd("ClaudeCodeAdd " .. vim.fn.fnameescape(path))
end

function M.send_context()
	local id = provider()
	if tree_filetypes[vim.bo.filetype] then
		if id == "claude" then
			vim.cmd("ClaudeCodeSend")
		else
			unsupported("tree selection")
		end
		return
	end

	M.add_buffer()
end

function M.send_selection()
	local id = provider()
	if id == "claude" then
		vim.cmd("'<,'>ClaudeCodeSend")
	elseif id == "opencode" then
		opencode_prompt("@this ")
	elseif is_cli(id) then
		cli_send_selection(id)
	end
end

function M.attach_file()
	local id = provider()
	if id == "claude" and tree_filetypes[vim.bo.filetype] then
		vim.cmd("ClaudeCodeTreeAdd")
	elseif id == "opencode" then
		opencode_mention_file()
	elseif is_cli(id) then
		cli_mention_file(id)
	else
		unsupported("file picker")
	end
end

function M.interrupt()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCodeStop")
	elseif id == "opencode" then
		opencode_command("session.interrupt")
	elseif is_cli(id) then
		local channel = terminals.channel(id)
		if channel then
			vim.api.nvim_chan_send(channel, "\003")
		end
	end
end

function M.resume()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCode --resume")
	elseif id == "opencode" then
		opencode_command("session.select")
	elseif is_cli(id) then
		terminals.send(id, "/resume\r")
	end
end

function M.continue()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCode --continue")
	else
		unsupported("continue")
	end
end

function M.model()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCodeSelectModel")
	elseif id == "opencode" then
		local opencode = opencode_api()
		if opencode then
			opencode.select()
		end
	elseif is_cli(id) then
		terminals.send(id, "/model\r")
	end
end

function M.accept()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCodeDiffAccept")
	elseif id == "opencode" and has_buffer_keymap("da") then
		feed_buffer_keymap("da")
	else
		notify("Approve changes in the " .. providers[id].label .. " terminal", vim.log.levels.INFO)
	end
end

function M.deny()
	local id = provider()
	if id == "claude" then
		vim.cmd("ClaudeCodeDiffDeny")
	elseif id == "opencode" and has_buffer_keymap("dr") then
		feed_buffer_keymap("dr")
	else
		notify("Reject changes in the " .. providers[id].label .. " terminal", vim.log.levels.INFO)
	end
end

return M
