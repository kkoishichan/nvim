return function(tmp)
	local saved = {
		ai = package.loaded["user.core.ai"],
		terminals = package.loaded["user.core.ai_terminal"],
		claude_terminal = package.loaded["claudecode.terminal"],
		lazy = package.loaded.lazy,
		notify = vim.notify,
		select = vim.ui.select,
		executable = vim.fn.executable,
		selection = vim.o.selection,
		provider = vim.g.user_ai_provider,
		chat_open = vim.g.user_ai_chat_open,
		chat_provider = vim.g.user_ai_chat_provider,
	}
	local claude_spec = require("lazy.core.config").plugins["claudecode.nvim"]
	local sent, interrupts, notices = {}, {}, {}
	local claude_visible = false
	local claude_buffer = vim.api.nvim_create_buf(false, true)
	local claude, selection, original_mention
	local function fresh_ai(provider)
		package.loaded["user.core.ai"] = nil
		vim.g.user_ai_provider = provider
		vim.g.user_ai_chat_open = false
		vim.g.user_ai_chat_provider = nil
		return require("user.core.ai")
	end
	local function normal(keys)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
		if keys ~= "" then
			vim.cmd.normal({ keys, bang = true })
		end
	end
	local ok, err = xpcall(function()
		vim.notify = function(message)
			table.insert(notices, message)
		end
		vim.fn.executable = function()
			return 1
		end
		package.loaded.lazy = { load = function() end }
		package.loaded["user.core.ai_terminal"] = {
			new = function()
				return {
					send = function(id, text)
						table.insert(sent, { id = id, text = text })
					end,
					visible = function()
						return false
					end,
					visible_buffer = function(bufnr)
						return bufnr == claude_buffer and claude_visible
					end,
					open = function()
						return {}
					end,
					close = function() end,
				}
			end,
		}
		package.loaded["claudecode.terminal"] = {
			get_active_terminal_bufnr = function()
				return claude_buffer
			end,
			send_to_terminal = function(text, opts)
				table.insert(interrupts, { text = text, opts = opts })
				return true
			end,
		}

		local bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(bufnr)
		vim.api.nvim_buf_set_name(bufnr, tmp .. "/ai-selection.txt")
		vim.api.nvim_buf_set_lines(
			bufnr,
			0,
			-1,
			false,
			{ "alpha beta", "gamma delta", "中文🙂 tail", "ABCDE", "abcde" }
		)
		vim.bo[bufnr].filetype = "text"
		vim.o.selection = "inclusive"
		local ai = fresh_ai("codex")
		vim.keymap.set("x", "<F12>", ai.send_selection, { buffer = bufnr })
		local function selected(keys, expected, first, last)
			normal(keys)
			local count = #sent
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F12>", true, false, true), "mx", false)
			assert(#sent == count + 1, "AI did not send the current Visual selection")
			local text = ("\27[200~Context from %s:%d-%d\n```text\n%s\n```\27[201~\r"):format(
				vim.api.nvim_buf_get_name(bufnr),
				first,
				last,
				expected
			)
			assert(sent[#sent].text == text, "AI selection differs: " .. vim.inspect(sent[#sent].text))
		end
		-- First selection has no '< / '> marks. The next one leaves stale marks.
		selected("gg0vll", "alp", 1, 1)
		selected("2G0vllll", "gamma", 2, 2)
		selected("2G04lv4h", "gamma", 2, 2)
		selected("gg0Vj", "alpha beta\ngamma delta", 1, 2)
		selected("4G0l\22jl", "BC\nbc", 4, 5)
		selected("5G02l\22kh", "BC\nbc", 4, 5)
		selected("3G0vll", "中文🙂", 3, 3)
		selected("3G02lvhh", "中文🙂", 3, 3)
		selected("gg06lvj4l", "beta\ngamma delta", 1, 2)
		vim.o.selection = "exclusive"
		selected("gg0vlll", "alp", 1, 1)
		vim.o.selection = "inclusive"
		normal("")
		local count = #sent
		ai.send_selection()
		assert(#sent == count, "AI sent a stale selection outside Visual mode")

		local stopped, closed = 0, 0
		vim.api.nvim_create_user_command("ClaudeCodeStop", function()
			stopped = stopped + 1
		end, { force = true })
		vim.api.nvim_create_user_command("ClaudeCodeClose", function()
			closed = closed + 1
			claude_visible = false
		end, { force = true })
		ai = fresh_ai("claude")
		ai.interrupt()
		assert(#interrupts == 1 and interrupts[1].text == "\27", "Claude interrupt did not send Escape")
		assert(
			interrupts[1].opts.submit == false and interrupts[1].opts.focus == false,
			"Claude interrupt submitted or focused"
		)
		assert(stopped == 0, "Claude interrupt stopped the IDE server")
		claude_visible = true
		vim.ui.select = function(_, _, callback)
			callback("codex")
		end
		ai.pick()
		assert(#interrupts == 2 and stopped == 0, "Switching providers stopped the Claude IDE server")
		assert(
			closed == 1 and vim.g.user_ai_provider == "codex",
			"Provider switch did not close Claude and select Codex"
		)
		package.loaded["claudecode.terminal"].send_to_terminal = function()
			return false
		end
		ai = fresh_ai("claude")
		ai.interrupt()
		assert(stopped == 0 and notices[#notices]:match("No running Claude"), "Missing Claude terminal was not handled")

		-- Exercise the pinned plugin's real Visual command and range extraction;
		-- only its final at-mention transport is stubbed. No server or CLI starts.
		vim.opt.rtp:append(claude_spec.dir)
		claude = require("claudecode")
		claude.setup({ auto_start = false, terminal = { provider = "native" } })
		selection = require("claudecode.selection")
		selection.state.tracking_enabled = true
		claude.state.server = {}
		original_mention = claude.send_at_mention
		local mentions = {}
		claude.send_at_mention = function(path, first, last)
			table.insert(mentions, { path = path, first = first, last = last })
			return true
		end
		local claude_selection_buffer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(claude_selection_buffer)
		vim.api.nvim_buf_set_name(claude_selection_buffer, tmp .. "/claude-selection.txt")
		vim.api.nvim_buf_set_lines(
			claude_selection_buffer,
			0,
			-1,
			false,
			{ "alpha beta", "gamma delta", "中文🙂 tail" }
		)
		vim.keymap.set("x", "<F12>", ai.send_selection, { buffer = claude_selection_buffer })
		assert(vim.fn.line("'<") == 0 and vim.fn.line("'>") == 0, "Claude first-selection fixture has stale marks")
		normal("2G0vllll")
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F12>", true, false, true), "mx", false)
		assert(
			vim.wait(500, function()
				return #mentions > 0
			end),
			"Claude did not send a current selection through its real command"
		)
		assert(mentions[1].first == 1 and mentions[1].last == 1, "Claude sent the previous selection's line range")
		assert(
			mentions[1].path == vim.api.nvim_buf_get_name(claude_selection_buffer),
			"Claude selection referred to the wrong file"
		)
		normal("3G0vll")
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F12>", true, false, true), "mx", false)
		assert(
			vim.wait(500, function()
				return #mentions == 2
			end),
			"Claude did not send the next selection"
		)
		assert(mentions[2].first == 2 and mentions[2].last == 2, "Claude reused the first selection's line range")
	end, debug.traceback)
	if claude then
		claude.state.server = nil
		claude.send_at_mention = original_mention or claude.send_at_mention
	end
	if selection then
		selection.state.tracking_enabled = false
	end
	package.loaded["user.core.ai"] = saved.ai
	package.loaded["user.core.ai_terminal"] = saved.terminals
	package.loaded["claudecode.terminal"] = saved.claude_terminal
	package.loaded.lazy = saved.lazy
	vim.notify = saved.notify
	vim.ui.select = saved.select
	vim.fn.executable = saved.executable
	vim.o.selection = saved.selection
	vim.g.user_ai_provider = saved.provider
	vim.g.user_ai_chat_open = saved.chat_open
	vim.g.user_ai_chat_provider = saved.chat_provider
	assert(ok, err)
end
