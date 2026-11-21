-- 第 3 层：通用透明处理
-- 把所有「背景色等于编辑器/侧边栏/浮窗底色」的高亮组改成透明，
-- 不依赖主题自带的透明选项，因此对任何主题、任何插件都一致。
local M = {}

-- 必须保留底色的组（即使颜色恰好相同）
local keep = {
  Visual = true,
  VisualNOS = true,
  Search = true,
  IncSearch = true,
  CurSearch = true,
  Substitute = true,
  PmenuSel = true,
  CursorLine = true,
  MatchParen = true,
  DiffAdd = true,
  DiffChange = true,
  DiffDelete = true,
  DiffText = true,
  Folded = true,
  UiFoldCount = true,
  BlinkCmpMenuSelection = true,
  FlashLabel = true,
}

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

  for name, spec in pairs(vim.api.nvim_get_hl(0, {})) do
    if not spec.link and spec.bg and targets[spec.bg] and not keep[name] and not name:find("^lualine_") then
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
