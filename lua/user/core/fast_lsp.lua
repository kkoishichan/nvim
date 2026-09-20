-- One language server, started because you asked for it.
--
-- Starting a server reintroduces edit synchronisation, analysis and possibly a
-- project index; hiding the diagnostics would not take any of that back. So the
-- lifecycle is explicit in both directions: :FastLspStart attaches exactly one
-- primary server to the current buffer, and :FastLspStop gives it up again.
--
-- Only the shared server definitions are loaded. The full-mode wiring
-- (completion engine, peek windows, lightbulb, reference highlighting, progress
-- notifications) is never pulled in to satisfy this command.

local M = {}

-- client id -> { name = string, buffers = { [bufnr] = true } }
local managed = {}
local pending = {}
local group

-- Settings that keep a server's analysis on the documents that are open, where
-- the server offers the choice. Anything without such a switch simply keeps its
-- own default; the command says what it started, not what it costs.
local open_files_only = {
	basedpyright = { settings = { basedpyright = { analysis = { diagnosticMode = "openFilesOnly" } } } },
	lua_ls = { settings = { Lua = { diagnostics = { workspaceDelay = -1 } } } },
	vtsls = { settings = { vtsls = { experimental = { enableProjectDiagnostics = false } } } },
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Language server" })
end

local function definitions()
	-- The server definitions live in nvim-lspconfig's runtime files, so the
	-- plugin only needs to be on the runtimepath; it is not configured here.
	pcall(function()
		require("lazy").load({ plugins = { "nvim-lspconfig" } })
	end)
	return require("user.core.manual_lsp")
end

local function watch_buffers()
	if group then
		return
	end
	group = vim.api.nvim_create_augroup("user_fast_lsp", { clear = true })
	vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload" }, {
		group = group,
		desc = "Release a manually started language server with its last buffer",
		callback = function(event)
			pending[event.buf] = nil
			for id, entry in pairs(managed) do
				entry.buffers[event.buf] = nil
				if vim.tbl_isempty(entry.buffers) then
					M.release(id)
				end
			end
		end,
	})
end

---Stop a client this mode owns, provided nothing else is still using it.
function M.release(id)
	local entry = managed[id]
	if not entry then
		return
	end
	managed[id] = nil
	local client = vim.lsp.get_client_by_id(id)
	if not client then
		return
	end
	for bufnr in pairs(entry.buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.lsp.buf_detach_client, bufnr, id)
		end
	end
	if next(client.attached_buffers) == nil then
		client:stop()
	end
end

---Servers that could own this buffer's filetype and have an installed command.
---@param bufnr integer
---@param include_auxiliary boolean|nil
function M.candidates(bufnr, include_auxiliary)
	local shared = definitions()
	local filetype = vim.bo[bufnr].filetype
	local names = {}
	for _, server in ipairs(shared.resolve()) do
		if include_auxiliary or not shared.auxiliary[server] then
			local config = vim.lsp.config[server]
			if config and vim.tbl_contains(config.filetypes or {}, filetype) then
				table.insert(names, server)
			end
		end
	end
	table.sort(names)
	return names
end

local function launch(name, bufnr, request)
	definitions()
	local config = vim.tbl_deep_extend("force", vim.deepcopy(vim.lsp.config[name] or {}), open_files_only[name] or {})
	config.name = name

	local function start(root)
		if pending[bufnr] ~= request or not vim.api.nvim_buf_is_loaded(bufnr) then
			return
		end
		pending[bufnr] = nil
		if not require("user.core.buffer_policy").allow(bufnr) then
			return
		end
		config.root_dir = root
		local attached = {}
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			attached[client.id] = true
		end
		local ok, id = pcall(vim.lsp.start, config, { bufnr = bufnr })
		if not ok or not id then
			notify(name .. " did not start: " .. (ok and "no client" or tostring(id)), vim.log.levels.ERROR)
			return
		end
		if attached[id] and not managed[id] then
			notify(name .. " is already attached; its existing owner keeps control")
			return
		end
		watch_buffers()
		managed[id] = managed[id] or { name = name, buffers = {} }
		managed[id].buffers[bufnr] = true
		notify(name .. " attached to " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:."))
	end

	local root = config.root_dir
	if type(root) == "function" then
		-- The definitions wrap root discovery, including its asynchronous form.
		root(bufnr, function(directory)
			vim.schedule(function()
				start(directory)
			end)
		end)
	else
		start(root or (config.root_markers and vim.fs.root(bufnr, config.root_markers)))
	end
end

---Start one server for the current buffer. With a name, start that server;
---otherwise offer the installed primary servers for this filetype.
function M.start(name)
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "" then
		notify("Current buffer is not a normal file", vim.log.levels.WARN)
		return
	end
	if not require("user.core.buffer_policy").allow(bufnr) then
		notify("This buffer runs with reduced features; :BufferFeatures on overrides it", vim.log.levels.WARN)
		return
	end
	watch_buffers()
	local request = {}
	pending[bufnr] = request

	if name and name ~= "" then
		local shared = definitions()
		if not vim.tbl_contains(shared.servers, name) then
			pending[bufnr] = nil
			notify("Unknown language server: " .. name, vim.log.levels.ERROR)
			return
		end
		if not vim.tbl_contains(shared.resolve(), name) then
			pending[bufnr] = nil
			notify(name .. " is not installed on this host; install its executable first", vim.log.levels.ERROR)
			return
		end
		launch(name, bufnr, request)
		return
	end

	local candidates = M.candidates(bufnr)
	if #candidates == 0 then
		pending[bufnr] = nil
		notify("No installed language server handles " .. vim.bo[bufnr].filetype, vim.log.levels.WARN)
		return
	end
	if #candidates == 1 then
		launch(candidates[1], bufnr, request)
		return
	end
	vim.ui.select(candidates, { prompt = "Language server" }, function(choice)
		if pending[bufnr] ~= request then
			return
		end
		if choice and vim.api.nvim_buf_is_loaded(bufnr) then
			launch(choice, bufnr, request)
		else
			pending[bufnr] = nil
		end
	end)
end

---Give up every client this mode started. Buffers held by another owner keep
---their client; only ours are detached.
function M.stop()
	local had_pending = not vim.tbl_isempty(pending)
	pending = {}
	if vim.tbl_isempty(managed) then
		notify(
			had_pending and "Cancelled pending language-server starts" or "No language server was started by this mode"
		)
		return
	end
	local names = {}
	for id, entry in pairs(managed) do
		table.insert(names, entry.name)
		M.release(id)
	end
	table.sort(names)
	notify("Stopped " .. table.concat(names, ", "))
end

---One line for `:ModeInfo`.
function M.summary()
	local parts = {}
	for id, entry in pairs(managed) do
		local client = vim.lsp.get_client_by_id(id)
		if client then
			table.insert(parts, ("%s #%d (%d buffers)"):format(entry.name, id, vim.tbl_count(entry.buffers)))
		end
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

function M.setup()
	vim.api.nvim_create_user_command("FastLspStart", function(command)
		M.start(command.args)
	end, {
		nargs = "?",
		desc = "Start one installed language server for this buffer",
		complete = function()
			return M.candidates(vim.api.nvim_get_current_buf(), true)
		end,
	})
	vim.api.nvim_create_user_command("FastLspStop", function()
		M.stop()
	end, { desc = "Stop the language servers this mode started" })
end

return M
