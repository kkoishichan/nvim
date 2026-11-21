-- 第 1 层：从当前主题提取语义颜色
local C = require("ui.color")
local M = {}

function M.extract()
  local dark = vim.o.background == "dark"
  local bg = C.hl("Normal", "bg") or (dark and "#1e1e2e" or "#eff1f5")
  local fg = C.hl("Normal", "fg") or (dark and "#cdd6f4" or "#4c4f69")
  dark = C.luminance(bg) < 0.5

  local p = {
    dark = dark,
    bg = bg,
    fg = fg,
    theme_float = C.hl("NormalFloat", "bg"),
    accent = C.first("fg", "Function", "Special", "Identifier") or fg,
    special = C.first("fg", "Keyword", "Statement", "Conditional") or fg,
    muted = C.first("fg", "Comment") or C.blend(fg, bg, 0.5),
    error = C.first("fg", "DiagnosticError", "ErrorMsg") or "#f38ba8",
    warn = C.first("fg", "DiagnosticWarn", "WarningMsg") or "#f9e2af",
    info = C.first("fg", "DiagnosticInfo") or "#89b4fa",
    hint = C.first("fg", "DiagnosticHint") or "#94e2d5",
  }
  p.ok = C.first("fg", "DiagnosticOk", "String") or p.hint
  p.add = C.first("fg", "GitSignsAdd", "Added", "diffAdded") or p.ok
  p.change = C.first("fg", "GitSignsChange", "Changed", "diffChanged") or p.warn
  p.delete = C.first("fg", "GitSignsDelete", "Removed", "diffRemoved") or p.error

  -- 派生色（透明模式下仍以 bg 为基准计算）
  p.surface = C.blend(fg, bg, dark and 0.05 or 0.035) -- 浮窗、补全
  p.sidebar = C.blend("#000000", bg, dark and 0.22 or 0.05) -- 侧边栏略深
  p.border = C.blend(fg, bg, 0.22)
  p.cursorline = C.blend(fg, bg, 0.065)
  p.subtle = C.blend(fg, bg, 0.12) -- 状态栏次级胶囊
  p.linenr = C.blend(fg, bg, 0.32)
  p.indent = C.blend(fg, bg, 0.1)
  return p
end

return M
