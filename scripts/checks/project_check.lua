-- Project checks parse real tool output into quickfix items and run only on
-- request; workspace symbol search routes to a live server query, ripgrep
-- definition patterns or plain grep depending on what the buffer has.
return function(tmp)
	local check = require("user.core.project_check")
	local symbols = require("user.core.symbols")

	-- 1. Output parsing covers every supported tool's line shape.
	local items = check.parse(
		"ruff",
		"src/app.py:3:8: F401 [*] `os` imported but unused\nsrc/app.py:9:1: SyntaxError: unexpected indent\n",
		"/proj"
	)
	assert(
		#items == 2 and items[1].filename == "/proj/src/app.py" and items[1].lnum == 3 and items[1].col == 8,
		vim.inspect(items)
	)
	assert(items[1].type == "W" and items[2].type == "E", "Ruff severities are wrong")
	items = check.parse("tsc", "src/scheduler.ts(216,5): error TS18048: 'run' is possibly 'undefined'.\n", "/proj")
	assert(
		#items == 1
			and items[1].lnum == 216
			and items[1].col == 5
			and items[1].type == "E"
			and items[1].text:find("TS18048", 1, true),
		vim.inspect(items)
	)
	items = check.parse(
		"cargo",
		"    Checking x v0.1.0\nsrc/lib.rs:12:5: warning: unused variable: `x`\nsrc/lib.rs:20:9: error[E0308]: mismatched types\nerror: could not compile `x`\n",
		"/proj"
	)
	assert(#items == 2 and items[1].type == "W" and items[2].type == "E", vim.inspect(items))
	items =
		check.parse("vet", "# example.com/x\n./logs.go:279:19: cannot use count (variable of type string)\n", "/proj")
	assert(#items == 1 and items[1].filename == "/proj/logs.go", vim.inspect(items))
	items = check.parse("selene", "build.lua:39:7: warning[unused_variable]: unused_limit is never used\n", "/proj")
	assert(#items == 1 and items[1].type == "W", vim.inspect(items))
	assert(#check.parse("ruff", "All checks passed!\n", "/proj") == 0, "Prose lines produced findings")

	-- 2. Availability follows project markers and tool presence.
	local project = vim.fs.joinpath(tmp, "proj")
	vim.fn.mkdir(project, "p")
	vim.fn.writefile({ "[project]", 'name = "x"' }, project .. "/pyproject.toml")
	vim.fn.writefile({ "{}" }, project .. "/tsconfig.json")
	local toolchain = require("user.toolchain")
	local executable, node_executable = toolchain.executable, toolchain.node_executable
	toolchain.executable = function(name, ...)
		if name == "ruff" then
			return "/fixture/ruff"
		end
		return executable(name, ...)
	end
	toolchain.node_executable = function()
		return nil
	end
	local ctx = { language_root = project, root = project }
	local available = check.available(ctx)
	local names = vim.tbl_map(function(entry)
		return entry.name
	end, available)
	assert(vim.deep_equal(names, { "ruff", "tsc" }), vim.inspect(names))
	assert(available[1].argv[1] == "/fixture/ruff" and available[1].root == project, "Ruff command or root is wrong")
	assert(available[2].argv == nil, "tsc must be unavailable without a project binary")
	assert(
		vim.deep_equal(check.available({ language_root = tmp, root = tmp }), {}),
		"Unmarked directory offered checks"
	)

	-- 3. Execution: a stand-in tool prints findings into the quickfix list;
	--    a failing tool without findings is reported instead.
	local script = project .. "/fake-check"
	vim.fn.writefile(
		{ "#!/bin/sh", "printf 'a.py:1:2: W001 first\\nb.py:3:4: SyntaxError: second\\n'", "exit 1" },
		script
	)
	vim.fn.setfperm(script, "rwxr-xr-x")
	local entry = { name = "ruff", label = "fake", root = project, argv = { script }, check = check.checks.ruff }
	local notices = {}
	local notify = vim.notify
	vim.notify = function(message, level)
		notices[#notices + 1] = { message = message, level = level }
	end
	check.last = nil
	assert(check.execute(entry, { open = false }), "execute refused a valid entry")
	assert(
		vim.wait(5000, function()
			return check.last ~= nil
		end, 25),
		"Fake check did not finish"
	)
	assert(check.last.code == 1 and #check.last.items == 2, vim.inspect(check.last))
	local list = vim.fn.getqflist({ title = 1, items = 1 })
	assert(list.title:find("fake", 1, true) and #list.items == 2, "Quickfix list was not filled: " .. list.title)
	assert(
		list.items[2].type == "E" and vim.api.nvim_buf_get_name(list.items[2].bufnr) == project .. "/b.py",
		"Quickfix items lost severity or path"
	)
	vim.fn.writefile({ "#!/bin/sh", "echo boom >&2", "exit 2" }, script)
	check.last, notices = nil, {}
	check.execute(entry, { open = false })
	assert(
		vim.wait(5000, function()
			return check.last ~= nil
		end, 25),
		"Failing check did not finish"
	)
	local reported = false
	for _, notice in ipairs(notices) do
		if notice.level == vim.log.levels.ERROR and notice.message:find("boom", 1, true) then
			reported = true
		end
	end
	assert(reported, "Tool failure was not reported")
	assert(check.run("nope") == false, "An unknown check name was accepted")
	vim.notify = notify
	toolchain.executable, toolchain.node_executable = executable, node_executable

	-- 4. Definition patterns, exercised with the real ripgrep.
	local rg = vim.fn.exepath("rg")
	assert(rg ~= "", "ripgrep is required for this check")
	local samples = {
		python = {
			hits = { "def alpha():", "class Beta:", "    async def gamma(self):" },
			misses = { "alpha()", "# def not" },
		},
		lua = {
			hits = { "local function alpha()", "function M.beta()", "local gamma = function()" },
			misses = { "alpha()", "-- function" },
		},
		sh = { hits = { "alpha() {", "function beta() {" }, misses = { "alpha", "echo beta()" } },
		go = {
			hits = { "func Alpha() {", "func (s *Stats) Beta() {", "type Entry struct {" },
			misses = { "\tfunc() {", "x := Alpha()" },
		},
		rust = {
			hits = { "pub fn alpha() {", "struct Beta {", "impl Gamma {", "pub(crate) async fn delta() {" },
			misses = { "alpha();", "let x = 1;" },
		},
		javascript = {
			hits = { "export function alpha() {", "class Beta {", "const gamma = 1;", "export default class Delta {" },
			misses = { "alpha();", "return x;" },
		},
		markdown = { hits = { "# Title", "### Sub" }, misses = { "#hashtag", "text" } },
		sql = { hits = { "CREATE TABLE customers (", "create or replace function f()" }, misses = { "SELECT 1;" } },
	}
	for filetype, sample in pairs(samples) do
		local pattern = assert(symbols.pattern_for(filetype), "no pattern for " .. filetype)
		local file = vim.fs.joinpath(tmp, "sample." .. filetype)
		local lines = {}
		vim.list_extend(lines, sample.hits)
		vim.list_extend(lines, sample.misses)
		vim.fn.writefile(lines, file)
		local result = vim.system({ rg, "--no-config", "-n", "-e", pattern, file }, { text = true }):wait()
		local matched = {}
		for line in (result.stdout or ""):gmatch("[^\n]+") do
			local number = line:match("^(%d+):")
			matched[tonumber(number)] = true
		end
		for index = 1, #sample.hits do
			assert(matched[index], filetype .. " pattern missed: " .. sample.hits[index])
		end
		for index = #sample.hits + 1, #lines do
			assert(not matched[index], filetype .. " pattern matched: " .. lines[index])
		end
	end
	assert(
		symbols.pattern_for("typescript") == symbols.pattern_for("javascript")
			and symbols.pattern_for("bash") == symbols.pattern_for("sh"),
		"Aliases are wrong"
	)
	assert(symbols.pattern_for("json") == nil, "Unexpected pattern for json")

	-- 5. Workspace analysis scope: dependency directories are skipped, the
	--    host limit turns the mode off, and foreign diagnostics are dropped.
	local definitions = require("user.core.lsp_definitions")
	local scoped = vim.fs.joinpath(tmp, "scoped")
	for _, relative in ipairs({
		"a.py",
		"pkg/b.py",
		"pkg/c.pyi",
		"node_modules/dep/d.py",
		".venv/lib/e.py",
		"README.md",
	}) do
		local path = vim.fs.joinpath(scoped, relative)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile({ "" }, path)
	end
	local enabled, files = definitions.workspace_scope(scoped, { py = true, pyi = true }, "basedpyright")
	assert(enabled and files == 3, ("workspace scope counted %d files, enabled=%s"):format(files, tostring(enabled)))
	local preferences = require("user.core.preferences")
	local get = preferences.get
	preferences.get = function(section)
		local values = get(section)
		if section == "runtime" then
			values.workspace_diagnostics_max_files = 2
		end
		return values
	end
	enabled, files = definitions.workspace_scope(scoped, { py = true, pyi = true }, "basedpyright")
	preferences.get = get
	assert(not enabled and files == 3, "The host limit did not keep the server in open-files mode")
	local recorded = definitions.workspace_decisions["basedpyright\0" .. scoped]
	assert(recorded and recorded.reason:find("more than 2", 1, true), vim.inspect(recorded))
	assert(
		not definitions.workspace_scope(nil, { py = true }, "basedpyright"),
		"A single-file session enabled workspace mode"
	)
	assert(definitions.project_diagnostic(scoped, scoped .. "/pkg/b.py", false), "Project file was dropped")
	assert(not definitions.project_diagnostic(scoped, "/opt/vtsls/lib/lib.es5.d.ts", false), "Foreign file was kept")
	assert(
		not definitions.project_diagnostic(scoped, scoped .. "/node_modules/dep/d.ts", false),
		"Vendored file was kept"
	)
	assert(
		definitions.project_diagnostic(scoped, "/opt/vtsls/lib/lib.es5.d.ts", true),
		"An opened foreign file was dropped"
	)

	-- 6. Protocol contract for workspace analysis: the settings table the
	--    client holds changes in place, and the pull-diagnostics capability is
	--    withheld so the server pushes for every tracked file.
	require("lazy").load({ plugins = { "nvim-lspconfig" } })
	local basedpyright = vim.lsp.config.basedpyright
	assert(type(basedpyright.before_init) == "function", "basedpyright has no before_init")
	local settings = vim.deepcopy(basedpyright.settings)
	local params = { capabilities = { textDocument = { diagnostic = { dynamicRegistration = true } } } }
	local client_config = { root_dir = scoped, settings = settings }
	basedpyright.before_init(params, client_config)
	assert(client_config.settings == settings, "before_init replaced the settings table the client holds")
	assert(
		vim.tbl_get(settings, "python", "analysis", "diagnosticMode") == "workspace"
			and vim.tbl_get(settings, "basedpyright", "analysis", "diagnosticMode") == "workspace",
		"Workspace mode was not written to both setting namespaces"
	)
	assert(params.capabilities.textDocument.diagnostic == nil, "Pull diagnostics were kept in workspace mode")
	preferences.get = function(section)
		local values = get(section)
		if section == "runtime" then
			values.workspace_diagnostics_max_files = 2
		end
		return values
	end
	settings = vim.deepcopy(basedpyright.settings)
	params = { capabilities = { textDocument = { diagnostic = { dynamicRegistration = true } } } }
	basedpyright.before_init(params, { root_dir = scoped, settings = settings })
	preferences.get = get
	assert(
		vim.tbl_get(settings, "python", "analysis", "diagnosticMode") == nil
			and params.capabilities.textDocument.diagnostic,
		"Over the limit the server must keep open-files mode and pull diagnostics"
	)
	assert(
		type(vim.lsp.config.vtsls.handlers["textDocument/publishDiagnostics"]) == "function",
		"vtsls diagnostics are not filtered to the project"
	)

	-- 7. Route selection: definitions for a filetype with a pattern, plain
	--    grep without one, the live server query once a client supports it.
	local native = require("user.core.native_search")
	local usable = native.usable
	native.usable = function()
		return true
	end
	local real_fzf = package.loaded["fzf-lua"]
	local calls = {}
	package.loaded["fzf-lua"] = {
		lsp_live_workspace_symbols = function()
			calls[#calls + 1] = "lsp"
		end,
		grep = function(opts)
			calls[#calls + 1] = "grep:" .. tostring(opts.search ~= nil and opts.no_esc == true)
		end,
		live_grep = function()
			calls[#calls + 1] = "live"
		end,
	}
	local old_ignore = vim.o.eventignore
	vim.o.eventignore = "FileType"
	vim.cmd.tabnew()
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].filetype = "python"
	assert(
		symbols.workspace({ cwd = tmp }) == "definitions" and calls[#calls] == "grep:true",
		"Python did not use definitions"
	)
	vim.bo[buf].filetype = "json"
	assert(
		symbols.workspace({ cwd = tmp }) == "grep" and calls[#calls] == "live",
		"JSON did not fall back to live grep"
	)
	local get_clients = vim.lsp.get_clients
	vim.lsp.get_clients = function()
		return {
			{
				supports_method = function()
					return true
				end,
			},
		}
	end
	assert(
		symbols.workspace({ cwd = tmp }) == "lsp" and calls[#calls] == "lsp",
		"A capable server did not get the live query"
	)
	vim.lsp.get_clients = get_clients
	native.usable = usable
	package.loaded["fzf-lua"] = real_fzf
	vim.api.nvim_buf_delete(buf, { force = true })
	vim.o.eventignore = old_ignore
	print(
		"Project check passed: tool output parsing, marker-based availability, quickfix execution, failure reporting, workspace analysis scope and protocol contract, ripgrep definition patterns and symbol routing"
	)
end
