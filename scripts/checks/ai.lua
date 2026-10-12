return function(tmp)
	local saved = {
		ai = package.loaded["user.core.ai"],
		terminals = package.loaded["user.core.ai_terminal"],
		claude_terminal = package.loaded["claudecode.terminal"],
		lazy = package.loaded.lazy,
		notify = vim.notify,
		select = vim.ui.select,
		executable = vim.fn.executable,
		chan_send = vim.api.nvim_chan_send,
		selection = vim.o.selection,
		provider = vim.g.user_ai_provider,
		chat_open = vim.g.user_ai_chat_open,
		chat_provider = vim.g.user_ai_chat_provider,
	}
	local claude_spec = require("lazy.core.config").plugins["claudecode.nvim"]
	assert(not require("lazy.core.config").plugins["opencode.nvim"], "Removed AI provider is still registered")
	local sent, interrupts, notices, cli_interrupts = {}, {}, {}, {}
	local cli_visible = {}
	local channels = { codex = 301, pi = 302 }
	local state_file = vim.fn.stdpath("state") .. "/ai-provider.txt"
	local previous = vim.fn.filereadable(state_file) == 1 and vim.fn.readfile(state_file) or nil
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
		vim.api.nvim_chan_send = function(channel, text)
			table.insert(cli_interrupts, { channel = channel, text = text })
		end
		package.loaded.lazy = { load = function() end }
		package.loaded["user.core.ai_terminal"] = {
			new = function()
				return {
					send = function(id, text)
						table.insert(sent, { id = id, text = text })
					end,
					channel = function(id)
						return channels[id]
					end,
					visible = function(id)
						return cli_visible[id] == true
					end,
					visible_buffer = function(bufnr)
						return bufnr == claude_buffer and claude_visible
					end,
					open = function(id)
						cli_visible = { [id] = true }
						return {}
					end,
					close = function(id)
						cli_visible[id] = false
					end,
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

		-- Retired persisted/session selections fall back without exposing a
		-- provider that no longer has a plugin or terminal implementation.
		vim.ui.select = function(items, opts, callback)
			assert(vim.deep_equal(items, { "claude", "codex", "pi" }), "AI picker exposes an unsupported provider")
			assert(opts.format_item("claude"):sub(1, 2) == "* ", "Retired AI selection did not fall back to Claude")
			callback(nil)
		end
		fresh_ai("opencode").pick()
		assert(vim.g.user_ai_provider == "claude", "Retired session provider was not normalized")
		vim.fn.mkdir(vim.fs.dirname(state_file), "p")
		vim.fn.writefile({ "opencode" }, state_file)
		fresh_ai(nil).pick()
		assert(vim.g.user_ai_provider == "claude", "Retired saved provider was not ignored")
		vim.ui.select = saved.select

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

		ai = fresh_ai("pi")
		vim.keymap.set("x", "<F12>", ai.send_selection, { buffer = bufnr })
		selected("3G0vll", "中文🙂", 3, 3)
		assert(sent[#sent].id == "pi", "Pi selection was routed to another provider")
		normal("")
		ai.add_buffer()
		assert(
			sent[#sent].id == "pi"
				and sent[#sent].text
					== "\27[200~Use this file as context: " .. vim.api.nvim_buf_get_name(bufnr) .. "\27[201~\r",
			"Pi did not receive a pasted file reference"
		)
		ai.resume()
		assert(sent[#sent].id == "pi" and sent[#sent].text == "/resume\r", "Pi resume used an unsupported command")
		ai.model()
		assert(sent[#sent].id == "pi" and sent[#sent].text == "/model\r", "Pi model picker was not opened")
		ai.interrupt()
		assert(
			cli_interrupts[#cli_interrupts].channel == channels.pi and cli_interrupts[#cli_interrupts].text == "\27",
			"Pi interrupt must send Escape, not clear its editor or exit"
		)
		fresh_ai("codex").interrupt()
		assert(
			cli_interrupts[#cli_interrupts].channel == channels.codex and cli_interrupts[#cli_interrupts].text == "\003",
			"Pi integration changed Codex interruption"
		)
		vim.ui.select = function(_, _, callback)
			callback("pi")
		end
		fresh_ai("claude").pick()
		assert(vim.fn.readfile(state_file)[1] == "pi", "Pi selection was not persisted")
		vim.ui.select = function(_, opts, callback)
			assert(opts.format_item("pi"):sub(1, 2) == "* ", "Saved Pi selection was not restored")
			callback(nil)
		end
		ai = fresh_ai(nil)
		ai.pick()
		ai.focus()
		assert(cli_visible.pi, "Pi did not open through the terminal manager")
		vim.ui.select = function(_, _, callback)
			callback("codex")
		end
		count = #cli_interrupts
		ai.pick()
		assert(
			#cli_interrupts == count + 1
				and cli_interrupts[#cli_interrupts].channel == channels.pi
				and cli_interrupts[#cli_interrupts].text == "\27",
			"Switching away from Pi did not interrupt it with Escape"
		)
		assert(not cli_visible.pi and cli_visible.codex, "Switching from Pi left the wrong panel visible")
		cli_visible = {}
		vim.fn.executable = function(command)
			return command == "pi" and 0 or 1
		end
		fresh_ai("pi").focus()
		assert(
			not cli_visible.pi and notices[#notices]:match("pi is not executable"),
			"Missing Pi CLI was not reported"
		)
		vim.fn.executable = function()
			return 1
		end

		local stopped, closed = 0, 0
		vim.api.nvim_create_user_command("ClaudeCodeStop", function()
			stopped = stopped + 1
		end, { force = true })
		vim.api.nvim_create_user_command("ClaudeCodeClose", function()
			closed = closed + 1
			claude_visible = false
		end, { force = true })
		vim.b[claude_buffer].user_project_root = require("user.core.project").root()
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
	vim.api.nvim_chan_send = saved.chan_send
	vim.o.selection = saved.selection
	vim.g.user_ai_provider = saved.provider
	vim.g.user_ai_chat_open = saved.chat_open
	vim.g.user_ai_chat_provider = saved.chat_provider
	if previous then
		vim.fn.writefile(previous, state_file)
	else
		vim.fn.delete(state_file)
	end
	assert(ok, err)
end
