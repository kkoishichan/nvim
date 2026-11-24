-- 第 2 层：用语义颜色统一生成界面高亮
local C = require("ui.color")
local M = {}

---本层设置过的组：它们已按透明模式取色，透明层不再处理
---@type table<string, true>
M.owned = {}

local function apply(groups)
  for name, spec in pairs(groups) do
    M.owned[name] = true
    vim.api.nvim_set_hl(0, name, spec)
  end
end

local function tint(c, p, a)
  return C.blend(c, p.bg, a)
end

---编辑器本身的界面组（ColorScheme 后立即应用）
function M.base(p)
  local T = p.transparent
  local float_bg = T and "NONE" or p.surface
  local line_bg = T and "NONE" or p.bg
  -- 外框（侧边栏、标签栏、状态栏、命令行）比编辑区深，浮层比编辑区浅
  local chrome_bg = T and "NONE" or p.chrome
  local sel_bg = tint(p.accent, p, 0.22)

  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  comment.italic = true

  local g = {
    Comment = comment,
    NormalFloat = { fg = p.fg, bg = float_bg },
    FloatBorder = { fg = p.border, bg = float_bg },
    FloatTitle = { fg = p.accent, bg = float_bg, bold = true },
    FloatFooter = { fg = p.muted, bg = float_bg },
    WinSeparator = { fg = p.border, bg = "NONE" },
    CursorLine = { bg = p.cursorline },
    CursorLineNr = { fg = p.accent, bold = true },
    LineNr = { fg = p.linenr },
    SignColumn = { bg = "NONE" },
    FoldColumn = { fg = p.linenr, bg = "NONE" },
    CursorLineFold = { fg = p.muted },
    CursorLineSign = { bg = "NONE" },
    Folded = { bg = tint(p.accent, p, 0.08) },
    UiFoldCount = { fg = p.accent, bg = tint(p.accent, p, 0.08), italic = true },
    Pmenu = { fg = p.fg, bg = float_bg },
    PmenuSel = { bg = sel_bg, bold = true },
    PmenuSbar = { bg = float_bg },
    PmenuThumb = { bg = p.border },
    PmenuBorder = { fg = p.border, bg = float_bg },
    StatusLine = { fg = p.fg, bg = chrome_bg },
    StatusLineNC = { fg = p.muted, bg = chrome_bg },
    MsgArea = { fg = C.hl("MsgArea", "fg"), bg = chrome_bg },
    TabLine = { fg = p.muted, bg = chrome_bg },
    TabLineFill = { bg = chrome_bg },
    TabLineSel = { fg = p.fg, bg = line_bg, bold = true }, -- 当前标签与编辑区同色
    WinBar = { fg = p.fg, bg = line_bg },
    WinBarNC = { fg = p.muted, bg = line_bg },
    OilWinbarIcon = { fg = p.accent, bg = line_bg },
    OilWinbarPath = { fg = p.fg, bg = line_bg, bold = true },
    Title = { fg = p.accent, bold = true },
    MatchParen = { bg = tint(p.accent, p, 0.25), bold = true },
    LspReferenceText = { bg = tint(p.fg, p, 0.1) },
    LspReferenceRead = { bg = tint(p.fg, p, 0.1) },
    LspReferenceWrite = { bg = tint(p.fg, p, 0.1), underline = true, sp = p.border },
    LspInlayHint = { fg = tint(p.fg, p, 0.45), bg = tint(p.fg, p, 0.05), italic = true },
    UiIndent = { fg = p.indent, nocombine = true },
    UiScope = { fg = tint(p.accent, p, 0.5), nocombine = true },
    -- 侧边栏（neo-tree、aerial、trouble、diffview 面板）
    UiSidebar = { fg = p.fg, bg = T and "NONE" or p.sidebar },
    UiSidebarCursorLine = { bg = C.blend(p.accent, p.sidebar, 0.15) },
    UiSidebarSeparator = { fg = T and p.border or p.sidebar, bg = T and "NONE" or p.sidebar },
  }

  -- 原生补全菜单的类型、附加信息、匹配字符列：底色跟随 Pmenu / PmenuSel，前景保留主题的
  for _, part in ipairs({ "Kind", "Extra", "Match" }) do
    local fg = C.hl("Pmenu" .. part, "fg") or (part == "Match" and p.accent or nil)
    local sel_fg = C.hl("Pmenu" .. part .. "Sel", "fg") or fg
    g["Pmenu" .. part] = { fg = fg, bg = float_bg, bold = part == "Match" }
    g["Pmenu" .. part .. "Sel"] = { fg = sel_fg, bg = sel_bg, bold = true }
  end

  for name, color in pairs({ Error = p.error, Warn = p.warn, Info = p.info, Hint = p.hint, Ok = p.ok }) do
    g["Diagnostic" .. name] = { fg = color }
    g["DiagnosticSign" .. name] = { fg = color }
    g["DiagnosticUnderline" .. name] = { undercurl = true, sp = color }
    g["DiagnosticVirtualText" .. name] = { fg = color, bg = tint(color, p, 0.12) }
    g["DiagnosticFloating" .. name] = { fg = color }
  end

  apply(g)
end

---插件相关的高亮组（延后一帧应用，避免被插件自己的 ColorScheme 回调覆盖）
function M.plugins(p)
  local T = p.transparent
  local float_bg = T and "NONE" or p.surface
  local side_bg = T and "NONE" or p.sidebar
  local sel = tint(p.accent, p, 0.18)

  local g = {
    -- gitsigns
    GitSignsAdd = { fg = p.add },
    GitSignsChange = { fg = p.change },
    GitSignsDelete = { fg = p.delete },
    GitSignsUntracked = { fg = p.info },
    GitSignsCurrentLineBlame = { fg = tint(p.fg, p, 0.35), italic = true },
    -- dashboard
    DashboardHeader = { fg = p.accent },
    DashboardIcon = { fg = p.accent },
    DashboardDesc = { fg = p.fg },
    DashboardKey = { fg = p.warn, bold = true },
    DashboardFooter = { fg = p.muted, italic = true },
    -- which-key
    WhichKeyNormal = { link = "NormalFloat" },
    WhichKeyBorder = { link = "FloatBorder" },
    WhichKeyTitle = { link = "FloatTitle" },
    WhichKey = { fg = p.accent },
    WhichKeyGroup = { fg = p.special },
    WhichKeyDesc = { fg = p.fg },
    WhichKeySeparator = { fg = p.muted },
    -- fzf-lua
    FzfLuaNormal = { link = "NormalFloat" },
    FzfLuaBorder = { link = "FloatBorder" },
    FzfLuaTitle = { link = "FloatTitle" },
    FzfLuaPreviewNormal = { link = "NormalFloat" },
    FzfLuaPreviewBorder = { link = "FloatBorder" },
    FzfLuaPreviewTitle = { link = "FloatTitle" },
    FzfLuaCursorLine = { bg = p.cursorline },
    FzfLuaFzfNormal = { fg = p.fg, bg = float_bg },
    FzfLuaFzfCursorLine = { fg = p.fg, bg = sel },
    FzfLuaFzfMatch = { fg = p.accent, bold = true },
    FzfLuaFzfPrompt = { fg = p.accent },
    FzfLuaFzfPointer = { fg = p.accent },
    FzfLuaFzfMarker = { fg = p.warn },
    FzfLuaFzfInfo = { fg = p.muted },
    FzfLuaFzfSeparator = { fg = p.border },
    FzfLuaFzfScrollbar = { fg = p.border },
    FzfLuaFzfGutter = { bg = float_bg },
    FzfLuaHeaderText = { fg = p.muted },
    FzfLuaHeaderBind = { fg = p.warn },
    -- neo-tree
    NeoTreeNormal = { link = "UiSidebar" },
    NeoTreeNormalNC = { link = "UiSidebar" },
    NeoTreeEndOfBuffer = { link = "UiSidebar" },
    NeoTreeWinSeparator = { link = "UiSidebarSeparator" },
    NeoTreeCursorLine = { link = "UiSidebarCursorLine" },
    NeoTreeRootName = { fg = p.accent, bold = true },
    NeoTreeDirectoryIcon = { fg = p.accent },
    NeoTreeDirectoryName = { fg = p.fg },
    NeoTreeFileNameOpened = { fg = p.fg, bold = true },
    NeoTreeIndentMarker = { fg = p.indent },
    NeoTreeExpander = { fg = p.muted },
    NeoTreeDimText = { fg = p.muted },
    NeoTreeDotfile = { fg = p.muted },
    NeoTreeModified = { fg = p.warn },
    NeoTreeGitAdded = { fg = p.add },
    NeoTreeGitModified = { fg = p.change },
    NeoTreeGitDeleted = { fg = p.delete },
    NeoTreeGitUntracked = { fg = p.info },
    NeoTreeGitConflict = { fg = p.error, bold = true },
    NeoTreeGitIgnored = { fg = p.muted },
    NeoTreeGitStaged = { fg = p.ok },
    NeoTreeGitUnstaged = { fg = p.warn },
    NeoTreeFloatBorder = { link = "FloatBorder" },
    NeoTreeFloatTitle = { link = "FloatTitle" },
    NeoTreeTitleBar = { fg = p.bg, bg = p.accent, bold = true },
    -- trouble / aerial / diffview
    TroubleNormal = { link = "UiSidebar" },
    TroubleNormalNC = { link = "UiSidebar" },
    AerialLine = { link = "UiSidebarCursorLine" },
    AerialGuide = { fg = p.indent },
    DiffviewNormal = { link = "UiSidebar" },
    DiffviewWinSeparator = { link = "UiSidebarSeparator" },
    DiffviewCursorLine = { link = "UiSidebarCursorLine" },
    DiffviewEndOfBuffer = { link = "UiSidebar" },
    -- glance
    GlancePreviewNormal = { bg = float_bg },
    GlancePreviewCursorLine = { bg = p.cursorline },
    GlancePreviewMatch = { bg = tint(p.warn, p, 0.22) },
    GlancePreviewLineNr = { fg = p.linenr, bg = float_bg },
    GlancePreviewSignColumn = { bg = float_bg },
    GlancePreviewEndOfBuffer = { fg = float_bg == "NONE" and p.bg or float_bg, bg = float_bg },
    GlancePreviewBorderBottom = { fg = p.border, bg = float_bg },
    GlanceListNormal = { fg = p.fg, bg = side_bg },
    GlanceListCursorLine = { bg = C.blend(p.accent, p.sidebar, 0.18) },
    GlanceListMatch = { fg = p.accent, bold = true },
    GlanceListFilename = { fg = p.fg, bold = true },
    GlanceListFilepath = { fg = p.muted },
    GlanceListCount = { fg = p.accent },
    GlanceListBorderBottom = { fg = p.border, bg = side_bg },
    GlanceListEndOfBuffer = { fg = side_bg == "NONE" and p.bg or side_bg, bg = side_bg },
    GlanceFoldIcon = { fg = p.muted },
    GlanceIndent = { fg = p.indent },
    GlanceBorderTop = { fg = p.border },
    GlanceWinBarTitle = { fg = p.accent, bg = float_bg, bold = true },
    GlanceWinBarFilename = { fg = p.fg, bg = float_bg, bold = true },
    GlanceWinBarFilepath = { fg = p.muted, bg = float_bg },
    -- treesitter-context
    TreesitterContext = { bg = float_bg },
    TreesitterContextLineNumber = { fg = p.muted, bg = float_bg },
    TreesitterContextBottom = { underline = true, sp = p.border },
    TreesitterContextLineNumberBottom = { underline = true, sp = p.border },
    -- blink.cmp
    BlinkCmpMenu = { link = "Pmenu" },
    BlinkCmpMenuBorder = { link = "PmenuBorder" },
    BlinkCmpMenuSelection = { link = "PmenuSel" },
    BlinkCmpDoc = { link = "NormalFloat" },
    BlinkCmpDocBorder = { link = "FloatBorder" },
    BlinkCmpDocSeparator = { fg = p.border, bg = float_bg },
    BlinkCmpSignatureHelp = { link = "NormalFloat" },
    BlinkCmpSignatureHelpBorder = { link = "FloatBorder" },
    BlinkCmpLabelMatch = { fg = p.accent, bold = true },
    BlinkCmpGhostText = { fg = p.muted, italic = true },
    BlinkCmpScrollBarThumb = { bg = p.border },
    BlinkCmpScrollBarGutter = { bg = float_bg },
    -- lazy / mason
    LazyNormal = { link = "NormalFloat" },
    MasonNormal = { link = "NormalFloat" },
    -- fidget
    FidgetTitle = { fg = p.accent, bold = true },
    FidgetTask = { fg = p.muted },
    -- flash
    FlashLabel = { fg = p.bg, bg = p.warn, bold = true },
    FlashMatch = { bg = tint(p.info, p, 0.25) },
    FlashCurrent = { bg = tint(p.ok, p, 0.3) },
    FlashBackdrop = { fg = p.muted },
    -- multicursor
    MultiCursorCursor = { reverse = true },
    MultiCursorVisual = { link = "Visual" },
    MultiCursorSign = { fg = p.accent },
    MultiCursorMatchPreview = { link = "Search" },
    MultiCursorDisabledCursor = { reverse = true },
    MultiCursorDisabledVisual = { link = "Visual" },
    MultiCursorDisabledSign = { fg = p.muted },
    -- dropbar
    DropBarMenuNormalFloat = { link = "NormalFloat" },
    DropBarMenuFloatBorder = { link = "FloatBorder" },
    DropBarMenuHoverEntry = { bg = sel },
    DropBarMenuCurrentContext = { bg = p.cursorline },
    DropBarIconUISeparator = { fg = p.muted },
    -- toggleterm
    ToggleTermNormal = { link = "NormalFloat" },
    ToggleTermBorder = { link = "FloatBorder" },
    -- render-markdown（代码块和标题保留淡色底）
    RenderMarkdownCode = { bg = tint(p.fg, p, 0.05) },
    RenderMarkdownCodeInline = { bg = tint(p.fg, p, 0.08) },
  }
  local heads = { p.accent, p.special, p.ok, p.warn, p.info, p.hint }
  for i, c in ipairs(heads) do
    g["RenderMarkdownH" .. i] = { fg = c, bold = true }
    g["RenderMarkdownH" .. i .. "Bg"] = { bg = tint(c, p, 0.12) }
  end

  apply(g)
end

return M
