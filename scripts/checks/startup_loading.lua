return function(tmp)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local directory = tmp .. "/directory with spaces"
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "original file", "second line" }, directory .. "/original.txt")
	vim.fn.writefile({ "listed file" }, directory .. "/listed.txt")
	local cases = {
		empty = {
			code = [[
assert(not package.loaded.oil, "An empty startup eagerly loaded Oil")
assert(vim.fn.exists(":Oil") == 2, "Oil's command is unavailable before first use")
assert(vim.fn.maparg("-", "n") ~= "", "Oil's directory mapping is unavailable")
assert(vim.fn.maparg("<leader>E", "n") ~= "", "Oil's project mapping is unavailable")
]],
		},
		file_then_edit = {
			argument = directory .. "/original.txt",
			code = [[
assert(not package.loaded.oil, "Opening a text file eagerly loaded Oil")
local original = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd.edit(vim.fn.fnameescape(directory))
check_oil()
require("oil").close()
assert(vim.api.nvim_get_current_buf() == original, "Oil did not return to the original file")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "Oil lost the original cursor")
]],
		},
		badd = {
			argument = directory .. "/original.txt",
			code = [[
local original = vim.api.nvim_get_current_buf()
vim.cmd.badd(vim.fn.fnameescape(directory))
assert(vim.api.nvim_get_current_buf() == original, "Adding a hidden directory stole focus")
assert(package.loaded.oil, "A hidden directory did not initialize Oil's explorer handling")
local hidden
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(buf):match("^oil://") then hidden = buf end
end
assert(hidden, "The hidden directory was not recognized by Oil")
vim.cmd.buffer(hidden)
check_oil()
require("oil").close()
assert(vim.api.nvim_get_current_buf() == original, "Hidden directory lost the original file")
]],
		},
		directory_argument = { argument = directory, code = "check_oil()" },
		uri_argument = { argument = "oil://" .. directory .. "/", code = "check_oil()" },
		command = {
			argument = directory .. "/original.txt",
			code = [[
local windows = #vim.api.nvim_list_wins()
vim.cmd("vertical Oil " .. vim.fn.fnameescape(directory))
check_oil()
assert(#vim.api.nvim_list_wins() == windows + 1, "Oil command lost its split modifier")
]],
		},
		mapping = {
			argument = directory .. "/original.txt",
			code = [[
vim.api.nvim_feedkeys("-", "xt", false)
check_oil()
]],
		},
		session = {
			code = [[
vim.cmd("Oil " .. vim.fn.fnameescape(directory))
check_oil()
-- The current session policy excludes unlisted nofile buffers. Exercise an
-- older session that includes Oil by retaining blank windows only in this child.
vim.opt.sessionoptions:append("blank")
vim.cmd.mksession({ args = { session }, bang = true })
]],
		},
	}
	local function run(name, case)
		local child = tmp .. "/startup_" .. name
		vim.fn.mkdir(child, "p")
		local script = child .. "/check.lua"
		local prelude = string.format(
			[[
local directory, session = %q, %q
local function check_oil()
  assert(vim.wait(5000, function()
    return vim.bo.filetype == "oil" and vim.bo.modifiable
      and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("listed.txt", 1, true)
  end, 10), "Oil did not display the real directory listing: " .. vim.api.nvim_buf_get_name(0))
  assert(vim.api.nvim_buf_get_name(0):match("^oil://"), "Directory was not handled by Oil")
end
vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function()
  vim.schedule(function()
    local ok, err = xpcall(function()
      assert(vim.v.errmsg == "", vim.v.errmsg)
]],
			directory,
			tmp .. "/oil-session.vim"
		)
		local ending = [[
      require("user.core.oil_registration").setup()
      require("user.core.oil_registration").setup()
      assert(#vim.api.nvim_get_autocmds({ group = "user_oil_registration" }) <= 2,
        "Reloaded directory registration duplicated autocmds")
    end, debug.traceback)
    if not ok then vim.api.nvim_err_writeln(err); vim.cmd.cquit() else vim.cmd("qa!") end
  end)
end })
]]
		vim.fn.writefile(vim.split(prelude .. case.code .. ending, "\n", { plain = true }), script)
		local argv = { vim.v.progpath, "--headless", "-u", root .. "/init.lua", "-i", "NONE" }
		vim.list_extend(argv, { "--cmd", "lua vim.opt.runtimepath:prepend(vim.env.NVIM_TEST_ROOT)" })
		vim.list_extend(argv, { "-c", "lua dofile(vim.env.NVIM_STARTUP_CHECK)" })
		if case.argument then
			argv[#argv + 1] = case.argument
		end
		if case.session then
			vim.list_extend(argv, { "-S", tmp .. "/oil-session.vim" })
		end
		local result = vim.system(argv, {
			text = true,
			env = {
				NVIM_STARTUP_CHECK = script,
				XDG_CACHE_HOME = child .. "/cache",
				XDG_STATE_HOME = child .. "/state",
				NVIM_LOG_FILE = child .. "/nvim.log",
			},
		}):wait(15000)
		assert(result.code == 0, name .. " startup failed:\n" .. (result.stderr or "") .. (result.stdout or ""))
	end
	for _, name in ipairs({
		"empty",
		"file_then_edit",
		"badd",
		"directory_argument",
		"uri_argument",
		"command",
		"mapping",
		"session",
	}) do
		run(name, cases[name])
	end
	-- Restore the session in a fresh process where Oil has never loaded.
	-- A directory URI in the session must activate the same public read handler.
	run("session_restore", { session = true, code = "check_oil()" })
	print(
		"Startup loading evidence: Oil stays unloaded for empty/text startup; native directory, URI, hidden buffer, command, mapping and session paths passed"
	)
end
