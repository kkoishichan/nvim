-- 主题注册、切换、持久化
local M = {}

local function sainnhe(scheme, background, bg)
  return {
    colorscheme = scheme,
    bg = bg or "dark",
    before = function()
      vim.g[scheme:gsub("-", "_") .. "_background"] = background
    end,
  }
end

---@type {name:string, colorscheme?:string, bg?:"dark"|"light", before?:fun()}[]
M.list = {
  { name = "catppuccin-mocha" },
  { name = "catppuccin-macchiato" },
  { name = "catppuccin-frappe" },
  { name = "catppuccin-latte", bg = "light" },
  { name = "tokyonight-night" },
  { name = "tokyonight-storm" },
  { name = "tokyonight-moon" },
  { name = "tokyonight-day", bg = "light" },
  { name = "kanagawa-wave" },
  { name = "kanagawa-dragon" },
  { name = "kanagawa-lotus", bg = "light" },
  { name = "rose-pine-main" },
  { name = "rose-pine-moon" },
  { name = "rose-pine-dawn", bg = "light" },
  { name = "nightfox" },
  { name = "duskfox" },
  { name = "nordfox" },
  { name = "terafox" },
  { name = "carbonfox" },
  { name = "dayfox", bg = "light" },
  { name = "dawnfox", bg = "light" },
  vim.tbl_extend("force", { name = "gruvbox-material-soft" }, sainnhe("gruvbox-material", "soft")),
  vim.tbl_extend("force", { name = "gruvbox-material-medium" }, sainnhe("gruvbox-material", "medium")),
  vim.tbl_extend("force", { name = "gruvbox-material-hard" }, sainnhe("gruvbox-material", "hard")),
  vim.tbl_extend("force", { name = "gruvbox-material-light" }, sainnhe("gruvbox-material", "medium", "light")),
  vim.tbl_extend("force", { name = "everforest-soft" }, sainnhe("everforest", "soft")),
  vim.tbl_extend("force", { name = "everforest-medium" }, sainnhe("everforest", "medium")),
  vim.tbl_extend("force", { name = "everforest-hard" }, sainnhe("everforest", "hard")),
  vim.tbl_extend("force", { name = "everforest-light" }, sainnhe("everforest", "medium", "light")),
  { name = "onedark" },
  { name = "onedark_vivid" },
  { name = "onedark_dark" },
  { name = "onelight", bg = "light" },
}

M.default = "catppuccin-mocha"
M.state = { theme = M.default, transparent = false }
M.current = nil

local state_file = vim.fn.stdpath("state") .. "/ui.json"
local applying = false

local function find(name)
  for _, t in ipairs(M.list) do
    if t.name == name then
      return t
    end
  end
end

function M.names()
  return vim.tbl_map(function(t)
    return t.name
  end, M.list)
end

function M.load_state()
  local f = io.open(state_file, "r")
  if not f then
    return
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok and type(data) == "table" then
    M.state = vim.tbl_extend("force", M.state, data)
  end
end

function M.save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ":h"), "p")
  local f = io.open(state_file, "w")
  if f then
    f:write(vim.json.encode(M.state))
    f:close()
  end
end

---应用主题
---@param name string 注册表中的名字，或任意 colorscheme 名
---@param opts? {persist?:boolean, silent?:boolean}
function M.apply(name, opts)
  opts = opts or {}
  local t = find(name)
  local scheme = t and (t.colorscheme or t.name) or name
  if t then
    if t.before then
      t.before()
    end
    local want = t.bg or "dark"
    if vim.o.background ~= want then
      vim.g.colors_name = nil -- 避免修改 background 时重新加载旧主题
      vim.o.background = want
    end
  end
  applying = true
  local ok, err = pcall(vim.cmd.colorscheme, scheme)
  applying = false
  if not ok then
    if not opts.silent then
      vim.notify("Failed to load theme " .. name .. "\n" .. tostring(err), vim.log.levels.ERROR)
    end
    return false
  end
  M.current = name
  if opts.persist then
    M.state.theme = name
    M.save_state()
  end
  return true
end

---用户手动执行 :colorscheme 时也持久化
function M.on_colorscheme()
  if applying or M.previewing then
    return
  end
  local name = vim.g.colors_name
  if name and name ~= "" then
    M.current = name
    M.state.theme = name
    M.save_state()
  end
end

function M.toggle_transparent()
  M.state.transparent = not M.state.transparent
  M.save_state()
  M.apply(M.current or M.state.theme)
  vim.notify(M.state.transparent and "Transparent background" or "Opaque background", vim.log.levels.INFO, {
    title = "Theme",
  })
end

---fzf 主题选择器：移动时实时预览，回车确认并保存，取消则恢复
function M.pick()
  local original = M.current or M.state.theme
  local names = M.names()
  for i, n in ipairs(names) do
    if n == original then
      table.remove(names, i)
      table.insert(names, 1, n)
      break
    end
  end

  local previewed
  local opts = {
    prompt = "\u{f53f}  ",
    fzf_opts = { ["--no-multi"] = true, ["--preview-window"] = "nohidden:right:0" },
    winopts = {
      title = " Themes ",
      height = 0.5,
      width = 0.32,
      row = 0.4,
      on_close = function()
        M.previewing = false
        -- 先恢复原主题；若是确认选择，随后的 action 会再应用选中的主题
        if previewed and previewed ~= original then
          M.apply(original)
        end
      end,
    },
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          M.apply(selected[1], { persist = true })
        end
      end,
    },
  }
  opts.preview = require("fzf-lua.shell").stringify_data(function(sel)
    if sel and sel[1] and sel[1] ~= previewed then
      previewed = sel[1]
      M.previewing = true
      M.apply(sel[1], { silent = true })
    end
  end, opts, "{}")
  require("fzf-lua").fzf_exec(names, opts)
end

function M.create_commands()
  vim.api.nvim_create_user_command("Theme", function(args)
    if args.args == "" then
      M.pick()
    else
      M.apply(args.args, { persist = true })
    end
  end, {
    nargs = "?",
    complete = function(lead)
      return vim.tbl_filter(function(n)
        return n:find(lead, 1, true) == 1
      end, M.names())
    end,
    desc = "Switch theme",
  })
  vim.api.nvim_create_user_command("Transparent", M.toggle_transparent, { desc = "Toggle transparent background" })
end

return M
