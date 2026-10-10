-- Quiet pauses every loaded decoration layer through its public entry and
-- restores exactly the previous state; a layer the user had already switched
-- off is left alone, and toggling is idempotent.
return function()
	local api = vim.api
	local quiet = require("user.core.quiet")
	local diagnostics = require("user.core.diagnostics")
	require("lazy").load({
		plugins = {
			"vim-matchup",
			"vim-illuminate",
			"indent-blankline.nvim",
			"nvim-highlight-colors",
			"todo-comments.nvim",
			"nvim-scrollview",
			"gitsigns.nvim",
		},
	})
	vim.cmd.tabnew()
	local buf = api.nvim_get_current_buf()
	api.nvim_buf_set_lines(buf, 0, -1, false, { "local value = compute(alpha, beta)", "return value" })
	vim.bo[buf].filetype = "lua"
	vim.wait(200, function()
		return false
	end, 10)

	local engine = require("illuminate.engine")
	local ibl_config = require("ibl.config")
	local todo = require("todo-comments.highlight")
	local gitsigns_config = require("gitsigns.config").config
	assert(vim.fn.exists(":NoMatchParen") == 2, "match-up did not initialise")
	assert(not engine.is_paused() and vim.g.scrollview_enabled, "Fixture started with layers already off")
	assert(diagnostics.current() == "lines", "Extra did not start with expanded diagnostics")
	assert(gitsigns_config.current_line_blame, "Extra did not start with line blame")

	-- A layer the user already turned off is not touched by quiet.
	engine.pause()

	local paused = quiet.enable()
	assert(quiet.active(), "Quiet did not activate")
	local names = table.concat(paused, ",")
	for _, expected in ipairs({
		"matchup",
		"indent lines",
		"todo comments",
		"scrollbar",
		"line blame",
		"expanded diagnostics",
	}) do
		assert(names:find(expected, 1, true), "Quiet did not pause " .. expected .. " (" .. names .. ")")
	end
	assert(not names:find("illuminate", 1, true), "Quiet claimed a layer that was already off")
	assert(vim.g.matchup_matchparen_enabled == 0, "match-up still highlights")
	assert(not ibl_config.get_config(buf).enabled, "indent lines still draw")
	assert(not todo.enabled, "todo comments still highlight")
	assert(not vim.g.scrollview_enabled, "scrollbar still refreshes")
	assert(not gitsigns_config.current_line_blame, "line blame still runs")
	assert(diagnostics.current() == "text", "expanded diagnostics were not lowered")
	assert(#quiet.enable() == #paused, "A second enable changed the paused set")

	local restored = quiet.disable()
	assert(not quiet.active() and #restored == #paused, "Quiet did not restore every layer")
	assert(vim.g.matchup_matchparen_enabled == 1, "match-up was not restored")
	assert(ibl_config.get_config(buf).enabled, "indent lines were not restored")
	assert(todo.enabled, "todo comments were not restored")
	assert(vim.g.scrollview_enabled, "scrollbar was not restored")
	assert(gitsigns_config.current_line_blame, "line blame was not restored")
	assert(diagnostics.current() == "lines", "expanded diagnostics were not restored")
	assert(engine.is_paused(), "Quiet resumed a layer the user had paused")
	engine.resume()
	assert(#quiet.disable() == 0, "Disabling an inactive quiet restored something")

	-- Command, mapping and report surface.
	assert(vim.fn.exists(":Quiet") == 2 and vim.fn.maparg("<leader>uq", "n") ~= "", "Quiet entry points are missing")
	vim.cmd("Quiet on")
	local echoed = {}
	local echo = api.nvim_echo
	api.nvim_echo = function(chunks, ...)
		for _, chunk in ipairs(chunks) do
			echoed[#echoed + 1] = chunk[1]
		end
		return echo(chunks, ...)
	end
	vim.cmd.ModeInfo()
	api.nvim_echo = echo
	assert(table.concat(echoed):find("quiet%s+on: "), "ModeInfo does not report the quiet session")
	vim.cmd("Quiet off")
	assert(not quiet.active(), ":Quiet off did not end the session")
	api.nvim_buf_delete(buf, { force = true })
	print(
		"Quiet passed: pause and exact restore of seven layers, respect for layers already off, idempotent toggle, command and ModeInfo"
	)
end
