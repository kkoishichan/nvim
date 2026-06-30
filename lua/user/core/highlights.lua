-- Helper so theme-derived highlight overrides survive a colorscheme switch:
-- runs `fn` immediately and again after every ColorScheme event.

local M = {}

local group = vim.api.nvim_create_augroup("user_custom_highlights", { clear = false })

---@param fn fun()
function M.on_colorscheme(fn)
	fn()
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = fn })
end

return M
