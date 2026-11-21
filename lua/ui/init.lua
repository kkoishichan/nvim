-- UI 设计系统入口：主题层 → 界面层 → 透明层
local M = {}

---@type table? 当前语义调色板，供 lualine / bufferline 等读取
M.palette = nil

local pending, pending_refresh = false, false

---延后一帧：应用插件高亮 + 透明处理，必要时通知 lualine 等刷新
function M.schedule_late(refresh)
  pending_refresh = pending_refresh or refresh
  if pending or not M.palette then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    require("ui.highlights").plugins(M.palette)
    if M.palette.transparent then
      require("ui.transparent").apply(M.palette)
    end
    if pending_refresh then
      pending_refresh = false
      vim.api.nvim_exec_autocmds("User", { pattern = "UiRefresh", modeline = false })
    end
  end)
end

function M.refresh()
  local p = require("ui.palette").extract()
  p.transparent = require("ui.themes").state.transparent
  M.palette = p
  require("ui.highlights").base(p)
  M.schedule_late(true)
end

function M.setup()
  local themes = require("ui.themes")
  themes.load_state()
  themes.create_commands()

  local group = vim.api.nvim_create_augroup("user_ui", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      M.refresh()
      themes.on_colorscheme()
    end,
  })
  -- 插件懒加载后可能会定义自己的高亮，重新应用一次
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function()
      M.schedule_late(false)
    end,
  })

  if not themes.apply(themes.state.theme, { silent = true }) then
    themes.apply(themes.default)
  end
end

return M
