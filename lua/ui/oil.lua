-- oil 窗口顶部的路径栏
local M = {}

function M.winbar()
  local buf = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
  local dir = require("oil").get_current_dir(buf)
  if not dir then
    return ""
  end
  dir = vim.fn.fnamemodify(dir, ":~"):gsub("%%", "%%%%")
  return "%#OilWinbarIcon# \u{f07c}  %#OilWinbarPath#" .. dir
end

return M
