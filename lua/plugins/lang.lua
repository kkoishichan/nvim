return {
  -- LaTeX：编译、预览（zathura + SyncTeX）、专用文本对象
  {
    "lervag/vimtex",
    lazy = false, -- vimtex 本身按文件类型加载，官方不建议懒加载
    init = function()
      vim.g.vimtex_view_method = "zathura_simple" -- Wayland 下没有 xdotool
      vim.g.vimtex_compiler_latexmk_engines = { _ = "-xelatex" }
      vim.g.vimtex_quickfix_mode = 2 -- 有错误时打开 quickfix，但不抢焦点
      vim.g.vimtex_quickfix_open_on_warning = 0
      vim.g.vimtex_mappings_disable = { n = { "K" } } -- K 留给 LSP hover
      vim.g.vimtex_syntax_conceal_disable = 0
    end,
  },

  -- Cargo.toml：依赖版本提示与补全
  {
    "saecki/crates.nvim",
    event = "BufRead Cargo.toml",
    opts = {
      completion = { crates = { enabled = true } },
      lsp = { enabled = true, actions = true, completion = true, hover = true },
      popup = { border = "rounded" },
    },
  },

  -- Markdown 编辑器内渲染
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    opts = {
      code = { sign = false, width = "block", right_pad = 1, border = "thin" },
      heading = { sign = false, position = "inline" },
      completions = { blink = { enabled = true } },
    },
    keys = {
      {
        "<localleader>r",
        function()
          require("render-markdown").toggle()
        end,
        desc = "Toggle Render",
        ft = "markdown",
      },
    },
  },

  -- Typst：浏览器实时预览（光标同步）· 导出 PDF · zathura 查看
  {
    "chomosuke/typst-preview.nvim",
    version = "1.*",
    cmd = { "TypstPreview", "TypstPreviewToggle", "TypstPreviewUpdate" },
    keys = function()
      local function pdf_path()
        return vim.fn.expand("%:p:r") .. ".pdf"
      end
      -- 通过 tinymist 导出 PDF，完成后执行 done
      local function export(done)
        local client = vim.lsp.get_clients({ bufnr = 0, name = "tinymist" })[1]
        if not client then
          return vim.notify("tinymist 未启动", vim.log.levels.WARN)
        end
        client:exec_cmd(
          { title = "Export PDF", command = "tinymist.exportPdf", arguments = { vim.api.nvim_buf_get_name(0) } },
          { bufnr = 0 },
          function(err)
            if err then
              return vim.notify("导出失败：" .. err.message, vim.log.levels.ERROR)
            end
            vim.notify("已导出 " .. vim.fn.fnamemodify(pdf_path(), ":t"))
            if done then
              done()
            end
          end
        )
      end
      return {
        { "<localleader>p", "<cmd>TypstPreviewToggle<cr>", desc = "Preview in Browser", ft = "typst" },
        {
          "<localleader>c",
          function()
            export()
          end,
          desc = "Export PDF",
          ft = "typst",
        },
        {
          "<localleader>v",
          function()
            local open = function()
              vim.system({ "zathura", pdf_path() }, { detach = true })
            end
            if vim.uv.fs_stat(pdf_path()) then
              open()
            else
              export(open)
            end
          end,
          desc = "View PDF (zathura)",
          ft = "typst",
        },
      }
    end,
    opts = function()
      return {
        follow_cursor = true,
        -- 使用系统的 tinymist；websocat 系统没有时由插件自动下载
        dependencies_bin = {
          tinymist = "tinymist",
          websocat = vim.fn.executable("websocat") == 1 and "websocat" or nil,
        },
      }
    end,
  },

  -- 浏览器预览（文件类型专属，用 localleader：\p）
  {
    "brianhuster/live-preview.nvim",
    cmd = "LivePreview",
    keys = {
      {
        "<localleader>p",
        function()
          local ok, lp = pcall(require, "livepreview")
          if ok and lp.is_running and lp.is_running() then
            vim.cmd("LivePreview close")
          else
            vim.cmd("LivePreview start")
          end
        end,
        desc = "Preview in Browser",
        ft = { "markdown", "html", "asciidoc", "svg" },
      },
    },
    opts = { sync_scroll = true, picker = "fzf-lua" },
    config = function(_, opts)
      require("livepreview.config").set(opts)
    end,
  },
}
