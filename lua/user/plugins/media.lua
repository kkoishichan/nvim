local function has_ui()
	return #vim.api.nvim_list_uis() > 0
end

local function toggle_images()
	local image = require("image")
	if image.is_enabled() then
		image.disable()
		vim.notify("Images disabled", vim.log.levels.INFO, { title = "Images" })
	else
		image.enable()
		vim.notify("Images enabled", vim.log.levels.INFO, { title = "Images" })
	end
end

return {
	{
		"3rd/image.nvim",
		cond = has_ui,
		event = {
			"BufReadPre *.avif",
			"BufReadPre *.bmp",
			"BufReadPre *.gif",
			"BufReadPre *.jpeg",
			"BufReadPre *.jpg",
			"BufReadPre *.png",
			"BufReadPre *.svg",
			"BufReadPre *.webp",
		},
		ft = { "markdown", "quarto", "rmd", "typst" },
		cmd = "ImageReport",
		build = false,
		opts = {
			backend = "kitty",
			processor = "magick_cli",
			integrations = {
				markdown = {
					enabled = true,
					clear_in_insert_mode = false,
					download_remote_images = false,
					only_render_image_at_cursor = false,
					only_render_image_at_cursor_mode = "popup",
					floating_windows = false,
					filetypes = { "markdown", "quarto", "rmd" },
				},
				typst = {
					enabled = true,
					filetypes = { "typst" },
				},
				asciidoc = {
					enabled = false,
				},
				neorg = {
					enabled = false,
				},
				rst = {
					enabled = false,
				},
				html = {
					enabled = false,
				},
				css = {
					enabled = false,
				},
			},
			max_width_window_percentage = 80,
			max_height_window_percentage = 60,
			window_overlap_clear_enabled = true,
			window_overlap_clear_ft_ignore = {
				"cmp_menu",
				"cmp_docs",
				"fzf",
				"fzflua_backdrop",
				"neo-tree",
				"snacks_notif",
				"snacks_picker_input",
				"which-key",
			},
			hijack_file_patterns = {
				"*.png",
				"*.jpg",
				"*.jpeg",
				"*.gif",
				"*.webp",
				"*.avif",
				"*.bmp",
				"*.svg",
			},
		},
		keys = {
			{
				"<leader>mI",
				toggle_images,
				desc = "Images toggle",
			},
			{
				"<leader>mr",
				"<cmd>ImageReport<cr>",
				desc = "Image report",
			},
		},
	},
}
