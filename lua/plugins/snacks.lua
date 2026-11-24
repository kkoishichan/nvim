-- snacks.nvim：只启用下面列出的模块，配色由 lua/ui 统一控制
-- indent（替代 indent-blankline）· toggle（界面开关，见 config/keymaps.lua）·
-- terminal / lazygit（替代 toggleterm）· bigfile（大文件保护）· gitbrowse（Git 远程链接）·
-- image（kitty 中显示图片和公式）
-- 状态列和 LSP 同名词高亮没有用 snacks：它们在每次重绘 / 光标移动时的开销会让快速滚动变卡，
-- 改为 lua/ui/statuscolumn.lua 和 plugins/lsp.lua 中的实现

-- 浮动终端和 lazygit 的窗口：圆角边框，不加背景遮罩（与 fzf 等浮窗一致）
local float = { position = "float", border = "rounded", backdrop = false }

return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      indent = {
        indent = { char = "│", hl = "UiIndent" },
        scope = { char = "│", hl = "UiScope" },
        animate = { enabled = false },
        filter = function(buf)
          local skip = { dashboard = true, help = true, lazy = true, mason = true, bigfile = true }
          return vim.g.snacks_indent ~= false
            and vim.b[buf].snacks_indent ~= false
            and vim.bo[buf].buftype == ""
            and not skip[vim.bo[buf].filetype]
        end,
      },
      bigfile = {
        -- 不提示：启动时通知插件还没加载，两行提示会出现"按回车继续"挡住启动
        notify = false,
        -- 默认处理（关闭折叠表达式、状态列、补全，改用正则语法高亮）外，
        -- 再标记 vim.b.bigfile，格式化、平滑滚动等据此跳过
        setup = function(ctx)
          vim.b[ctx.buf].bigfile = true
          Snacks.util.wo(0, { foldmethod = "manual", statuscolumn = "", conceallevel = 0 })
          vim.b[ctx.buf].completion = false
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(ctx.buf) then
              vim.bo[ctx.buf].syntax = ctx.ft
            end
          end)
        end,
      },
      image = {
        -- 只在 Markdown 中渲染图片和公式（见下方 init）；LaTeX 交给 vimtex + zathura
        doc = { inline = true, max_width = 80, max_height = 30 },
      },
      terminal = { win = float },
      lazygit = { win = float },
    },
    keys = {
      {
        "<C-/>",
        function()
          Snacks.terminal.toggle(nil, { win = float })
        end,
        mode = { "n", "t" },
        desc = "Terminal",
      },
      {
        "<C-_>",
        function()
          Snacks.terminal.toggle(nil, { win = float })
        end,
        mode = { "n", "t" },
        desc = "which_key_ignore",
      },
      {
        "<leader>gg",
        function()
          Snacks.lazygit({ cwd = vim.fs.root(0, ".git") })
        end,
        desc = "Lazygit",
      },
      {
        "<leader>go",
        function()
          Snacks.gitbrowse()
        end,
        mode = { "n", "x" },
        desc = "Open in Browser (Git Remote)",
      },
      {
        "<leader>gy",
        function()
          Snacks.gitbrowse({
            what = "permalink",
            notify = false,
            open = function(url)
              vim.fn.setreg("+", url)
              vim.fn.setreg('"', url)
              vim.notify(url, vim.log.levels.INFO, { title = "Copied git link" })
            end,
          })
        end,
        mode = { "n", "x" },
        desc = "Copy Git Remote Link",
      },
    },
    init = function()
      -- image 默认会接管所有有 images.scm 查询的语言（LaTeX、HTML、JS 等）；
      -- 预先标记为已处理，只保留 Markdown
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_snacks_image", { clear = true }),
        callback = function(ev)
          if vim.bo[ev.buf].filetype ~= "markdown" then
            vim.b[ev.buf].snacks_image_attached = true
          end
        end,
      })
    end,
  },
}
