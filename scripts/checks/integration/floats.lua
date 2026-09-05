return function()
	do
		local float_style = require("user.core.float_style")
		local function open_float(bufnr, width, height, border)
			return vim.api.nvim_open_win(bufnr, false, {
				relative = "editor",
				row = 1,
				col = 1,
				width = width,
				height = height,
				border = border or "rounded",
				style = "minimal",
			})
		end

		local small_buffer = vim.api.nvim_create_buf(false, true)
		local small = open_float(small_buffer, 24, 4)
		require("user.core.window_roles").mark(small, "transient")
		vim.wo[small].winhighlight = "Normal:ErrorMsg,CursorLine:Visual"
		assert(
			vim.wait(200, function()
				return float_style.is_padded(small)
			end),
			"small third-party float was not restyled"
		)
		assert(vim.wo[small].winhighlight:find("Normal:Pmenu", 1, true), "small float body does not use Pmenu")
		assert(vim.wo[small].winhighlight:find("FloatBorder:Pmenu", 1, true), "small float padding does not use Pmenu")
		assert(
			vim.wo[small].winhighlight:find("CursorLine:Visual", 1, true),
			"popup styling discarded a plugin highlight"
		)
		assert(float_style.is_transient(small), "small third-party float is not dismissible")

		local large_buffer = vim.api.nvim_create_buf(false, true)
		local large_width = math.max(1, vim.o.columns - 4)
		local large_height = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
		local large = open_float(large_buffer, large_width, large_height)
		require("user.core.window_roles").mark(large, "editor_float")
		vim.wait(50)
		assert(not float_style.is_padded(large), "application-sized float was mistaken for a popup")
		assert(not float_style.is_transient(large), "application-sized float is dismissible")

		local panel_buffer = vim.api.nvim_create_buf(false, true)
		vim.bo[panel_buffer].filetype = "Glance"
		local panel = open_float(panel_buffer, 24, 4)
		vim.wait(50)
		assert(not float_style.is_padded(panel), "small Glance pane lost its dedicated layout")
		assert(not float_style.is_transient(panel), "Glance application pane is dismissible as a popup")

		local popup_buffer = vim.api.nvim_create_buf(false, true)
		vim.bo[popup_buffer].filetype = "neo-tree-popup"
		local popup = open_float(popup_buffer, large_width, 4)
		assert(
			vim.wait(200, function()
				return float_style.is_padded(popup)
			end),
			"Neo-tree dialog fallback was not applied"
		)
		assert(float_style.is_transient(popup), "known large dialog is not dismissible")

		local notification_buffer = vim.api.nvim_create_buf(false, true)
		local notification = open_float(notification_buffer, 24, 4)
		vim.bo[notification_buffer].filetype = "notify"
		vim.wait(50)
		assert(not float_style.is_padded(notification), "generic popup styling changed nvim-notify")
		assert(not float_style.is_transient(notification), "notification bypasses its lifecycle-aware closer")

		local context_buffer = vim.api.nvim_create_buf(false, true)
		local context = open_float(context_buffer, 24, 2)
		vim.w[context].treesitter_context = true
		local scroll_buffer = vim.api.nvim_create_buf(false, true)
		local scroll = open_float(scroll_buffer, 1, 4)
		vim.w[scroll].scrollview_key = "scrollview_val"
		vim.wait(50)
		assert(not float_style.is_transient(context), "Tree-sitter Context was mistaken for a popup")
		assert(not float_style.is_transient(scroll), "scrollview rail was mistaken for a popup")

		local layout = require("user.core.layout")
		local lazy_buffer = vim.api.nvim_create_buf(false, true)
		local lazy_window = open_float(lazy_buffer, 30, 6, layout.manager_border)
		vim.bo[lazy_buffer].filetype = "lazy"
		local mason_buffer = vim.api.nvim_create_buf(false, true)
		local mason_window = open_float(mason_buffer, 50, 10, layout.manager_border)
		vim.bo[mason_buffer].filetype = "mason"
		assert(
			vim.wait(200, function()
				local lazy_config = vim.api.nvim_win_get_config(lazy_window)
				local mason_config = vim.api.nvim_win_get_config(mason_window)
				return lazy_config.width == mason_config.width
					and lazy_config.height == mason_config.height
					and lazy_config.row == mason_config.row
					and lazy_config.col == mason_config.col
			end),
			"Lazy and Mason manager rectangles still differ"
		)

		local backdrop_buffer = vim.api.nvim_create_buf(false, true)
		local backdrop = open_float(backdrop_buffer, 30, 6)
		vim.bo[backdrop_buffer].filetype = "lazy_backdrop"
		local backdrop_config = vim.api.nvim_win_get_config(backdrop)
		assert(backdrop_config.border == "none", "Lazy backdrop inherited the global window border")
		assert(
			backdrop_config.row == 0
				and backdrop_config.col == 0
				and backdrop_config.width == vim.o.columns
				and backdrop_config.height == vim.o.lines,
			"Lazy backdrop no longer covers the viewport exactly"
		)

		local notify = package.loaded.notify
		local dismiss = notify and notify.dismiss
		local notification_dismissed = false
		if notify then
			notify.dismiss = function(...)
				notification_dismissed = true
				return dismiss(...)
			end
		end
		assert(require("user.core.popups").close(), "unified popup closer found no transient windows")
		if notify then
			notify.dismiss = dismiss
		end
		assert(not notification_dismissed, "Escape dismissed an auto-expiring notification")
		assert(not vim.api.nvim_win_is_valid(small), "Escape fallback left a small popup open")
		assert(not vim.api.nvim_win_is_valid(popup), "Escape fallback left a known dialog open")
		for label, winid in pairs({
			application = large,
			context = context,
			glance = panel,
			notification = notification,
			scrollview = scroll,
		}) do
			assert(vim.api.nvim_win_is_valid(winid), "popup closer incorrectly closed " .. label)
		end

		for _, winid in ipairs({
			small,
			large,
			panel,
			popup,
			notification,
			context,
			scroll,
			lazy_window,
			mason_window,
			backdrop,
		}) do
			if vim.api.nvim_win_is_valid(winid) then
				vim.api.nvim_win_close(winid, true)
			end
		end
	end
end
