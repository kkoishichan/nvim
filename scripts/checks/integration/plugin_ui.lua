return function()
	local plugins = require("lazy.core.config").plugins
	local plugin = require("lazy.core.plugin")
	local function opts(name)
		return plugin.values(assert(plugins[name], "missing plugin: " .. name), "opts", false)
	end
	local layout = require("user.core.layout")
	-- Plugins that read 'winborder' themselves must not override it; the rest
	-- are handed the same border explicitly.
	local function assert_default_border(border, label)
		assert(border == nil, label .. " still sets its own border")
	end
	local function assert_float_border(border, label)
		assert(border == layout.float_border(), label .. " does not follow the global float border")
	end

	local glance = plugins["glance.nvim"]
	assert(glance and glance.cmd == "Glance", "Glance peek UI is missing or not lazy-loaded")
	do
		-- The peek draws its own lines: top and bottom from Glance, and a
		-- native left border on the list, including its empty rows and winbar.
		require("lazy").load({ plugins = { "glance.nvim" } })
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/peek.lua")
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(
			buf,
			0,
			-1,
			false,
			{ "local function area(w, h)", "\treturn w * h", "end", "print(area(1, 2))" }
		)
		vim.cmd("noautocmd setlocal filetype=lua")
		local uri = vim.uri_from_bufnr(buf)
		local client_id = assert(vim.lsp.start({
			name = "peek_fixture",
			root_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":h"),
			cmd = function(dispatchers)
				local closing, id = false, 0
				return {
					request = function(method, _, callback)
						id = id + 1
						local result = vim.NIL
						if method == "initialize" then
							result = { capabilities = { textDocumentSync = 1, referencesProvider = true } }
						elseif method == "textDocument/references" then
							result = {
								{
									uri = uri,
									range = {
										start = { line = 0, character = 15 },
										["end"] = { line = 0, character = 19 },
									},
								},
								{
									uri = uri,
									range = {
										start = { line = 3, character = 6 },
										["end"] = { line = 3, character = 10 },
									},
								},
							}
						end
						vim.schedule(function()
							callback(nil, result)
						end)
						return true, id
					end,
					notify = function(method)
						if method == "exit" and not closing then
							closing = true
							vim.schedule(function()
								dispatchers.on_exit(0, 0)
							end)
						end
						return true
					end,
					is_closing = function()
						return closing
					end,
					terminate = function() end,
				}
			end,
		}, { bufnr = buf }))
		local client = assert(vim.lsp.get_client_by_id(client_id))
		assert(
			vim.wait(2000, function()
				return client.initialized and vim.lsp.buf_is_attached(buf, client_id)
			end),
			"Peek fixture server did not attach"
		)
		vim.api.nvim_win_set_cursor(0, { 1, 16 })
		local function open_peek(command)
			vim.cmd(command or "Glance references")
			local list
			assert(
				vim.wait(3000, function()
					for _, winid in ipairs(vim.api.nvim_list_wins()) do
						if vim.bo[vim.api.nvim_win_get_buf(winid)].filetype == "Glance" then
							list = winid
							return true
						end
					end
				end, 50),
				"Glance did not open its list"
			)
			vim.wait(100)
			-- A theme reload between opens leaves the grid stale; draw it in full.
			vim.cmd("redraw!")
			return list
		end
		local function close_peek(list)
			require("glance").actions.close()
			assert(
				vim.wait(1000, function()
					return not vim.api.nvim_win_is_valid(list)
				end),
				"Peek did not close"
			)
		end
		-- Opaque: two fills, no lines, no separator column.
		local list = open_peek()
		local list_width = vim.api.nvim_win_get_width(list)
		assert(vim.wo[list].foldcolumn == "0" and vim.wo[list].statuscolumn == "", "Opaque peek draws a separator")
		assert(not vim.wo[list].winbar:find("GlanceListSeparator", 1, true), "Opaque peek winbar has a separator")
		assert(vim.api.nvim_win_get_config(list).border == "none", "Opaque peek draws lines")
		close_peek(list)
		-- Transparent: no fill, lines above and below, a separator before the list.
		local transparency = require("user.core.transparency")
		local notify = vim.notify
		vim.notify = function() end
		transparency.toggle()
		list = open_peek()
		assert(vim.wo[list].foldcolumn == "0" and vim.wo[list].statuscolumn == "", "Peek still uses a partial column")
		assert(not vim.wo[list].winbar:find("GlanceListSeparator", 1, true), "Peek still patches its winbar")
		assert(vim.api.nvim_win_get_width(list) + 1 == list_width, "Peek separator changed the panel footprint")
		assert(
			vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(list)) < vim.api.nvim_win_get_height(list),
			"Peek fixture has no empty rows to cover"
		)
		local border = vim.api.nvim_win_get_config(list).border
		assert(type(border) == "table" and border[2][1] == "─", "Transparent peek has no top line")
		assert(border[6][1] == "─", "Transparent peek has no bottom line")
		assert(border[8][1] == "│", "Transparent peek has no full-height separator")
		assert(border[1][1] == "┬" and border[7][1] == "┴", "Peek separator does not join its horizontal lines")
		close_peek(list)
		list = open_peek("Glance resume")
		assert(vim.api.nvim_win_get_config(list).border[8][1] == "│", "Resumed peek lost its separator")
		assert(vim.api.nvim_win_get_width(list) + 1 == list_width, "Resumed peek shrank its list again")
		close_peek(list)
		transparency.toggle()
		vim.notify = notify
		assert(
			require("glance.config").options.border.enable == false,
			"Peek lines stayed on after returning to opaque"
		)
		client:stop(true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	local neo_tree_opts = opts("neo-tree.nvim")
	assert(neo_tree_opts.auto_clean_after_session_restore, "Neo-tree cannot clean legacy session buffers")
	local neo_tree_session_cleanup = vim.api.nvim_get_autocmds({
		group = "user_neotree_session_cleanup",
		event = "SessionLoadPost",
	})
	assert(#neo_tree_session_cleanup == 1, "Legacy Neo-tree session cleanup is not registered")
	assert(neo_tree_opts.enable_git_status, "neo-tree Git status is disabled")
	assert(neo_tree_opts.enable_diagnostics, "neo-tree diagnostics are disabled")
	assert(neo_tree_opts.filesystem.use_libuv_file_watcher, "neo-tree file watcher is disabled")
	local gitsigns_opts = opts("gitsigns.nvim")
	assert(gitsigns_opts.current_line_blame, "current-line Git blame is disabled")
	for _, signs in ipairs({ gitsigns_opts.signs, gitsigns_opts.signs_staged }) do
		for _, kind in ipairs({ "add", "change", "changedelete" }) do
			assert(signs[kind].text == "┃", "Gitsigns " .. kind .. " marker is not a centred heavy bar")
		end
	end
	assert_default_border(gitsigns_opts.preview_config.border, "Gitsigns previews")
	assert(
		gitsigns_opts.preview_config.row == 1 and gitsigns_opts.preview_config.col == 0,
		"Gitsigns preview is misplaced"
	)
	assert_default_border(vim.diagnostic.config().float.border, "Diagnostic floats")
	local ufo_opts = opts("nvim-ufo")
	assert_float_border(ufo_opts.preview.win_config.border, "Fold previews")
	assert(ufo_opts.preview.win_config.winblend == 0, "Fold previews are translucent")
	assert(ufo_opts.preview.mappings.close == "q", "Fold previews lost their original q mapping")
	assert_float_border(opts("outline.nvim").preview_window.border, "Outline previews")
	assert_float_border(opts("nvim-bqf").preview.border, "Quickfix previews")
	assert(opts("nvim-bqf").preview.winblend == 0, "Quickfix previews are translucent")
	assert_float_border(opts("nvim-dap-ui").floating.border, "DAP eval floats")
	assert_float_border(opts("crates.nvim").popup.border, "Crates popups")
	local snacks_opts = opts("snacks.nvim")
	assert_default_border(snacks_opts.styles.input.border, "vim.ui.input")
	assert(
		vim.deep_equal(snacks_opts.styles.input.keys.i_esc[2], { "cmp_close", "cancel" }),
		"vim.ui.input still needs two Escape presses"
	)
	assert(snacks_opts.styles.notification == nil, "Snacks notifier is disabled but still styled")
	assert_float_border(opts("which-key.nvim").win.border, "Which-key")
	local which_key_green = vim.api.nvim_get_hl(0, { name = "WhichKeyIconGreen", link = false }).fg
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg
	assert(which_key_green ~= comment, "Which-key green icons still inherit the VS Code comment green")
	assert(
		which_key_green == require("user.core.palette").get().dim,
		"Which-key green icons are not using the neutral popup colour"
	)
end
