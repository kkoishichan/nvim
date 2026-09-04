local M = {}
local completed = {}
local observed = false

function M.command(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait(60000)
	assert(result.code == 0, table.concat(argv, " ") .. "\n" .. (result.stderr or "") .. (result.stdout or ""))
	return result.stdout or ""
end

function M.marker(path, marker)
	for row, line in ipairs(vim.fn.readfile(path)) do
		if line:find(marker, 1, true) then
			return row
		end
	end
	error("Missing fixture marker: " .. marker)
end

function M.edit(path, root)
	require("user.core.project").set(root)
	vim.cmd.edit({ args = { path }, bang = true })
	return vim.api.nvim_get_current_buf()
end

function M.client(bufnr, name)
	local client
	assert(
		vim.wait(60000, function()
			for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = name })) do
				if candidate.initialized then
					client = candidate
					return true
				end
			end
		end, 50),
		name .. " did not attach"
	)
	return client
end

function M.language(path, root, name, bad_line)
	print("Python/JS workflow: " .. name .. " definition and unsaved diagnostic")
	local bufnr = M.edit(path, root)
	local client = M.client(bufnr, name)
	local row = M.marker(path, "DEFINITION")
	-- The target marker also contains DEFINITION, so select the actual call.
	for index, line in ipairs(vim.fn.readfile(path)) do
		if line:find("DEFINITION", 1, true) and not line:find("TARGET", 1, true) then
			row = index
		end
	end
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
	local response = client:request_sync("textDocument/definition", {
		textDocument = { uri = vim.uri_from_fname(path) },
		position = { line = row - 1, character = assert(line:find("answer", 1, true)) - 1 },
	}, 30000, bufnr)
	assert(response and not response.err and response.result, "Definition failed: " .. vim.inspect(response))
	local location = response.result.uri and response.result or response.result[1]
	assert(location, "Empty definition response from " .. name)
	assert(vim.uri_to_fname(location.targetUri or location.uri) == path, "Wrong definition file")
	assert(
		(location.targetSelectionRange or location.range).start.line == M.marker(path, "DEFINITION_TARGET") - 1,
		"Wrong definition line"
	)
	local original = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { bad_line })
	assert(
		vim.wait(60000, function()
			for _, diagnostic in ipairs(vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })) do
				if diagnostic.lnum == #original then
					return true
				end
			end
		end, 50),
		name .. " did not diagnose the unsaved error: " .. vim.inspect(vim.diagnostic.get(bufnr))
	)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, original)
	vim.bo[bufnr].modified = false
	return client
end

function M.neotest(path, root, framework)
	print("Python/JS workflow: Neotest " .. framework .. " pass and fail")
	local bufnr = M.edit(path, root)
	local testing = require("user.core.testing")
	if not observed then
		-- Observe final results through Neotest's documented consumer API;
		-- streamed counts can finish before the underlying process exits.
		local neotest = require("neotest")
		local setup = neotest.setup
		neotest.setup = function(config)
			neotest.setup = setup
			config.consumers = config.consumers or {}
			config.consumers.workflow_results = function(client)
				client.listeners.results = function(id, _, partial)
					if not partial then
						completed[id] = (completed[id] or 0) + 1
					end
				end
			end
			return setup(config)
		end
		observed = true
	end
	assert(testing.prepare(), "No test adapter for " .. path)
	local neotest = require("neotest")
	local last_counts = {}
	local previous = vim.deepcopy(completed)
	local function status(wanted)
		for _, id in ipairs(neotest.state.adapter_ids()) do
			local counts = neotest.state.status_counts(id, { buffer = bufnr })
			if counts then
				last_counts[id] = vim.deepcopy(counts)
				local complete = wanted == "passed" and counts.passed == counts.total and counts.failed == 0
					or wanted == "failed" and counts.failed > 0
				if
					counts.total > 0
					and complete
					and counts.running == 0
					and (completed[id] or 0) > (previous[id] or 0)
				then
					assert(id:find(framework, 1, true), "Wrong adapter handled " .. path .. ": " .. id)
					return true
				end
			end
		end
	end
	testing.run({ path, env = { NVIM_WORKFLOW_FAIL = "0" } })
	assert(
		vim.wait(60000, function()
			return status("passed")
		end, 50),
		"No passing " .. framework .. " result: " .. vim.inspect(last_counts)
	)
	previous = vim.deepcopy(completed)
	testing.run({ path, env = { NVIM_WORKFLOW_FAIL = "1" } })
	assert(
		vim.wait(60000, function()
			return status("failed")
		end, 50),
		"No intentional failing " .. framework .. " result: " .. vim.inspect(last_counts)
	)
end

function M.breakpoint(path, root, config, expression, expected)
	print("Python/JS workflow: " .. config.type .. " breakpoint in " .. vim.fs.basename(path))
	require("lazy").load({ plugins = { config.type == "python" and "nvim-dap-python" or "nvim-dap" } })
	local dap = require("dap")
	dap.listeners.after.event_initialized.user_dap_ui = nil
	dap.listeners.before.event_terminated.user_dap_ui = nil
	dap.listeners.before.event_exited.user_dap_ui = nil
	M.edit(path, root)
	local line = M.marker(path, "BREAKPOINT")
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	dap.clear_breakpoints()
	dap.set_breakpoint()
	local stopped, ended, output = false, false, {}
	dap.listeners.after.event_stopped.python_js_workflow = function(_, body)
		stopped = body.reason == "breakpoint"
	end
	dap.listeners.after.event_terminated.python_js_workflow = function()
		ended = true
	end
	dap.listeners.after.event_output.python_js_workflow = function(_, body)
		table.insert(output, body.output or "")
	end
	local ok, err = xpcall(function()
		dap.run(vim.tbl_extend("force", {
			name = "Isolated Python/JS workflow fixture",
			request = "launch",
			cwd = root,
			console = "internalConsole",
			stopOnEntry = false,
		}, config))
		assert(vim.wait(60000, function()
			local session = dap.session()
			local frame = session and session.current_frame
			return ended or (stopped and frame and frame.line == line and frame.source.path == path)
		end, 50) and not ended, "Breakpoint was not hit: " .. table.concat(output))
		local session = assert(dap.session())
		local evaluated, result, failure
		session:request("evaluate", {
			expression = expression or "value",
			frameId = session.current_frame.id,
			context = "repl",
		}, function(eval_err, body)
			evaluated, result, failure = true, body and body.result, eval_err
		end)
		assert(vim.wait(10000, function()
			return evaluated
		end, 20) and not failure, "DAP evaluation failed: " .. vim.inspect(failure))
		assert(result and result:find(expected or "42", 1, true), "Unexpected DAP value: " .. tostring(result))
	end, debug.traceback)
	dap.listeners.after.event_stopped.python_js_workflow = nil
	dap.listeners.after.event_terminated.python_js_workflow = nil
	dap.listeners.after.event_output.python_js_workflow = nil
	if next(dap.sessions()) then
		dap.terminate({ all = true, hierarchy = true })
		assert(
			vim.wait(10000, function()
				return next(dap.sessions()) == nil
			end, 20),
			"DAP sessions did not terminate"
		)
	end
	dap.clear_breakpoints()
	assert(ok, err)
end

return M
