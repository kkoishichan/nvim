return function(tmp)
	local policy = require("user.core.buffer_policy")
	local function edit(name, lines)
		local path = vim.fs.joinpath(tmp, name)
		vim.fn.writefile(lines, path)
		vim.cmd.edit(vim.fn.fnameescape(path))
		return vim.api.nvim_get_current_buf()
	end
	local function drain()
		vim.wait(80, function()
			return false
		end, 10)
	end
	local long = edit("long.json", { '{"text":"' .. string.rep("a", 30000) .. '"}' })
	assert(vim.b[long].bigfile and not policy.allow(long), "30 KB long line bypassed policy")
	assert(vim.bo[long].filetype == "json", "Cost policy erased filetype")
	drain()
	assert(#vim.lsp.get_clients({ bufnr = long }) == 0, "Large buffer acquired a language server")
	local colors = require("lazy.core.config").plugins["nvim-highlight-colors"].opts
	assert(colors.exclude_buffer(long), "Color scanning did not exclude the long line")
	assert(vim.bo[long].undolevels ~= -1, "Policy disabled undo")

	local sparse = {}
	for i = 1, 1000 do
		sparse[i] = "short"
	end
	sparse[501] = string.rep("x", 3000)
	local mixed = edit("sparse.txt", sparse)
	assert(not policy.allow(mixed), "Sparse long line hidden by average length")
	local large = edit("large.txt", { string.rep("a", 2 * 1024 * 1024) })
	assert(not policy.allow(large), "Byte ceiling ignored")
	local many = {}
	for i = 1, 10002 do
		many[i] = "x"
	end
	assert(not policy.allow(edit("many.txt", many)), "Line count ceiling ignored")

	local normal = edit("normal.txt", { "ordinary content" })
	assert(policy.allow(normal), "Normal file lost full features")
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { string.rep("a", 3000) })
	assert(vim.b[normal].bigfile, "Pasted long line was not classified synchronously")
	drain()
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { "ordinary again" })
	assert(policy.allow(normal), "Edited normal content did not recover")
	drain()
	assert(policy.set(normal, "off").heavy, "Manual disable ignored")
	drain()
	assert(not policy.set(normal, "auto").heavy, "Automatic recovery ignored")
	drain()
	vim.wo.foldmethod, vim.wo.foldenable = "indent", true
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { string.rep("h", 3000) })
	drain()
	edit("other.txt", { "other buffer" })
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { "normal while hidden" })
	drain()
	vim.api.nvim_set_current_buf(normal)
	assert(vim.wo.foldmethod == "indent" and vim.wo.foldenable, "Hidden buffer lost its original fold settings")

	-- A root discovered asynchronously must re-check the document at completion.
	local complete, accepted
	local root = policy.lsp_root({
		root_dir = function(_, callback)
			complete = callback
		end,
	})
	root(normal, function()
		accepted = true
	end)
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { string.rep("b", 3000) })
	complete(tmp)
	assert(not accepted, "A queued root callback admitted a now-expensive buffer")
	vim.api.nvim_buf_set_lines(normal, 0, -1, false, { "ordinary again" })
	drain()

	-- An in-process LSP speaks the real initialization protocol without starting
	-- external services. Two documents share it; only the costly one detaches.
	local started = 0
	local delay_initialize, initialize
	local opened = {}
	local function server(dispatchers)
		started = started + 1
		local closing = false
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
				local reply = function()
					callback(
						nil,
						method == "initialize" and { capabilities = { hoverProvider = true, textDocumentSync = 1 } }
							or vim.NIL
					)
				end
				if method == "initialize" and delay_initialize then
					initialize = reply
				else
					vim.schedule(reply)
				end
				return true, 1
			end,
			notify = function(method, params)
				if method == "textDocument/didOpen" then
					opened[params.textDocument.uri] = true
				end
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
	end
	vim.lsp.config("user_policy_test", {
		cmd = server,
		filetypes = { "policytest" },
		root_dir = policy.lsp_root({ root_dir = tmp }),
		on_init = policy.lsp_init(),
	})
	vim.lsp.enable("user_policy_test")
	vim.bo[long].filetype = "policytest"
	drain()
	assert(started == 0, "LSP started for an expensive buffer")
	vim.bo[normal].filetype = "policytest"
	assert(
		vim.wait(2000, function()
			return #vim.lsp.get_clients({ name = "user_policy_test", bufnr = normal }) == 1
		end, 10),
		"Normal document failed to attach to the test server"
	)
	local client = vim.lsp.get_clients({ name = "user_policy_test", bufnr = normal })[1]
	assert(vim.lsp.buf_attach_client(long, client.id), "Test setup could not attach the second document")
	drain()
	assert(not vim.lsp.buf_is_attached(long, client.id), "Late LSP attachment survived the cost guard")
	assert(vim.lsp.buf_is_attached(normal, client.id), "Cost guard detached the other document")
	assert(vim.lsp.is_enabled("user_policy_test"), "Cost guard disabled the shared server")
	assert(not client:is_stopped(), "Cost guard stopped the shared process")
	vim.lsp.enable("user_policy_test", false)
	drain()

	-- Initialize can return after the document changed. The costly document
	-- must never be sent via didOpen, while another queued document survives.
	delay_initialize = true
	opened = {}
	local slow = edit("slow.txt", { "initially small" })
	local slow_id = assert(vim.lsp.start({
		name = "user_policy_slow",
		cmd = server,
		root_dir = tmp,
		on_init = policy.lsp_init(),
	}, { bufnr = slow }))
	assert(initialize, "Slow test initialization was not queued")
	local second = edit("second.txt", { "another normal document" })
	assert(vim.lsp.buf_attach_client(second, slow_id))
	vim.api.nvim_buf_set_lines(slow, 0, -1, false, { string.rep("z", 3000) })
	drain()
	initialize()
	drain()
	assert(not opened[vim.uri_from_bufnr(slow)], "Slow initialization sent the costly document")
	assert(opened[vim.uri_from_bufnr(second)], "Slow initialization lost the normal document")
	assert(vim.lsp.buf_is_attached(second, slow_id), "Normal queued document detached")
	assert(not vim.lsp.buf_is_attached(slow, slow_id), "Costly queued document attached")
	vim.lsp.get_client_by_id(slow_id):stop(true)
end
