return function()
	assert(require("user.core.theme").saved() == "vscode", "default theme is not vscode")
	assert(vim.g.colors_name == "vscode", "vscode was not applied at startup")
	do
		local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
		local snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstop", link = false })
		local active_snippet = vim.api.nvim_get_hl(0, { name = "SnippetTabstopActive", link = true })
		assert(visual.bg == 0x264f78, "vscode Visual selection colour was overridden")
		assert(
			snippet.bg == require("user.core.palette").get().subtle and snippet.fg == nil,
			"Native snippet placeholders are not using the theme-derived neutral grey"
		)
		assert(snippet.bg ~= visual.bg, "Native snippet placeholders still inherit Visual")
		assert(active_snippet.link == "SnippetTabstop", "Active snippet placeholder does not inherit snippet grey")
	end
	assert(vim.o.shada:match("<0"), "ShaDa still persists register contents")
	assert(
		not vim.tbl_contains(vim.opt.sessionoptions:get(), "blank"),
		"Sessions still serialize plugin panels as ordinary file buffers"
	)
	assert(vim.tbl_contains(vim.opt.sessionoptions:get(), "buffers"), "Sessions no longer preserve hidden file buffers")
	assert(vim.g.user_lsp_preview_patched == nil, "LSP floating-preview API was monkeypatched")
	assert(
		type(vim.fn.maparg("<Esc>", "n", false, true).callback) == "function",
		"Normal Escape is not a semantic popup closer"
	)
	assert(
		type(vim.fn.maparg("<Esc>", "x", false, true).callback) == "function",
		"Visual Escape is not a semantic popup closer"
	)

	do
		local plugins = require("lazy.core.config").plugins
		local edgy = plugins["edgy.nvim"]
		local codex
		for _, panel in ipairs(edgy.opts.right) do
			if panel.title == "Codex" then
				codex = panel
				break
			end
		end
		assert(codex and codex.ft == "toggleterm", "Codex is not docked as a toggleterm panel")

		require("lazy").load({ plugins = { "bufferline.nvim" } })
		local bufferline_opts = require("lazy.core.plugin").values(plugins["bufferline.nvim"], "opts", false)
		local options = bufferline_opts.options
		assert(options.numbers == "none", "Bufferline numbers are still visible")
		assert(options.indicator.style == "none", "Current Bufferline item still has an indicator")
		-- Lazy caches the resolved opts and bufferline's setup replaces the
		-- highlights function with the table it produced from the palette.
		assert(type(plugins["bufferline.nvim"].opts) == "function", "Bufferline opts are not built at load time")
		assert(type(bufferline_opts.highlights) == "table", "Bufferline highlights were not derived")
		-- A tab is icon, name and modified mark; problems colour the name only.
		assert(options.diagnostics_indicator(0, 0, { error = 1, warning = 2 }) == "", "Bufferline shows counts on tabs")
		assert(not options.always_show_bufferline, "The tab bar is shown for a single buffer")
		assert(options.sort_by == "insert_after_current", "New buffers do not open beside the current one")
		assert(type(options.middle_mouse_command) == "function", "Middle click does not close a tab")
		assert(type(options.custom_filter) == "function", "Tabs are not filtered by workspace")
		assert(type(options.custom_areas.right) == "function", "The workspace label is missing")
		assert(options.offsets[1].text == "Explorer", "The sidebar title is missing")
		assert(vim.fn.maparg("<M-1>", "n") == "", "Ordinal buffer jumps are still mapped")

		-- Each tab's bar lists its own workspace's files and names the workspace.
		local project = require("user.core.project")
		local root_a = vim.fn.tempname()
		local root_b = vim.fn.tempname()
		vim.fn.mkdir(root_a .. "/.git", "p")
		vim.fn.mkdir(root_b .. "/.git", "p")
		vim.fn.writefile({ "a" }, root_a .. "/alpha.lua")
		vim.fn.writefile({ "b" }, root_b .. "/beta.lua")
		local function bar()
			vim.cmd.redrawtabline()
			return vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
		end
		vim.cmd.tabnew()
		project.set(root_a)
		vim.cmd.edit(root_a .. "/alpha.lua")
		local alpha = vim.api.nvim_get_current_buf()
		vim.cmd.tabnew()
		project.set(root_b)
		vim.cmd.edit(root_b .. "/beta.lua")
		local beta = vim.api.nvim_get_current_buf()
		local text = bar()
		assert(
			text:find("beta.lua", 1, true) and not text:find("alpha.lua", 1, true),
			"Tab bar shows another workspace's files: " .. text
		)
		-- The bar shows only when this workspace has more than one buffer;
		-- the other tab's file is not counted here, unbound buffers are.
		local tabbar = require("user.core.tabbar")
		assert(tabbar.belongs(beta) and not tabbar.belongs(alpha), "Workspace membership is wrong")
		local function visibility_matches(label)
			vim.wait(100)
			local expected = tabbar.count() > 1 and 2 or 0
			assert(
				vim.o.showtabline == expected,
				label .. ": showtabline " .. vim.o.showtabline .. " for " .. tabbar.count()
			)
		end
		local before = tabbar.count()
		visibility_matches("one workspace file")
		vim.fn.writefile({ "b2" }, root_b .. "/gamma.lua")
		vim.cmd.edit(root_b .. "/gamma.lua")
		local gamma = vim.api.nvim_get_current_buf()
		assert(tabbar.count() == before + 1, "A second workspace file was not counted")
		visibility_matches("two workspace files")
		assert(vim.o.showtabline == 2, "Tab bar is hidden with two workspace buffers")
		-- Leave the file before closing it, or Neovim fills the window with a
		-- new unnamed buffer, which belongs to the tab and counts.
		vim.cmd.buffer(beta)
		vim.api.nvim_buf_delete(gamma, { force = true })
		assert(tabbar.count() == before, "A closed workspace file is still counted")
		visibility_matches("second file closed")
		local tabs = #vim.api.nvim_list_tabpages()
		assert(
			text:find(vim.fs.basename(root_b) .. " " .. tabs .. "/" .. tabs, 1, true),
			"Tab bar does not name the workspace and tab position: " .. text
		)
		vim.cmd.tabprevious()
		text = bar()
		assert(
			text:find("alpha.lua", 1, true) and not text:find("beta.lua", 1, true),
			"Tab bar did not follow the workspace: " .. text
		)
		assert(text:find(vim.fs.basename(root_a), 1, true), "Tab bar lost the workspace name: " .. text)
		vim.cmd.tabclose()
		vim.cmd.tabclose()
		for _, bufnr in ipairs({ alpha, beta }) do
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		vim.fn.delete(root_a, "rf")
		vim.fn.delete(root_b, "rf")
	end
end
