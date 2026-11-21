local map = vim.keymap.set

-- 折行时按显示行移动
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- 窗口
map("n", "<C-h>", "<C-w>h", { desc = "Go to Left Window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to Lower Window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to Upper Window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to Right Window" })
-- <C-Up>/<C-Down> 留给多光标，窗口大小用 Alt + 方向键
map("n", "<A-Up>", "<cmd>resize +2<cr>", { desc = "Increase Window Height" })
map("n", "<A-Down>", "<cmd>resize -2<cr>", { desc = "Decrease Window Height" })
map("n", "<A-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease Window Width" })
map("n", "<A-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase Window Width" })
map("n", "<leader>-", "<C-w>s", { desc = "Split Below" })
map("n", "<leader>|", "<C-w>v", { desc = "Split Right" })
map("n", "<leader>wd", "<C-w>c", { desc = "Delete Window" })

-- 移动行
map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
map("x", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
map("x", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

-- buffer
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev Buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next Buffer" })
map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })
map("n", "<leader>`", "<cmd>e #<cr>", { desc = "Switch to Other Buffer" })

-- Esc 清除搜索高亮
map({ "i", "n", "s" }, "<esc>", function()
  vim.cmd("noh")
  return "<esc>"
end, { expr = true, desc = "Escape and Clear hlsearch" })

-- n/N 方向固定并展开折叠
map({ "n", "x", "o" }, "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
map({ "n", "x", "o" }, "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })

-- 保存
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

-- 缩进后保持选区
map("x", "<", "<gv")
map("x", ">", ">gv")

-- 诊断
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
map("n", "]e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { desc = "Next Error" })
map("n", "[e", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { desc = "Prev Error" })

-- 杂项
map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit All" })
map("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy" })
map("n", "<leader>ui", vim.show_pos, { desc = "Inspect Pos" })
map("n", "]w", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.WARN, float = true })
end, { desc = "Next Warning" })
map("n", "[w", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.WARN, float = true })
end, { desc = "Prev Warning" })
map("n", "<leader>zi", function()
  pcall(vim.lsp.foldclose, "imports", 0)
end, { desc = "Fold Imports" })

-- 终端模式：双击 Esc 回到普通模式
map("t", "<esc><esc>", "<c-\\><c-n>", { desc = "Enter Normal Mode" })

-- 复制路径 / Git 远程链接
local function yank(text, what)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(text, vim.log.levels.INFO, { title = "Copied " .. what })
end
map("n", "<leader>fy", function()
  yank(vim.fn.expand("%:."), "relative path")
end, { desc = "Copy Relative Path" })
map("n", "<leader>fY", function()
  yank(vim.fn.expand("%:p"), "absolute path")
end, { desc = "Copy Absolute Path" })
map({ "n", "x" }, "<leader>gy", function()
  local file = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(0, ".git")
  if not root or file == "" then
    return vim.notify("Not in a git repository", vim.log.levels.WARN)
  end
  local function git(...)
    local out = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
    return out.code == 0 and vim.trim(out.stdout) or nil
  end
  local remote, sha = git("remote", "get-url", "origin"), git("rev-parse", "HEAD")
  if not remote or not sha then
    return vim.notify("No remote 'origin' or commits", vim.log.levels.WARN)
  end
  local url = remote:gsub("%.git$", ""):gsub("^git@([^:]+):", "https://%1/"):gsub("^ssh://git@", "https://")
  local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local mode = vim.fn.mode()
  local range = (mode == "v" or mode == "V") and ("#L" .. l1 .. "-L" .. l2) or ("#L" .. l2)
  local blob = url:find("gitlab") and "/-/blob/" or "/blob/"
  yank(url .. blob .. sha .. "/" .. vim.fs.relpath(root, file) .. range, "git link")
end, { desc = "Copy Git Remote Link" })

-- 界面开关
local function toggle(name, get, set)
  return function()
    local value = not get()
    set(value)
    vim.notify((value and "Enabled " or "Disabled ") .. name, vim.log.levels.INFO, { title = "Toggle" })
  end
end
local function opt_toggle(option, name)
  return toggle(name, function()
    return vim.wo[option]
  end, function(v)
    vim.opt_local[option] = v
  end)
end
map("n", "<leader>uw", opt_toggle("wrap", "Wrap"), { desc = "Toggle Wrap" })
map("n", "<leader>us", opt_toggle("spell", "Spelling"), { desc = "Toggle Spelling" })
map("n", "<leader>uL", opt_toggle("relativenumber", "Relative Number"), { desc = "Toggle Relative Number" })
map("n", "<leader>ul", opt_toggle("number", "Line Number"), { desc = "Toggle Line Number" })
map(
  "n",
  "<leader>uc",
  toggle("Conceal", function()
    return vim.wo.conceallevel > 0
  end, function(v)
    vim.wo.conceallevel = v and 2 or 0
  end),
  { desc = "Toggle Conceal" }
)
map(
  "n",
  "<leader>ud",
  toggle("Diagnostics", function()
    return vim.diagnostic.is_enabled()
  end, function(v)
    vim.diagnostic.enable(v)
  end),
  { desc = "Toggle Diagnostics" }
)
map(
  "n",
  "<leader>uh",
  toggle("Inlay Hints", function()
    return vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  end, function(v)
    vim.lsp.inlay_hint.enable(v, { bufnr = 0 })
  end),
  { desc = "Toggle Inlay Hints" }
)
map(
  "n",
  "<leader>uf",
  toggle("Auto Format (global)", function()
    return vim.g.autoformat
  end, function(v)
    vim.g.autoformat = v
  end),
  { desc = "Toggle Auto Format (Global)" }
)
map(
  "n",
  "<leader>uF",
  toggle("Auto Format (buffer)", function()
    return vim.b.autoformat ~= false
  end, function(v)
    vim.b.autoformat = v
  end),
  { desc = "Toggle Auto Format (Buffer)" }
)
map(
  "n",
  "<leader>uS",
  toggle("Smooth Scroll", function()
    return vim.g.smooth_scroll
  end, function(v)
    vim.g.smooth_scroll = v
  end),
  { desc = "Toggle Smooth Scroll" }
)
map("n", "<leader>ug", "<cmd>IBLToggle<cr>", { desc = "Toggle Indent Guides" })
map("n", "<leader>ux", "<cmd>TSContext toggle<cr>", { desc = "Toggle Sticky Context" })
map("n", "<leader>uC", function()
  require("ui.themes").pick()
end, { desc = "Theme Picker" })
map("n", "<leader>ut", function()
  require("ui.themes").toggle_transparent()
end, { desc = "Toggle Transparent" })
