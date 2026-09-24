return function()
	local api = vim.api
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	-- The UI-only spec is intentionally disabled in this headless check.
	local plugin_dir = vim.fs.joinpath(require("lazy.core.config").options.root, "image.nvim")
	vim.opt.rtp:prepend(plugin_dir)
	-- Use the actual renderer, virtual lines and float masking. Only terminal
	-- pixels and source dimensions are simulated, so CI needs no Kitty/Magick.
	local backend = { features = { crop = true } }
	function backend.setup(state)
		backend.state = state
	end
	function backend.render(image)
		image.is_rendered = true
		backend.state.images[image.id] = image
	end
	function backend.clear(id, shallow)
		for name, image in pairs(backend.state.images) do
			if not id or id == name then
				image.is_rendered = false
				if not shallow then
					backend.state.images[name] = nil
				end
			end
		end
	end
	package.loaded["image/backends/kitty"] = backend
	package.loaded["image/utils/term"] = {
		get_size = function()
			return { cell_width = 8, cell_height = 16, screen_cols = vim.o.columns, screen_rows = vim.o.lines }
		end,
	}
	package.loaded["image/processors/magick_cli"] = {
		get_format = function()
			return "png"
		end,
		get_dimensions = function()
			return { width = 160, height = 160 }
		end,
	}
	local opts = dofile(root .. "/lua/user/plugins/media.lua")[1].opts
	for _, name in ipairs({ "markdown", "typst", "asciidoc", "neorg", "syslang", "html", "css", "org", "rst" }) do
		opts.integrations[name] = { enabled = false }
	end
	-- Keep unrelated configuration events out of this isolated layout fixture.
	vim.o.eventignore = "all"
	vim.o.laststatus, vim.o.showtabline = 0, 0
	vim.cmd("enew!")
	vim.wo.winbar = ""
	vim.wo.foldenable, vim.wo.wrap = false, false
	vim.wo.scrolloff, vim.wo.smoothscroll = 8, true
	local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
	local lines = {}
	for i = 1, 120 do
		lines[i] = "Document line " .. i
	end
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local image = require("image")
	image.setup(opts)
	local picture = assert(
		image.from_file(plugin_dir .. "/tests/test_data/256x256.png", {
			id = "image-scroll-check",
			window = win,
			buffer = buf,
			y = 9,
			with_virtual_padding = true,
		}),
		"Inline image fixture could not load"
	)
	local namespace = api.nvim_get_namespaces()["image.nvim"]
	local function padding()
		local mark = api.nvim_buf_get_extmark_by_id(buf, namespace, picture.internal_id, { details = true })
		return mark[3] and #(mark[3].virt_lines or {}) or 0
	end
	local function settle()
		for _ = 1, 4 do
			vim.cmd.redraw()
			vim.wait(15, function()
				return false
			end, 5)
		end
	end
	vim.cmd("normal! 10Gzt")
	picture:render()
	settle()
	assert(picture.is_rendered and padding() == 10, "Inline fixture did not reserve its image height")
	vim.cmd("normal! 14" .. vim.keycode("<C-e>"))
	settle()
	local partial = vim.fn.winsaveview()
	assert(partial.topfill > 0 and partial.topfill < padding(), "Fixture did not partially scroll the image offscreen")
	assert(picture.rendered_geometry.y < picture.bounds.top, "Image was not cropped at the top")
	local function check_decorations(edge)
		local before, height = vim.fn.winsaveview(), padding()
		for _, filetype in ipairs({ "scrollview", "scrollview_sign" }) do
			local floatbuf = api.nvim_create_buf(false, true)
			vim.bo[floatbuf].filetype = filetype
			local float = api.nvim_open_win(floatbuf, false, {
				relative = "win",
				win = win,
				row = 1,
				col = api.nvim_win_get_width(win) - 2,
				width = 1,
				height = 3,
				focusable = false,
				style = "minimal",
				zindex = 50,
			})
			settle()
			assert(picture.is_rendered and padding() == height, filetype .. " removed " .. edge .. " image padding")
			assert(vim.deep_equal(before, vim.fn.winsaveview()), filetype .. " pulled the " .. edge .. " viewport back")
			api.nvim_win_close(float, true)
			api.nvim_buf_delete(floatbuf, { force = true })
			settle()
			assert(vim.deep_equal(before, vim.fn.winsaveview()), "Removing " .. filetype .. " shifted the viewport")
		end
	end
	check_decorations("top")
	-- Move the same inline image to the bottom edge and allow it to be cropped.
	picture:clear()
	vim.cmd("normal! gg")
	picture:move(0, api.nvim_win_get_height(win) - 3)
	settle()
	assert(
		picture.rendered_geometry.y + picture.rendered_geometry.height > picture.bounds.bottom + 1,
		"Image was not cropped at the bottom"
	)
	check_decorations("bottom")
	local dialogbuf = api.nvim_create_buf(false, true)
	vim.bo[dialogbuf].filetype = "image_scroll_dialog"
	local dialog = api.nvim_open_win(dialogbuf, false, {
		relative = "win",
		win = win,
		row = 4,
		col = 10,
		width = 20,
		height = 4,
		style = "minimal",
	})
	settle()
	assert(not picture.is_rendered, "A real dialog no longer hides the image behind it")
	api.nvim_win_close(dialog, true)
	picture:clear()
	print("Inline image padding and viewport stay stable at both edges with scrollbar and sign floats.")
end
