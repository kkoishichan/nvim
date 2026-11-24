-- 第 3 层：通用透明处理
-- 把所有「背景色等于编辑器/侧边栏/浮窗底色」的高亮组改成透明，
-- 不依赖主题自带的透明选项，因此对任何主题、任何插件都一致。
local M = {}

-- 界面层（ui.highlights）设置的组已按透明模式取色，这里直接跳过；
-- 以下是主题和插件里表示选区、标记的组，底色即使恰好等于编辑区底色也要保留
local keep = {
  Visual = true,
  VisualNOS = true,
  Search = true,
  IncSearch = true,
  CurSearch = true,
  Substitute = true,
  DiffAdd = true,
  DiffChange = true,
  DiffDelete = true,
  DiffText = true,
  ColorColumn = true,
  CursorColumn = true,
  QuickFixLine = true,
  WildMenu = true,
  Cursor = true,
  lCursor = true,
  CursorIM = true,
  TermCursor = true,
  SnippetTabstop = true,
  SnippetTabstopActive = true,
  LspSignatureActiveParameter = true,
}
-- 插件按命名约定表示选中项、当前项、匹配、滚动条滑块、计数徽标的组
local keep_patterns = { "Sel$", "Selection$", "Selected$", "CursorLine$", "Current", "Match$", "Thumb$", "Count$" }

local function kept(name)
  if keep[name] then
    return true
  end
  for _, pat in ipairs(keep_patterns) do
    if name:find(pat) then
      return true
    end
  end
  return false
end

local function to_int(hex)
  return hex and tonumber(hex:sub(2), 16) or nil
end

function M.apply(p)
  local targets = {}
  for _, c in ipairs({ p.bg, p.sidebar, p.surface, p.theme_float }) do
    local n = to_int(c)
    if n then
      targets[n] = true
    end
  end

  local owned = require("ui.highlights").owned
  for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
    if
      not spec.link
      and spec.bg
      and targets[spec.bg]
      and not owned[name]
      and not name:find("^lualine_")
      and not kept(name)
    then
      spec.bg = nil
      if spec.cterm then
        spec.cterm.bg = nil
      end
      spec.ctermbg = nil
      pcall(vim.api.nvim_set_hl, 0, name, spec)
    end
  end

  -- 确保基础组透明
  for _, name in ipairs({
    "Normal",
    "NormalNC",
    "NormalSB",
    "EndOfBuffer",
    "SignColumn",
    "SignColumnSB",
    "FoldColumn",
    "LineNr",
    "CursorLineNr",
    "StatusLineTerm",
    "StatusLineTermNC",
  }) do
    local spec = vim.api.nvim_get_hl(0, { name = name, link = false })
    spec.bg = nil
    pcall(vim.api.nvim_set_hl, 0, name, spec)
  end
end

return M
