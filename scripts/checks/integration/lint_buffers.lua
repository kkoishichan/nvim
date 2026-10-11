return function(tmp)
	local api = vim.api
	local directory = tmp .. "/lint-diffview"
	vim.fn.mkdir(directory, "p")
	local function git(...)
		local command = { "git", "-C", directory, "-c", "commit.gpgSign=false" }
		vim.list_extend(command, { ... })
		local result = vim.system(command, { text = true }):wait()
		assert(result.code == 0, result.stderr)
	end
	git("init", "--quiet")
	local path = directory .. "/CMakeLists.txt"
	vim.fn.writefile({ "project(before)" }, path)
	git("add", "CMakeLists.txt")
	git(
		"-c",
		"user.name=Lint Check",
		"-c",
		"user.email=lint-check@example.invalid",
		"commit",
		"--quiet",
		"-m",
		"fixture"
	)
	vim.fn.writefile({ "project(after)" }, path)

	-- Run a real disk-based CLI: a revision URI is not a filesystem path.
	local script, log = tmp .. "/lint-fixture.sh", tmp .. "/lint-invocations.txt"
	vim.fn.writefile({
		'printf "%s\\n" "$2" >> "$1"',
		'case "$2" in *://*) echo "revision has no filesystem path" >&2; exit 2 ;; esac',
		'printf "fixture warning\\n"',
	}, script)
	require("lazy").load({ plugins = { "nvim-lint", "diffview.nvim" } })
	local lint = require("lint")
	local provider = "user_diffview_fixture"
	local previous = vim.deepcopy(lint.linters_by_ft.cmake)
	lint.linters[provider] = {
		cmd = assert(vim.fn.exepath("sh")),
		stdin = false,
		args = { script, log },
		parser = function(output)
			return output:find("fixture warning", 1, true)
					and { { lnum = 0, col = 0, message = "fixture warning", severity = vim.diagnostic.severity.WARN } }
				or {}
		end,
	}
	local namespace = lint.get_namespace(provider)
	-- Exercise Neovim's automatic LSP attachment too: the editable index has
	-- buftype="", but disk-oriented servers cannot handle its revision URI.
	local policy = require("user.core.buffer_policy")
	local opened = {}
	local server_name = "user_diffview_fixture"
	vim.lsp.config(server_name, {
		filetypes = { "cmake" },
		root_dir = policy.lsp_root({ root_dir = directory }),
		on_init = policy.lsp_init(),
		cmd = function(dispatchers)
			local closing = false
			return {
				request = function(method, _, callback)
					vim.schedule(function()
						callback(nil, method == "initialize" and { capabilities = { textDocumentSync = 1 } } or vim.NIL)
					end)
					return true, 1
				end,
				notify = function(method, params)
					if method == "textDocument/didOpen" then
						opened[params.textDocument.uri] = true
					end
					return true
				end,
				is_closing = function()
					return closing
				end,
				terminate = function()
					closing = true
					vim.schedule(function()
						dispatchers.on_exit(0, 0)
					end)
				end,
			}
		end,
	})
	vim.lsp.enable(server_name)
	local function install()
		lint.linters_by_ft.cmake = { provider }
	end
	local function invocations()
		return vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
	end
	local previous_cwd = vim.fn.getcwd()
	vim.cmd.cd(directory)
	install()
	vim.cmd.edit(path)
	local source = api.nvim_get_current_buf()
	assert(
		vim.wait(2000, function()
			return #vim.diagnostic.get(source, { namespace = namespace }) > 0
				and #lint.get_running(source) == 0
				and opened[vim.uri_from_bufnr(source)]
		end, 20),
		"Ordinary file did not receive lint diagnostics and automatic LSP attachment"
	)

	for _, revision in ipairs({ "HEAD", "" }) do
		vim.cmd("DiffviewOpen " .. revision .. " -- CMakeLists.txt")
		local snapshot
		assert(
			vim.wait(3000, function()
				for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
					local buf = api.nvim_win_get_buf(win)
					if vim.bo[buf].filetype == "cmake" and api.nvim_buf_get_name(buf):match("^diffview://") then
						snapshot = buf
						return true
					end
				end
				return false
			end, 20),
			"Diffview did not open the revision fixture"
		)
		if revision == "" then
			assert(vim.bo[snapshot].buftype == "" and vim.bo[snapshot].modifiable, "Index fixture is not editable")
		else
			assert(vim.bo[snapshot].buftype == "nowrite", "History fixture is not a revision buffer")
		end
		api.nvim_buf_call(snapshot, function()
			-- Reproduce nvim-lint being configured while the first revision's
			-- FileType loads it; its initial deferred pass must also be guarded.
			require("lazy.core.config").plugins["nvim-lint"].config()
			install()
			vim.cmd.Lint()
		end)
		for _, event in ipairs({ "BufReadPost", "InsertLeave", "BufWritePost" }) do
			api.nvim_exec_autocmds(event, { buffer = snapshot, group = "user_lint", modeline = false })
		end
		vim.wait(650, function()
			return false
		end, 20)
		for _, name in ipairs(invocations()) do
			assert(name == path, "Linter received a virtual revision path: " .. name)
		end
		assert(#vim.diagnostic.get(snapshot, { namespace = namespace }) == 0, "Revision received lint diagnostics")
		assert(not opened[vim.uri_from_bufnr(snapshot)], "Language server received a virtual revision URI")
		assert(#vim.lsp.get_clients({ bufnr = snapshot }) == 0, "Revision acquired a language server")

		-- The editable worktree pane still supports lint; 'diff' alone is not
		-- grounds to skip a real source file.
		local before = #invocations()
		api.nvim_buf_call(source, function()
			vim.cmd.Lint()
		end)
		assert(
			vim.wait(2000, function()
				return #invocations() > before and #lint.get_running(source) == 0
			end, 20),
			"Diffview's worktree file stopped supporting manual lint"
		)
		assert(
			#vim.lsp.get_clients({ bufnr = source, name = server_name }) == 1,
			"Diffview's worktree file lost its language server"
		)
		vim.cmd.DiffviewClose()
	end
	vim.lsp.enable(server_name, false)
	vim.cmd.cd(previous_cwd)
	lint.linters_by_ft.cmake = previous
	lint.linters[provider] = nil
	api.nvim_buf_delete(source, { force = true })
end
