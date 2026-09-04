local M = {}

function M.command(argv, cwd, expected, env, timeout)
	print("Native workflow: " .. table.concat(argv, " "))
	local result = vim.system(argv, { cwd = cwd, env = env, text = true }):wait(timeout or 120000)
	local output = (result.stdout or "") .. (result.stderr or "")
	if expected == "failure" then
		assert(result.code ~= 0 and result.code ~= 124, "Expected command failure: " .. table.concat(argv, " "))
	else
		assert(result.code == 0, "Command failed: " .. table.concat(argv, " ") .. "\n" .. output)
	end
	return output
end

function M.marker(path, text)
	for row, line in ipairs(vim.fn.readfile(path)) do
		local col = line:find(text, 1, true)
		if col then
			return row, col
		end
	end
	error("Missing fixture marker " .. text .. " in " .. path)
end

function M.edit(path, root)
	require("user.core.project").set(root)
	vim.cmd.edit({ args = { path } })
	return vim.api.nvim_get_current_buf()
end

function M.language(path, root, server_name, symbol, definition_marker, broken_line)
	print("Native workflow: " .. server_name .. " definition and live diagnostic")
	local bufnr = M.edit(path, root)
	local client
	assert(
		vim.wait(90000, function()
			for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				if candidate.name == server_name and candidate.initialized then
					client = candidate
					return true
				end
			end
		end, 50),
		"Language server did not attach: " .. server_name
	)
	local row = M.marker(path, "DEFINITION")
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
	local col = assert(line:find(symbol, 1, true), "Definition call has no symbol")
	local response, location
	-- Rust Analyzer initializes before loading the Cargo workspace. Wait for the
	-- actual operation we need, rather than treating an initialized client as ready.
	assert(
		vim.wait(90000, function()
			response = client:request_sync("textDocument/definition", {
				textDocument = { uri = vim.uri_from_fname(path) },
				position = { line = row - 1, character = col - 1 },
			}, 5000, bufnr)
			if response and not response.err and response.result then
				location = response.result.uri and response.result or response.result[1]
			end
			return location ~= nil
		end, 250),
		"Language server returned no definition: " .. server_name .. " " .. vim.inspect(response)
	)
	local uri = location.targetUri or location.uri
	local range = location.targetSelectionRange or location.range
	assert(vim.uri_to_fname(uri) == path, "Definition resolved to the wrong source")
	local expected_line = M.marker(path, definition_marker)
	assert(range.start.line == expected_line - 1, "Definition resolved to the wrong line")
	local original = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { broken_line })
	assert(
		vim.wait(90000, function()
			for _, diagnostic in ipairs(vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })) do
				if diagnostic.lnum >= #original then
					return true
				end
			end
		end, 50),
		server_name .. " did not report the intentional type error: " .. vim.inspect(vim.diagnostic.get(bufnr))
	)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original)
	vim.bo[bufnr].modified = false
	return client
end

function M.breakpoint(path, root, config)
	print("Native workflow: " .. config.type .. " breakpoint in " .. vim.fs.basename(path))
	require("lazy").load({ plugins = { "nvim-dap", config.type == "go" and "nvim-dap-go" or "nvim-dap" } })
	local dap = require("dap")
	-- Exercise the real adapter/protocol without opening unrelated UI in headless tests.
	dap.listeners.after.event_initialized.user_dap_ui = nil
	dap.listeners.before.event_terminated.user_dap_ui = nil
	dap.listeners.before.event_exited.user_dap_ui = nil
	M.edit(path, root)
	local line = M.marker(path, "BREAKPOINT")
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	dap.clear_breakpoints()
	dap.set_breakpoint()
	local stopped, failure, output = false, nil, {}
	dap.listeners.after.event_stopped.native_workflow = function(_, body)
		stopped = body.reason == "breakpoint"
	end
	dap.listeners.after.event_output.native_workflow = function(_, body)
		if body.output then
			table.insert(output, body.output)
		end
	end
	dap.listeners.after.event_terminated.native_workflow = function()
		if not stopped then
			failure = "Debug session terminated before hitting the breakpoint"
		end
	end
	dap.run(vim.tbl_extend("force", {
		name = "Native workflow fixture",
		request = "launch",
		cwd = root,
		stopOnEntry = false,
	}, config))
	local hit = vim.wait(60000, function()
		local session = dap.session()
		local frame = session and session.current_frame
		return failure or (stopped and frame and frame.source and frame.source.path == path and frame.line == line)
	end, 50)
	local function cleanup()
		dap.listeners.after.event_stopped.native_workflow = nil
		dap.listeners.after.event_output.native_workflow = nil
		dap.listeners.after.event_terminated.native_workflow = nil
		if dap.session() then
			dap.terminate()
			vim.wait(10000, function()
				return dap.session() == nil
			end, 20)
		end
		dap.clear_breakpoints()
	end
	cleanup()
	assert(hit and not failure, (failure or "Breakpoint was not hit") .. "\n" .. table.concat(output))
end

function M.neotest(path, root)
	print("Native workflow: Neotest pass/fail " .. path)
	local bufnr = M.edit(path, root)
	local testing = require("user.core.testing")
	assert(testing.prepare(), "No configured Neotest adapter for " .. path)
	local neotest = require("neotest")
	local function status(wanted)
		for _, id in ipairs(neotest.state.adapter_ids()) do
			local counts = neotest.state.status_counts(id, { buffer = bufnr })
			if counts and counts[wanted] > 0 and counts.running == 0 then
				return true
			end
		end
		return false
	end
	testing.run({ path, env = { NVIM_NATIVE_FAIL = "0" } })
	assert(
		vim.wait(120000, function()
			return status("passed")
		end, 50),
		"Neotest did not report passing fixture tests: " .. path
	)
	testing.run({ path, env = { NVIM_NATIVE_FAIL = "1" } })
	assert(
		vim.wait(120000, function()
			return status("failed")
		end, 50),
		"Neotest did not report intentional failing fixture tests: " .. path
	)
end

return M
