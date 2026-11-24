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

-- 复制路径（Git 远程链接见 plugins/snacks.lua 的 <leader>gy / <leader>gB）
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

-- 界面开关（snacks.toggle：which-key 菜单中显示当前是开还是关）
local toggle = Snacks.toggle
toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
toggle.option("spell", { name = "Spelling" }):map("<leader>us")
toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
toggle.line_number():map("<leader>ul")
toggle.option("conceallevel", { off = 0, on = 2, name = "Conceal" }):map("<leader>uc")
toggle.diagnostics():map("<leader>ud")
toggle.inlay_hints():map("<leader>uh")
toggle.indent():map("<leader>ug")
toggle
  .new({
    id = "autoformat",
    name = "Auto Format (Global)",
    get = function()
      return vim.g.autoformat
    end,
    set = function(state)
      vim.g.autoformat = state
    end,
  })
  :map("<leader>uf")
toggle
  .new({
    id = "autoformat_buffer",
    name = "Auto Format (Buffer)",
    get = function()
      return vim.b.autoformat ~= false
    end,
    set = function(state)
      vim.b.autoformat = state
    end,
  })
  :map("<leader>uF")
toggle
  .new({
    id = "smooth_scroll",
    name = "Smooth Scroll",
    get = function()
      return vim.g.smooth_scroll
    end,
    set = function(state)
      vim.g.smooth_scroll = state
    end,
  })
  :map("<leader>uS")
toggle
  .new({
    id = "treesitter_context",
    name = "Sticky Context",
    get = function()
      return require("treesitter-context").enabled()
    end,
    set = function(state)
      require("treesitter-context")[state and "enable" or "disable"]()
    end,
  })
  :map("<leader>ux")
toggle
  .new({
    id = "transparent",
    name = "Transparent",
    notify = false, -- toggle_transparent 自己会提示
    get = function()
      return require("ui.themes").state.transparent
    end,
    set = function(state)
      if state ~= require("ui.themes").state.transparent then
        require("ui.themes").toggle_transparent()
      end
    end,
  })
  :map("<leader>ut")
map("n", "<leader>uC", function()
  require("ui.themes").pick()
end, { desc = "Theme Picker" })
