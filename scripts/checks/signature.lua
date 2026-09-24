return function(tmp)
	require("lazy").load({ plugins = { "blink.cmp" } })
	local cmp = require("blink.cmp")
	local api = vim.api
	-- Blink installs its event listeners after checking the fuzzy binary.
	assert(
		vim.wait(2000, function()
			return package.loaded["blink.cmp.signature"] ~= nil
		end),
		"Blink signature setup did not finish"
	)
	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(buf, tmp .. "/signature.fixture")
	api.nvim_set_current_buf(buf)
	-- Exercise the real LSP -> Blink path with deterministic responses. No
	-- external server, Blink internals or custom renderer is needed by this check.
	local response
	local requests = 0
	local client_id = assert(vim.lsp.start({
		name = "signature_fixture",
		root_dir = tmp,
		cmd = function(dispatchers)
			local closing = false
			local id = 0
			local function close()
				if not closing then
					closing = true
					vim.schedule(function()
						dispatchers.on_exit(0, 0)
					end)
				end
			end
			return {
				request = function(method, _, callback)
					id = id + 1
					local result = vim.NIL
					if method == "initialize" then
						result = {
							capabilities = {
								textDocumentSync = 1,
								signatureHelpProvider = { triggerCharacters = { "(", "," } },
							},
						}
					elseif method == "textDocument/signatureHelp" then
						requests = requests + 1
						result = vim.deepcopy(response)
					end
					vim.schedule(function()
						callback(nil, result)
					end)
					return true, id
				end,
				notify = function(method)
					if method == "exit" then
						close()
					end
					return true
				end,
				is_closing = function()
					return closing
				end,
				terminate = close,
			}
		end,
	}, { bufnr = buf }))
	local client = assert(vim.lsp.get_client_by_id(client_id))
	assert(
		vim.wait(2000, function()
			return client.initialized and vim.lsp.buf_is_attached(buf, client_id)
		end),
		"Signature fixture did not attach"
	)

	local function popup()
		for _, win in ipairs(api.nvim_list_wins()) do
			if vim.bo[api.nvim_win_get_buf(win)].filetype == "blink-cmp-signature" then
				return win
			end
		end
	end
	local function hide()
		assert(cmp.hide_signature(), "Public signature hide failed")
		assert(
			vim.wait(1000, function()
				return not cmp.is_signature_visible()
			end),
			"Signature popup stayed open"
		)
	end
	local function show(help, line, filetype, automatic)
		response = help
		local lines = {}
		for _ = 1, 12 do
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = line
		api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		-- Avoid starting unrelated real language servers for these fixtures.
		vim.cmd("noautocmd setlocal filetype=" .. filetype)
		api.nvim_win_set_cursor(0, { #lines, #line - 1 })
		vim.cmd.redraw()
		local cursor = api.nvim_win_get_cursor(0)
		local leftcol = vim.fn.winsaveview().leftcol
		if automatic then
			api.nvim_exec_autocmds("InsertEnter", { buffer = buf, modeline = false })
		else
			assert(cmp.show_signature(), "Public signature show failed")
		end
		assert(
			vim.wait(1000, cmp.is_signature_visible),
			"LSP response did not open a signature popup: " .. vim.v.errmsg
		)
		assert(vim.deep_equal(cursor, api.nvim_win_get_cursor(0)), "Signature moved the editing cursor")
		assert(vim.fn.winsaveview().leftcol == leftcol, "Signature scrolled the editing window horizontally")
		return assert(popup())
	end
	local function highlighted_parameter(win)
		local popup_buf = api.nvim_win_get_buf(win)
		for _, mark in ipairs(api.nvim_buf_get_extmarks(popup_buf, -1, 0, -1, { details = true })) do
			local details = mark[4]
			if details.hl_group == "BlinkCmpSignatureHelpActiveParameter" then
				return table.concat(
					api.nvim_buf_get_text(popup_buf, mark[2], mark[3], details.end_row, details.end_col, {}),
					"\n"
				)
			end
		end
	end

	-- Trust the server's keyword-argument index, including Unicode labels.
	local win = show({
		activeParameter = 0,
		signatures = {
			{
				label = "调用(值: str, 次数: int)",
				parameters = { { label = "值: str" }, { label = "次数: int" } },
			},
		},
	}, "调用(次数=2, 值='文字')", "python", true)
	assert(highlighted_parameter(win) == "值: str", "Server-selected keyword parameter was not highlighted")
	hide()

	-- Blink 1.10.2 has an upstream non-first-overload highlight bug (README).
	-- Keep the ordinary server-selected-first case; do not patch its renderer.
	win = show({
		activeSignature = 0,
		activeParameter = 1,
		signatures = {
			{
				label = "int pick(int first, int second)",
				parameters = { { label = "int first" }, { label = "int second" } },
			},
			{ label = "int pick(int first)", parameters = { { label = "int first" } } },
		},
	}, "pick(1, 2)", "cpp")
	assert(highlighted_parameter(win) == "int second", "LSP-selected overload lost its active parameter")
	assert(api.nvim_buf_line_count(api.nvim_win_get_buf(win)) >= 2, "Alternative overload was discarded")
	hide()

	local parameters = {}
	for index = 1, 16 do
		parameters[index] = "    parameter_" .. index .. ": int,"
	end
	win = show(
		{ signatures = { { label = "long_call(\n" .. table.concat(parameters, "\n") .. "\n)" } } },
		"long_call()",
		"python"
	)
	assert(
		api.nvim_win_get_height(win) > 1 and api.nvim_win_get_height(win) <= 6,
		"Multiline signature height is wrong"
	)
	local initial_row = api.nvim_win_get_cursor(win)[1]
	assert(cmp.scroll_signature_down(), "Public signature scroll failed")
	assert(
		vim.wait(1000, function()
			return api.nvim_win_get_cursor(win)[1] > initial_row
		end),
		"Long signature did not scroll"
	)
	assert(cmp.scroll_signature_up(), "Public signature reverse scroll failed")
	hide()
	assert(requests == 3, "Manual signature checks made duplicate requests")
	client:stop(true)
	api.nvim_buf_delete(buf, { force = true })
end
