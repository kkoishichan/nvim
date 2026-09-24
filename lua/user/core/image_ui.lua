-- Clip terminal images before drawing floats over them. Layout belongs to
-- image.nvim: temporary occlusion must never remove its virtual padding.
local M = {}
local api = vim.api
local owner
local namespace = api.nvim_create_namespace("user_image_ui")

local function borders(border)
	if not border or border == "none" or border == "" then
		return 0, 0, 0, 0
	end
	if border == "shadow" then
		return 0, 1, 1, 0
	end
	if type(border) ~= "table" then
		return 1, 1, 1, 1
	end
	local function side(index)
		local char = border[(index - 1) % #border + 1]
		char = type(char) == "table" and char[1] or char
		return char and char ~= "" and 1 or 0
	end
	if #border == 0 then
		return 0, 0, 0, 0
	end
	return side(2), side(4), side(6), side(8)
end

local function floats()
	local result = {}
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		local config = api.nvim_win_get_config(win)
		if config.relative ~= "" and not config.hide then
			local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
			if ft ~= "scrollview" and ft ~= "scrollview_sign" then
				local pos = api.nvim_win_get_position(win)
				local top, right, bottom, left = borders(config.border)
				result[#result + 1] = {
					win = win,
					zindex = config.zindex or 50,
					top = pos[1],
					left = pos[2],
					bottom = pos[1] + api.nvim_win_get_height(win) + top + bottom,
					right = pos[2] + api.nvim_win_get_width(win) + left + right,
				}
			end
		end
	end
	return result
end

local function clip(image, x, y, width, height)
	local bounds = image.bounds
	local rect = {
		top = math.max(y, bounds.top),
		left = math.max(x, bounds.left),
		bottom = math.min(y + height, bounds.bottom + 1),
		right = math.min(x + width, bounds.right),
	}
	local zindex = image.window and api.nvim_win_get_config(image.window).zindex or 0
	for _, mask in ipairs(floats()) do
		if
			mask.win ~= image.window
			and mask.zindex > zindex
			and mask.left < rect.right
			and mask.right > rect.left
			and mask.top < rect.bottom
			and mask.bottom > rect.top
		then
			-- Headers and bottom panels trim only the covered edge. For a
			-- popup crossing the middle, hide this image until it closes.
			if mask.left <= rect.left and mask.right >= rect.right and mask.top <= rect.top then
				rect.top = mask.bottom
			elseif mask.left <= rect.left and mask.right >= rect.right and mask.bottom >= rect.bottom then
				rect.bottom = mask.top
			elseif mask.top <= rect.top and mask.bottom >= rect.bottom and mask.left <= rect.left then
				rect.left = mask.right
			elseif mask.top <= rect.top and mask.bottom >= rect.bottom and mask.right >= rect.right then
				rect.right = mask.left
			else
				return nil
			end
		end
	end
	if rect.top >= rect.bottom or rect.left >= rect.right then
		return nil
	end
	-- The locked Kitty backend's left crop overwrites its right crop. Avoid
	-- painting through the right popup when both horizontal edges are covered.
	if rect.left > x and rect.right < x + width then
		return nil
	end
	return { top = rect.top, left = rect.left, bottom = rect.bottom - 1, right = rect.right }
end

function M.shutdown()
	local state = owner
	if not state then
		return
	end
	owner, state.active = nil, false
	if state.backend.render == state.wrapper then
		state.backend.render = state.render
	end
	api.nvim_set_decoration_provider(namespace, {})
	if vim._user_image_ui == M then
		vim._user_image_ui = nil
	end
end

function M.setup()
	local previous = vim._user_image_ui
	if previous and previous ~= M then
		previous.shutdown()
	end
	M.shutdown()
	local image = require("image")
	local backend = require("image/backends/kitty")
	local state = { active = true, backend = backend, render = backend.render }
	state.wrapper = function(picture, x, y, width, height)
		local bounds = clip(picture, x, y, width, height)
		if not bounds then
			local current = picture.global_state.images[picture.id]
			if current and current ~= picture then
				current:clear(true)
			end
			picture.global_state.images[picture.id] = picture
			if picture.is_rendered then
				backend.clear(picture.id, true)
			end
			return
		end
		local original = picture.bounds
		picture.bounds = bounds
		local ok, err = pcall(state.render, picture, x, y, width, height)
		picture.bounds = original
		if not ok then
			error(err)
		end
	end
	backend.render = state.wrapper
	owner, vim._user_image_ui = state, M
	-- which-key and context create floats with noautocmd. Observe redraws,
	-- coalesce changes, and redraw images only when float geometry changes.
	api.nvim_set_decoration_provider(namespace, {
		on_start = function()
			if not image.is_enabled() or #image.get_images() == 0 then
				state.floats = nil
				return false
			end
			local current = floats()
			if not vim.deep_equal(current, state.floats) then
				state.floats = current
				if not state.pending then
					state.pending = true
					vim.schedule(function()
						state.pending = false
						if not state.active or not image.is_enabled() then
							return
						end
						for _, picture in ipairs(image.get_images()) do
							-- Bypass the plugin's unchanged-geometry shortcut;
							-- the new crop never changes image height or padding.
							picture.rendered_geometry = {}
							picture:render()
						end
					end)
				end
			end
			return false
		end,
	})
end

return M
