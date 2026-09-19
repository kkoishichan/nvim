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
		directory_then_explorer = {
			argument = directory,
			code = [[
check_oil()
local oil_buffer = vim.api.nvim_get_current_buf()
for _ = 1, 2 do
  check_explorer(directory, "listed.txt")
  vim.api.nvim_feedkeys(vim.g.mapleader .. "e", "xt", false)
  vim.wait(200)
  assert(vim.api.nvim_get_current_buf() == oil_buffer, "Closing the tree lost the Oil buffer")
end
local nested = directory .. "/nested child"
vim.fn.mkdir(nested, "p")
vim.fn.writefile({ "nested file" }, nested .. "/nested.txt")
vim.cmd.edit(vim.fn.fnameescape(nested))
assert(vim.wait(5000, function()
  return vim.bo.filetype == "oil" and vim.bo.modifiable
    and require("oil").get_current_dir() == nested .. "/"
end, 10), "Opening a nested directory stopped using Oil after loading the tree")
check_explorer(nested, "nested.txt")
]],
		},
		file_oil_then_explorer = {
			argument = directory .. "/original.txt",
			code = [[
local original = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_feedkeys("-", "xt", false)
check_oil()
check_explorer(directory, "listed.txt")
vim.api.nvim_feedkeys(vim.g.mapleader .. "e", "xt", false)
vim.wait(200)
require("oil").close()
assert(vim.api.nvim_get_current_buf() == original, "The tree broke Oil's return to the original file")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "The tree broke Oil's saved cursor")
check_explorer(directory, "original.txt", directory .. "/original.txt")
]],
		},
		explorer_then_oil = {
			argument = directory .. "/original.txt",
			code = [[
assert(not package.loaded.oil, "Oil loaded before the first directory")
local editor = vim.api.nvim_get_current_win()
vim.cmd.cd(vim.fn.fnameescape(directory))
local tree = check_explorer(directory, "original.txt", directory .. "/original.txt")
assert(not package.loaded.oil, "Opening the tree eagerly loaded Oil")
vim.api.nvim_set_current_win(editor)
vim.cmd.edit(vim.fn.fnameescape(directory))
check_oil()
vim.wait(200)
assert(vim.api.nvim_win_is_valid(tree), "Entering Oil closed the existing sidebar")
assert(vim.bo[vim.api.nvim_win_get_buf(tree)].filetype == "neo-tree", "Oil replaced the sidebar")
vim.api.nvim_feedkeys(vim.g.mapleader .. "e", "xt", false)
vim.wait(200)
assert(not vim.api.nvim_win_is_valid(tree), "Oil could not toggle the existing tree closed")
check_explorer(directory, "listed.txt")
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
local explorer_errors, notify = {}, vim.notify
vim.notify = function(message, level, ...)
  if level and level >= vim.log.levels.ERROR then
    explorer_errors[#explorer_errors + 1] = tostring(message)
  end
  return notify(message, level, ...)
end
local function check_explorer(path, filename, selected)
  vim.api.nvim_feedkeys(vim.g.mapleader .. "e", "xt", false)
  assert(vim.wait(5000, function() return vim.bo.filetype == "neo-tree" end, 10),
    "Explorer did not open: " .. table.concat(explorer_errors, "\n"))
  -- Allow delayed layout enforcement and file-following to settle; a momentary
  -- tree window is insufficient if the panel budget immediately closes it.
  vim.wait(200)
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  assert(state.winid and vim.api.nvim_win_is_valid(state.winid), "Explorer closed after rendering")
  assert(vim.bo.filetype == "neo-tree", "Explorer failed to retain focus")
  assert(vim.fs.normalize(state.path) == vim.fs.normalize(path), "Explorer opened the wrong directory: " .. state.path)
  assert(table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n"):find(filename, 1, true),
    "Explorer did not list the requested directory")
  if selected then
    assert(state.tree:get_node():get_id() == selected, "Explorer stopped revealing the current file")
  end
  assert(vim.v.errmsg == "", vim.v.errmsg)
  assert(#explorer_errors == 0, table.concat(explorer_errors, "\n"))
  return state.winid
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
		"directory_then_explorer",
		"file_oil_then_explorer",
		"explorer_then_oil",
		"session",
	}) do
		run(name, cases[name])
	end
	-- Restore the session in a fresh process where Oil has never loaded.
	-- A directory URI in the session must activate the same public read handler.
	run("session_restore", { session = true, code = "check_oil()" })
	print(
		"Startup loading evidence: Oil stays unloaded for empty/text startup; directory, URI, hidden buffer, command, mapping, explorer coexistence and session paths passed"
	)
end
