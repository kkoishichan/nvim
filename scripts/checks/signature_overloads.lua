-- The signature popup shows the selected overload only, highlights its own
-- parameter, marks "(n/m)", cycles with <C-s>, keeps a manual choice for the
-- call until the server changes its mind, and forwards the choice for the
-- next retrigger. Without the adapter the locked plugin paints the active
-- parameter of overload n onto the label of overload 1.
return function(tmp)
	local api = vim.api
	require("lazy").load({ plugins = { "blink.cmp" } })
	local cmp = require("blink.cmp")
	assert(
		vim.wait(2000, function()
			return package.loaded["blink.cmp.signature.window"] ~= nil
		end),
		"Blink signature setup did not finish"
	)
	local adapter = require("user.core.signature_overloads")
	local window = require("blink.cmp.signature.window")
	local trigger = require("blink.cmp.signature.trigger")
	assert(adapter.active(), "Overload adapter is not active after startup")
	local entry
	for _, item in ipairs(require("user.core.adapters").list()) do
		if item.name == "signature_overloads" then
			entry = item
		end
	end
	assert(entry and entry.active, "Adapter registry does not list signature_overloads as active")

	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(buf, tmp .. "/overloads.fixture")
	api.nvim_set_current_buf(buf)
	local response
	local client_id = assert(vim.lsp.start({
		name = "overload_fixture",
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
		"Overload fixture did not attach"
	)
	-- Leave room above the cursor; Blink closes a popup it cannot place.
	local lines = {}
	for _ = 1, 12 do
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = "area(2.0, "
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.cmd("noautocmd setlocal filetype=cpp")
	api.nvim_win_set_cursor(0, { #lines, 10 })

	local function popup_buf()
		local win = window.win:get_win()
		assert(win and api.nvim_win_is_valid(win), "Signature popup is not open")
		return api.nvim_win_get_buf(win)
	end
	local function shown()
		local pbuf = popup_buf()
		local result = { lines = api.nvim_buf_get_lines(pbuf, 0, -1, false) }
		for _, mark in ipairs(api.nvim_buf_get_extmarks(pbuf, -1, 0, -1, { details = true })) do
			local details = mark[4]
			if details.hl_group == "BlinkCmpSignatureHelpActiveParameter" then
				result.parameter = table.concat(
					api.nvim_buf_get_text(pbuf, mark[2], mark[3], details.end_row, details.end_col, {}),
					"\n"
				)
			elseif details.hl_group == "BlinkCmpSignatureHelpOverload" then
				result.marker = api.nvim_buf_get_text(pbuf, mark[2], mark[3], mark[2], details.end_col, {})[1]
			end
		end
		return result
	end
	-- Blink creates its sources on the first automatic trigger; a manual
	-- show before that has nothing to ask. The first request therefore comes
	-- from entering Insert mode inside the call, as it would for a user.
	-- `how` is "insert" for the first automatic request, "retrigger" for the
	-- re-request Blink makes while the popup is open (cursor movement or a
	-- retrigger character), and nil for the public manual show, which Blink
	-- only accepts while the popup is hidden.
	local function show(help, how)
		response = help
		vim.v.errmsg = ""
		local renders = adapter.renders()
		if how == "insert" then
			api.nvim_exec_autocmds("InsertEnter", { buffer = buf, modeline = false })
		elseif how == "retrigger" then
			assert(trigger.context, "No signature context to retrigger")
			trigger.show()
		else
			assert(cmp.show_signature(), "Public signature show failed")
		end
		assert(
			vim.wait(1000, function()
				return adapter.renders() > renders and cmp.is_signature_visible()
			end),
			("LSP response did not open a signature popup (renders %d -> %d, visible %s): %s"):format(
				renders,
				adapter.renders(),
				tostring(cmp.is_signature_visible()),
				vim.v.errmsg
			)
		)
		assert(vim.v.errmsg == "", "Rendering raised an error: " .. vim.v.errmsg)
		return shown()
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

	local two = {
		activeSignature = 1,
		activeParameter = 1,
		signatures = {
			{
				label = "int area(int width, int height)",
				parameters = { { label = { 9, 18 } }, { label = { 20, 30 } } },
			},
			{
				label = "double area(double radius, bool precise)",
				parameters = { { label = { 12, 25 } }, { label = { 27, 39 } } },
			},
		},
	}

	-- 1. The server's second overload is the only one shown and its own
	--    parameter is highlighted; offsets past the first label no longer fail.
	local view = show(two, "insert")
	assert(#view.lines == 1, "Popup shows more than the selected overload: " .. vim.inspect(view.lines))
	assert(view.lines[1] == "double area(double radius, bool precise)  (2/2)", "Selected overload label is wrong")
	assert(view.parameter == "bool precise", "Active parameter was not highlighted on the selected overload")
	assert(view.marker == "(2/2)", "Overload marker is missing: " .. tostring(view.marker))
	local reported = adapter.shown()
	assert(reported.index == 2 and reported.count == 2, "Adapter reports the wrong overload")

	-- 2. <C-s> cycles, re-highlights and forwards the choice for the retrigger.
	assert(adapter.cycle(1), "Cycling did nothing")
	view = shown()
	assert(view.lines[1] == "int area(int width, int height)  (1/2)", "Cycling did not show the first overload")
	assert(view.parameter == "int height", "Cycling did not move the parameter highlight")
	assert(
		trigger.context and trigger.context.active_signature_help.activeSignature == 0,
		"Manual overload choice is not forwarded in the retrigger context"
	)
	assert(adapter.cycle(1), "Cycling did not wrap")
	assert(shown().marker == "(2/2)", "Cycling did not wrap to the server's overload")
	assert(adapter.cycle(1) and shown().marker == "(1/2)", "Third cycle failed")

	-- 3. A retrigger with the same server choice keeps the manual choice.
	view = show(two, "retrigger")
	assert(view.marker == "(1/2)", "Retrigger discarded the manual overload choice")

	-- 4. When the server changes its own choice, the server wins.
	local three = vim.deepcopy(two)
	three.signatures[3] = { label = "float area(float side)", parameters = { { label = { 11, 21 } } } }
	three.activeSignature = 1
	view = show(three, "retrigger")
	assert(view.marker == "(2/3)", "A changed signature count did not reset to the server's choice")
	assert(adapter.cycle(1) and shown().marker == "(3/3)", "Cycling to the third overload failed")
	three.activeSignature = 0
	view = show(three, "retrigger")
	assert(view.marker == "(1/3)", "Server's new choice did not override the manual one")
	assert(view.parameter == "int height", "Parameter highlight did not follow the server's new choice")

	-- 5. A new call site starts from the server's choice again.
	assert(adapter.cycle(1) and shown().marker == "(2/3)", "Cycling after the server change failed")
	hide()
	assert(not adapter.cycle(1), "Cycling worked without a popup")
	three.activeSignature = 0
	view = show(three)
	assert(view.marker == "(1/3)", "A new call inherited the previous manual choice")

	-- 6. A single signature renders untouched; an empty answer closes the popup.
	hide()
	local single = {
		activeParameter = 0,
		signatures = { { label = "void plain(int alpha)", parameters = { { label = { 11, 20 } } } } },
	}
	view = show(single)
	assert(view.lines[1] == "void plain(int alpha)" and view.marker == nil, "Single signature was decorated")
	assert(view.parameter == "int alpha", "Single signature lost its parameter highlight")
	assert(not adapter.cycle(1), "Cycling a single signature claimed to work")
	response = { signatures = {} }
	local renders = adapter.renders()
	trigger.show()
	assert(
		vim.wait(1000, function()
			return adapter.renders() > renders and not cmp.is_signature_visible()
		end),
		"An empty answer left the popup open"
	)

	-- 7. Shutdown restores the plugin's own renderer; setup reinstalls it.
	adapter.shutdown()
	assert(not adapter.active(), "Adapter still active after shutdown")
	local native = window.open_with_signature_help
	assert(
		debug.getinfo(native, "S").source:find("blink%.cmp/lua/blink/cmp/signature/window%.lua$"),
		"Native renderer was not restored"
	)
	assert(adapter.setup(), "Adapter did not reinstall")
	assert(window.open_with_signature_help ~= native and adapter.active(), "Reinstall did not wrap the renderer")
	view = show(two)
	assert(view.marker == "(2/2)" and view.parameter == "bool precise", "Reinstalled adapter does not render")
	hide()

	client:stop(true)
	api.nvim_buf_delete(buf, { force = true })
	print(
		"Signature overloads passed: single overload shown with its own highlight, marker, <C-s> cycling and forwarding, manual choice kept until the server changes, new call resets, single signature untouched, shutdown and reinstall"
	)
end
