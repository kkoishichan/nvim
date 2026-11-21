local opt = vim.opt

-- 界面
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.showmode = false -- 模式由状态栏显示
opt.laststatus = 3 -- 全局状态栏
opt.pumheight = 10
opt.winborder = "rounded" -- 所有浮窗圆角
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
opt.fillchars = { foldopen = "\u{eab4}", foldclose = "\u{eab6}", fold = " ", foldsep = " ", diff = "╱", eob = " " }
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.smoothscroll = true

-- 编辑
opt.mouse = "a"
opt.undofile = true
opt.undolevels = 10000
opt.confirm = true
opt.virtualedit = "block"
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.shiftround = true
opt.smartindent = true
opt.wrap = false
opt.linebreak = true
opt.formatoptions = "jcroqlnt"
opt.completeopt = "menu,menuone,noselect"
opt.spelllang = { "en", "cjk" }

-- 搜索
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split" -- :s 替换实时预览
opt.grepprg = "rg --vimgrep"
opt.grepformat = "%f:%l:%c:%m"

-- 窗口与滚动
opt.splitright = true
opt.splitbelow = true
opt.splitkeep = "screen"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.jumpoptions = "view"

-- 折叠（treesitter），默认全部展开
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldtext = "v:lua.require'ui.fold'.text()"
opt.foldcolumn = "1"
opt.foldlevel = 99

-- 响应速度
opt.updatetime = 200
opt.timeoutlen = 300

opt.wildmode = "longest:full,full"
opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

vim.g.autoformat = true -- 保存时格式化（<leader>uf 开关）
vim.g.smooth_scroll = true -- 平滑滚动（<leader>uS 开关）

-- 剪贴板探测较慢，推迟到启动后
vim.schedule(function()
  if vim.env.SSH_TTY then
    -- SSH 下用 OSC 52：复制经终端写入本地剪贴板。
    -- 粘贴不向终端读取（kitty 默认会弹窗询问，且要等待响应），直接用 nvim 最近一次复制的内容；
    -- 粘贴本地剪贴板的内容用终端的粘贴键（Ctrl+Shift+V）
    local osc52 = require("vim.ui.clipboard.osc52")
    local function paste()
      return { vim.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
    end
    vim.g.clipboard = {
      name = "OSC 52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = paste, ["*"] = paste },
    }
  end
  opt.clipboard = "unnamedplus"
end)
