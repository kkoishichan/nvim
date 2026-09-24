return function()
	local api = vim.api
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	-- The UI-only spec is intentionally disabled in this headless check.
	local plugin_dir = vim.fs.joinpath(require("lazy.core.config").options.root, "image.nvim")
	vim.opt.rtp:prepend(plugin_dir)
	-- Use the actual renderer, virtual lines and float masking. Only terminal
	-- pixels and source dimensions are simulated, so CI needs no Kitty/Magick.
	local backend = { features = { crop = true } }
	local placements = {}
	function backend.setup(state)
		backend.state = state
	end
	function backend.render(image)
		image.is_rendered = true
		backend.state.images[image.id] = image
		placements[image.id] = vim.deepcopy(image.bounds)
	end
	function backend.clear(id, shallow)
		for name, image in pairs(backend.state.images) do
			if not id or id == name then
				image.is_rendered = false
				placements[name] = nil
				if not shallow then
					backend.state.images[name] = nil
				end
			end
		end
	end
	package.loaded["image/backends/kitty"] = backend
	package.loaded["image/utils/term"] = {
		get_tty = function()
			return nil
		end,
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
	local spec = dofile(root .. "/lua/user/plugins/media.lua")[1]
	local opts = spec.opts
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
	spec.config(nil, opts)
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
	-- Use the real context parser and renderer on a README: a heading,
	-- followed immediately by an image and then ordinary body text.
	picture:clear()
	lines[1], lines[2], lines[3], lines[4] = "# Heading", "", "![image](fixture.png)", ""
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "markdown"
	vim.treesitter.start(buf)
	require("lazy").load({ plugins = { "nvim-treesitter-context", "which-key.nvim" } })
	require("treesitter-context").disable()
	assert(require("user.core.sticky_context").setup(), "Sticky context adapter differs from the locked plugin")
	local context = require("treesitter-context.context")
	local render = require("treesitter-context.render")
	vim.cmd("normal! gg")
	picture:move(0, 2)
	settle()
	vim.cmd("normal! 4" .. vim.keycode("<C-e>"))
	settle()
	local before = vim.fn.winsaveview()
	assert(before.topfill > 0 and before.lnum == before.topline, "Context fixture lacks virtual rows above the cursor")
	local ranges, headings = context.get(win)
	assert(headings and headings[1] == "# Heading", "Heading disappeared while scrolling through image padding")
	render.open(win, ranges, headings)
	settle()
	assert(
		vim.deep_equal(before, vim.fn.winsaveview()) and padding() == 10,
		"First context appearance shifted the view"
	)
	assert(picture.is_rendered, "Sticky context hid the entire image")
	assert(placements[picture.id].top > picture.bounds.top, "Image was drawn through the sticky heading")
	for _ = 1, 14 do
		vim.cmd("normal! " .. vim.keycode("<C-e>"))
		local scrolled = vim.fn.winsaveview()
		ranges, headings = context.get(win)
		assert(headings and headings[1] == "# Heading", "Heading flickered while the image left the screen")
		render.open(win, ranges, headings)
		settle()
		assert(vim.deep_equal(scrolled, vim.fn.winsaveview()), "Context/image redraw pulled the viewport back")
		assert(padding() == 10, "Scrolling or context removed image padding")
	end
	assert(not picture.is_rendered, "Image remained visible after fully scrolling offscreen")
	render.close(win)
	-- Restore a fully visible image. Popup filetypes used to bypass masking,
	-- while wk (the real which-key filetype) hid every image in the window.
	picture:clear()
	vim.cmd("normal! gg")
	picture:move(0, 2)
	settle()
	before = vim.fn.winsaveview()
	local function stable(message)
		assert(padding() == 10 and vim.deep_equal(before, vim.fn.winsaveview()), message)
	end
	for _, ft in ipairs({ "", "cmp_menu", "fzf", "snacks_notif", "image_scroll_dialog" }) do
		local floatbuf = api.nvim_create_buf(false, true)
		vim.bo[floatbuf].filetype = ft
		local float = api.nvim_open_win(floatbuf, false, {
			relative = "win",
			win = win,
			row = 5,
			col = 5,
			width = 10,
			height = 3,
			style = "minimal",
			noautocmd = true,
		})
		settle()
		assert(not picture.is_rendered, "Image covered a popup: " .. ft)
		stable("Popup appearance changed image layout: " .. ft)
		api.nvim_win_close(float, true)
		api.nvim_buf_delete(floatbuf, { force = true })
		settle()
		assert(picture.is_rendered, "Image did not return after popup closed: " .. ft)
		stable("Popup dismissal changed image layout: " .. ft)
	end
	local menu = require("which-key.win").new({ row = 17, col = 0, width = 70, height = 3, border = "single" })
	menu:show()
	settle()
	assert(picture.is_rendered, "A non-overlapping leader menu hid the image")
	stable("Leader menu changed image layout")
	menu:show({ row = 8 })
	settle()
	assert(picture.is_rendered, "Leader menu hid the uncovered top of the image")
	assert(placements[picture.id].bottom < picture.bounds.bottom, "Image extended into the leader menu")
	stable("Moving leader menu changed image layout")
	menu:hide()
	settle()
	assert(
		picture.is_rendered and placements[picture.id].bottom == 12,
		"Image crop did not recover after leader closed"
	)
	stable("Leader dismissal changed image layout")
	-- Exercise the real Kitty backend too: intercept only terminal writes,
	-- then inspect its pixel crop and placement command, not a mock's flags.
	local bridge = require("user.core.image_ui")
	bridge.shutdown()
	local display
	package.loaded["image/backends/kitty/helpers"] = {
		write_graphics = function() end,
		write_graphics_at = function(payload, x, y)
			display = { payload = payload, x = x, y = y }
		end,
	}
	local kitty = dofile(plugin_dir .. "/lua/image/backends/kitty/init.lua")
	package.loaded["image/backends/kitty"] = kitty
	kitty.setup(picture.global_state)
	picture.global_state.backend = kitty
	bridge.setup()
	bridge.setup()
	menu:show({ row = 8 })
	settle()
	assert(display and display.y + display.payload.display_height / 16 <= 9, "Kitty pixels crossed the leader border")
	stable("Kitty cropping changed image layout")
	menu:hide()
	settle()
	assert(display.payload.display_height == 160, "Kitty did not restore the full image after leader closed")
	local sides = {}
	local geometry = picture.rendered_geometry
	for _, col in ipairs({ geometry.x, geometry.x + geometry.width - 3 }) do
		local sidebuf = api.nvim_create_buf(false, true)
		local sidewin = api.nvim_open_win(sidebuf, false, {
			relative = "editor",
			row = geometry.y,
			col = col,
			width = 3,
			height = geometry.height,
			style = "minimal",
			noautocmd = true,
		})
		sides[#sides + 1] = { win = sidewin, buf = sidebuf }
	end
	settle()
	assert(not picture.is_rendered, "Kitty's simultaneous left/right crop painted through a side popup")
	stable("Two side popups changed image layout")
	for _, side in ipairs(sides) do
		api.nvim_win_close(side.win, true)
		api.nvim_buf_delete(side.buf, { force = true })
	end
	settle()
	assert(picture.is_rendered and display.payload.display_width == 160, "Closing side popups did not restore image")
	vim.cmd("normal! 4" .. vim.keycode("<C-e>"))
	ranges, headings = context.get(win)
	render.open(win, ranges, headings)
	settle()
	assert(display.payload.display_y > 0 and display.y >= 2, "Kitty pixels crossed the sticky heading")
	render.close(win)
	picture:clear()
	assert(padding() == 0, "Permanently clearing an image leaked virtual padding")
	require("user.core.image_ui").shutdown()
	require("user.core.sticky_context").shutdown()
	print("Image layout, sticky headings, popup occlusion and leader-menu clipping stay stable.")
end
