local M = {}

local providers = {
	codex = {
		label = "Codex",
		plugin = "codex.nvim",
		executable = "codex",
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
		terminal = "opencode --port",
		count = 202,
	},
}

local order = { "codex", "claude", "opencode" }
local current = vim.g.user_ai_provider or "codex"
local chat_open = vim.g.user_ai_chat_open == true
local chat_provider = vim.g.user_ai_chat_provider
local cli_terms = {}

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
		current = "codex"
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

local function codex_slash(command)
	load(providers.codex.plugin)
	local ok, codex = pcall(require, "codex")
	if ok and type(codex.execute_slash_command) == "function" then
		local sent, err = codex.execute_slash_command({ command = command })
		if not sent and err then
			notify(("Codex /%s failed: %s"):format(command, err), vim.log.levels.WARN)
		end
		return
	end
	unsupported("/" .. command)
end

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

local function cli_command(id)
	local p = providers[id]
	if not p or not p.command then
		return nil
	end
	return p.terminal or p.command
end

local function cli_width()
	return math.max(24, math.floor((vim.o.columns or 80) * 0.40))
end

local function terminal_buf(term)
	return term and (term.bufnr or term.buf)
end

local function terminal_win(term)
	return term and (term.window or term.win)
end

local function terminal_buf_valid(term)
	local bufnr = terminal_buf(term)
	if type(bufnr) ~= "number" then
		return false
	end
	return vim.api.nvim_buf_is_valid(bufnr)
end

local function terminal_visible(term)
	if not terminal_buf_valid(term) then
		return false
	end
	if type(term.is_open) == "function" then
		local ok, valid = pcall(term.is_open, term)
		if ok then
			return valid == true
		end
	end
	local winid = terminal_win(term)
	return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function visible_buffer(bufnr)
	if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
			return true
		end
	end
	return false
end

local function buffer_var(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	if ok then
		return value
	end
	return nil
end

local function pattern_escape(value)
	return (value:gsub("([^%w])", "%%%1"))
end

local function command_matches(full_cmd, cmd)
	if type(full_cmd) ~= "string" or type(cmd) ~= "string" or cmd == "" then
		return false
	end
	local escaped = pattern_escape(cmd)
	return full_cmd == cmd or full_cmd:match("^" .. escaped .. "%s") ~= nil
end

local function terminal_command(bufnr)
	local ai = buffer_var(bufnr, "user_ai_terminal")
	if type(ai) == "table" and type(ai.command) == "string" then
		return ai.command
	end

	local marker = buffer_var(bufnr, "codex_terminal")
	if type(marker) == "table" and type(marker.cmd) == "string" then
		return marker.cmd
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if type(name) == "string" then
		return name:match("^term://.-//%d+:(.+)$")
	end
	return nil
end

local function visible_command(cmd)
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(winid) then
			local bufnr = vim.api.nvim_win_get_buf(winid)
			if command_matches(terminal_command(bufnr), cmd) then
				return true
			end
		end
	end
	return false
end

local function cli_term(id)
	local term = cli_terms[id]
	if terminal_buf_valid(term) then
		return term
	end

	local p = providers[id]
	if not p or not p.count then
		return nil
	end

	load("toggleterm.nvim")
	local ok, terminal_mod = pcall(require, "toggleterm.terminal")
	if not ok then
		return nil
	end

	if type(terminal_mod.get) == "function" then
		term = terminal_mod.get(p.count, true)
		if terminal_buf_valid(term) then
			cli_terms[id] = term
			return term
		end
	end

	return nil
end

local function cli_visible(id)
	local p = providers[id]
	return terminal_visible(cli_term(id)) or (p and visible_command(p.command))
end

local function cli_terminal(id, focus)
	local p = providers[id]
	if not p or not p.command then
		return nil
	end
	if p.plugin then
		load(p.plugin)
	end
	if vim.fn.executable(p.command) == 0 then
		notify(p.command .. " is not executable", vim.log.levels.ERROR)
		return nil
	end

	load("toggleterm.nvim")
	local ok, terminal_mod = pcall(require, "toggleterm.terminal")
	if not ok or not terminal_mod.Terminal then
		notify("toggleterm.nvim is not available", vim.log.levels.ERROR)
		return nil
	end

	local term = cli_term(id)
	if term then
		local ok_open = pcall(function()
			if focus then
				if not terminal_visible(term) then
					term:open(cli_width(), "vertical")
				end
				term:focus()
				vim.cmd.startinsert()
			else
				term:toggle(cli_width(), "vertical")
			end
		end)
		if not ok_open then
			notify("Could not open " .. p.label .. " terminal", vim.log.levels.ERROR)
			return nil
		end
		return term
	end

	term = terminal_mod.Terminal:new({
		cmd = cli_command(id),
		count = p.count,
		direction = "vertical",
		display_name = p.label,
		hidden = true,
		close_on_exit = false,
		on_create = function(t)
			if t.bufnr and vim.api.nvim_buf_is_valid(t.bufnr) then
				vim.api.nvim_buf_set_var(t.bufnr, "user_ai_terminal", {
					provider = id,
					command = cli_command(id),
					label = p.label,
				})
			end
		end,
	})
	cli_terms[id] = term
	local ok_open = pcall(function()
		if focus then
			term:open(cli_width(), "vertical")
			term:focus()
			vim.cmd.startinsert()
		else
			term:toggle(cli_width(), "vertical")
		end
	end)
	if not ok_open then
		cli_terms[id] = nil
		notify("Could not open " .. p.label .. " terminal", vim.log.levels.ERROR)
		return nil
	end
	return term
end

local function provider_chat_visible(id)
	if id == "codex" then
		return visible_command("codex")
	elseif id == "claude" and package.loaded["claudecode.terminal"] then
		local ok, terminal = pcall(require, "claudecode.terminal")
		if not ok then
			return false
		end
		if type(terminal.get_active_terminal_bufnr) == "function" then
			return visible_buffer(terminal.get_active_terminal_bufnr())
		end
	elseif is_cli(id) then
		return cli_visible(id)
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
	if id == "codex" then
		load(providers.codex.plugin)
		return pcall(vim.cmd, "CodexClose")
	elseif id == "claude" then
		load(providers.claude.plugin)
		return pcall(vim.cmd, "ClaudeCodeClose")
	elseif is_cli(id) then
		local term = cli_term(id)
		if term and type(term.close) == "function" and terminal_visible(term) then
			return pcall(term.close, term)
		end
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

	if id == "codex" then
		load(providers.codex.plugin)
		ok = pcall(vim.cmd, focus and "CodexFocus" or "Codex")
	elseif id == "claude" then
		load(providers.claude.plugin)
		ok = pcall(vim.cmd, focus and "ClaudeCodeFocus" or "ClaudeCode")
	elseif is_cli(id) then
		ok = cli_terminal(id, focus) ~= nil
	end
	if ok then
		set_chat_state(true, id)
	end
	return ok
end

local function terminal_channel(term)
	local bufnr = terminal_buf(term)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	if type(term.job_id) == "number" and term.job_id > 0 then
		return term.job_id
	end

	local ok_var, chan = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
	if ok_var and type(chan) == "number" and chan > 0 then
		return chan
	end

	local ok_opt, opt = pcall(vim.api.nvim_get_option_value, "channel", { buf = bufnr })
	if ok_opt and type(opt) == "number" and opt > 0 then
		return opt
	end

	return nil
end

local function cli_send(id, text)
	local term = cli_terminal(id, true)
	if not term then
		return
	end

	local function attempt(remaining)
		local chan = terminal_channel(term)
		if chan then
			vim.api.nvim_chan_send(chan, text)
			return
		end
		if remaining <= 0 then
			notify("Could not send to " .. providers[id].label .. ": terminal is not ready", vim.log.levels.WARN)
			return
		end
		vim.defer_fn(function()
			attempt(remaining - 1)
		end, 60)
	end

	vim.defer_fn(function()
		attempt(12)
	end, 80)
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
	cli_send(id, paste_submit("Use this file as context: " .. path))
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
	cli_send(id, paste_submit(text))
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
		cli_send(id, paste_submit("Use this file as context: " .. vim.fn.fnamemodify(path, ":p")))
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
			if not open_chat(id, true) then
				current = previous
				vim.g.user_ai_provider = previous
				set_chat_state(true, open_provider)
				notify(("Could not switch to %s"):format(providers[id].label), vim.log.levels.ERROR)
				return
			end
			close_chat(open_provider)
		end

		current = id
		vim.g.user_ai_provider = id
		notify("Current AI: " .. providers[id].label)
		if open_provider then
			set_chat_state(true, id)
		end
	end)
end

function M.toggle()
	local id = provider()
	local was_open = route_chat_visible(id)
	local ok = true
	if id == "codex" then
		ok = pcall(vim.cmd, "Codex")
	elseif id == "claude" then
		ok = pcall(vim.cmd, "ClaudeCode")
	elseif is_cli(id) then
		ok = cli_terminal(id, false) ~= nil
	end
	if ok then
		set_chat_state(not was_open, id)
	end
end

function M.focus()
	local id = provider()
	open_chat(id, true)
end

function M.open_cli(id, focus)
	if not is_cli(id) then
		return nil
	end
	return cli_terminal(id, focus ~= false)
end

function M.add_buffer()
	local id = provider()
	if id == "codex" then
		vim.cmd("CodexSendFile")
		return
	end
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
	if id == "codex" then
		vim.cmd("'<,'>CodexSendSelection")
	elseif id == "claude" then
		vim.cmd("'<,'>ClaudeCodeSend")
	elseif id == "opencode" then
		opencode_prompt("@this ")
	elseif is_cli(id) then
		cli_send_selection(id)
	end
end

function M.attach_file()
	local id = provider()
	if id == "codex" then
		vim.cmd("CodexMentionFile")
	elseif id == "claude" and tree_filetypes[vim.bo.filetype] then
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
	if id == "codex" then
		vim.cmd("CodexClearInput")
	elseif id == "claude" then
		vim.cmd("ClaudeCodeStop")
	elseif id == "opencode" then
		opencode_command("session.interrupt")
	elseif is_cli(id) then
		cli_send(id, "\003")
	end
end

function M.resume()
	local id = provider()
	if id == "codex" then
		vim.cmd("CodexResume")
	elseif id == "claude" then
		vim.cmd("ClaudeCode --resume")
	elseif id == "opencode" then
		opencode_command("session.select")
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
	if id == "codex" then
		codex_slash("model")
	elseif id == "claude" then
		vim.cmd("ClaudeCodeSelectModel")
	elseif id == "opencode" then
		local opencode = opencode_api()
		if opencode then
			opencode.select()
		end
	elseif is_cli(id) then
		cli_send(id, "/model\r")
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
