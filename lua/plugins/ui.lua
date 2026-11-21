local icons = require("config.icons")

local function palette()
  return require("ui").palette
end

-- 由调色板生成 lualine 主题：圆角胶囊，模式块用实色，其余透明或与编辑区同色
local function lualine_theme()
  local p = palette()
  local base = p.transparent and "NONE" or p.bg
  local b = { fg = p.fg, bg = p.subtle }
  local c = { fg = p.muted, bg = base }
  local function mode(color)
    return { a = { fg = p.bg, bg = color, gui = "bold" }, b = b, c = c, x = c, y = b, z = { fg = p.bg, bg = color } }
  end
  return {
    normal = mode(p.accent),
    insert = mode(p.ok),
    visual = mode(p.special),
    replace = mode(p.error),
    command = mode(p.warn),
    terminal = mode(p.info),
    inactive = { a = c, b = c, c = c },
  }
end

return {
  -- 图标（同时模拟 nvim-web-devicons，供其他插件使用）
  {
    "nvim-mini/mini.icons",
    lazy = true,
    opts = {},
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },

  -- 启动页
  {
    "nvimdev/dashboard-nvim",
    lazy = true,
    cmd = "Dashboard",
    opts = function()
      local logo = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]]
      logo = string.rep("\n", 6) .. logo .. "\n\n"
      local center = {
        { action = "FzfLua files", desc = " Find File", icon = "\u{f002} ", key = "f" },
        { action = "ene | startinsert", desc = " New File", icon = "\u{f15b} ", key = "n" },
        { action = "FzfLua oldfiles", desc = " Recent Files", icon = "\u{f1da} ", key = "r" },
        { action = "FzfLua live_grep", desc = " Grep Text", icon = "\u{f422} ", key = "g" },
        { action = 'lua require("persistence").load()', desc = " Restore Session", icon = "\u{f01e} ", key = "s" },
        { action = 'lua require("ui.themes").pick()', desc = " Themes", icon = "\u{f53f} ", key = "t" },
        { action = "FzfLua files cwd=" .. vim.fn.stdpath("config"), desc = " Config", icon = "\u{f013} ", key = "c" },
        { action = "Lazy", desc = " Lazy", icon = "󰒲 ", key = "l" },
        { action = "qa", desc = " Quit", icon = "\u{f426} ", key = "q" },
      }
      for _, item in ipairs(center) do
        item.desc = item.desc .. string.rep(" ", 40 - #item.desc)
        item.key_format = "  %s"
      end
      return {
        theme = "doom",
        hide = { statusline = false, tabline = true, winbar = true },
        config = {
          header = vim.split(logo, "\n"),
          center = center,
          footer = function()
            local stats = require("lazy").stats()
            local ms = math.floor(stats.startuptime * 100 + 0.5) / 100
            return { "", "⚡ loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms .. "ms" }
          end,
        },
      }
    end,
  },

  -- 状态栏
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      vim.g.lualine_laststatus = vim.o.laststatus
      if vim.fn.argc(-1) > 0 then
        vim.o.statusline = " " -- 加载前留空，避免闪一下默认状态栏
      else
        vim.o.laststatus = 0
      end
    end,
    opts = function()
      vim.o.laststatus = vim.g.lualine_laststatus
      local function lsp_clients()
        local names = vim.tbl_map(function(c)
          return c.name
        end, vim.lsp.get_clients({ bufnr = 0 }))
        return #names > 0 and ("\u{f085} " .. table.concat(names, " ")) or ""
      end
      return {
        options = {
          theme = lualine_theme(),
          globalstatus = true,
          component_separators = "",
          section_separators = { left = "\u{e0b4}", right = "\u{e0b6}" },
          disabled_filetypes = { statusline = { "dashboard" } },
        },
        sections = {
          lualine_a = { { "mode", separator = { left = "\u{e0b6}", right = "\u{e0b4}" } } },
          lualine_b = { { "branch", icon = "\u{e0a0}" } },
          lualine_c = {
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename", path = 1, symbols = { modified = " ●", readonly = " \u{f023}", unnamed = "" } },
            {
              "diagnostics",
              symbols = {
                error = icons.diagnostics.Error,
                warn = icons.diagnostics.Warn,
                info = icons.diagnostics.Info,
                hint = icons.diagnostics.Hint,
              },
            },
          },
          lualine_x = {
            {
              function()
                return "󰑋 @" .. vim.fn.reg_recording()
              end,
              cond = function()
                return vim.fn.reg_recording() ~= ""
              end,
              color = function()
                return { fg = palette().error }
              end,
            },
            {
              function()
                return require("lazy.status").updates()
              end,
              cond = function()
                return package.loaded["lazy.status"] and require("lazy.status").has_updates()
              end,
              color = function()
                return { fg = palette().warn }
              end,
            },
            {
              "diff",
              symbols = { added = icons.git.added, modified = icons.git.modified, removed = icons.git.removed },
              source = function()
                local g = vim.b.gitsigns_status_dict
                if g then
                  return { added = g.added, modified = g.changed, removed = g.removed }
                end
              end,
            },
            { lsp_clients },
          },
          lualine_y = { { "progress", padding = { left = 1, right = 1 } } },
          lualine_z = { { "location", separator = { left = "\u{e0b6}", right = "\u{e0b4}" } } },
        },
        extensions = { "lazy", "mason", "man", "quickfix", "neo-tree", "trouble", "toggleterm", "aerial", "fzf" },
      }
    end,
    config = function(_, opts)
      require("lualine").setup(opts)
      vim.api.nvim_create_autocmd("User", {
        pattern = "UiRefresh",
        group = vim.api.nvim_create_augroup("user_lualine", { clear = true }),
        callback = function()
          opts.options.theme = lualine_theme()
          require("lualine").setup(opts)
        end,
      })
    end,
  },

  -- 标签栏
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    keys = {
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "[B", "<cmd>BufferLineMovePrev<cr>", desc = "Move Buffer Left" },
      { "]B", "<cmd>BufferLineMoveNext<cr>", desc = "Move Buffer Right" },
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Toggle Pin" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Close Unpinned Buffers" },
      { "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", desc = "Close Buffers to the Left" },
      { "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Close Buffers to the Right" },
      { "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = "Close Other Buffers" },
    },
    opts = function()
      local function bufremove(n)
        require("mini.bufremove").delete(n, false)
      end
      return {
        options = {
          close_command = bufremove,
          right_mouse_command = bufremove,
          separator_style = "thin",
          themable = false, -- 由 lua/ui 统一控制颜色，每次都覆盖已有高亮

          indicator = { style = "underline" },
          always_show_bufferline = false, -- 只有一个 buffer 时隐藏
          show_buffer_close_icons = false,
          show_close_icon = false,
          modified_icon = "●",
          diagnostics = "nvim_lsp",
          diagnostics_update_in_insert = false,
          diagnostics_indicator = function(_, _, diag)
            local ret = (diag.error and icons.diagnostics.Error .. diag.error .. " " or "")
              .. (diag.warning and icons.diagnostics.Warn .. diag.warning or "")
            return vim.trim(ret)
          end,
          offsets = {
            {
              filetype = "neo-tree",
              text = "\u{f07b}  Explorer",
              highlight = "NeoTreeRootName",
              text_align = "left",
              separator = true,
            },
          },
          get_element_icon = function(el)
            local icon, hl = require("mini.icons").get("filetype", el.filetype)
            return icon, hl
          end,
        },
      }
    end,
    config = function(_, opts)
      local function highlights()
        local p = palette()
        local bg = p.transparent and "NONE" or p.bg
        local h = {}
        for _, k in ipairs(require("ui.bufferline_groups")) do
          h[k] = { bg = bg }
        end
        local function set(keys, spec)
          for _, k in ipairs(keys) do
            h[k] = vim.tbl_extend("force", h[k] or {}, spec)
          end
        end
        set({ "background", "buffer", "tab", "close_button", "numbers", "duplicate" }, { fg = p.muted })
        set({ "buffer_visible", "close_button_visible", "numbers_visible", "duplicate_visible" }, { fg = p.muted })
        set({ "buffer_selected", "numbers_selected", "close_button_selected", "tab_selected", "duplicate_selected" }, {
          fg = p.fg,
          bold = true,
          italic = false,
          sp = p.accent,
        })
        set({ "indicator_selected", "indicator_visible" }, { fg = p.accent, sp = p.accent })
        set({
          "separator",
          "separator_visible",
          "separator_selected",
          "tab_separator",
          "tab_separator_selected",
          "offset_separator",
        }, {
          fg = p.border,
        })
        set({ "modified", "modified_visible", "modified_selected" }, { fg = p.warn })
        for _, kind in ipairs({ "error", "warning", "info", "hint" }) do
          local c = ({ error = p.error, warning = p.warn, info = p.info, hint = p.hint })[kind]
          set({ kind, kind .. "_visible", kind .. "_diagnostic", kind .. "_diagnostic_visible" }, { fg = c, sp = c })
          set({ kind .. "_selected", kind .. "_diagnostic_selected" }, { fg = c, sp = p.accent, bold = true })
        end
        set({ "pick", "pick_visible", "pick_selected" }, { fg = p.error, bold = true })
        return h
      end
      opts.highlights = highlights()
      require("bufferline").setup(opts)
      vim.api.nvim_create_autocmd("User", {
        pattern = "UiRefresh",
        group = vim.api.nvim_create_augroup("user_bufferline", { clear = true }),
        callback = function()
          opts.highlights = highlights()
          require("bufferline").setup(opts)
        end,
      })
    end,
  },

  -- 面包屑
  {
    "Bekaboo/dropbar.nvim",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      {
        "<leader>;",
        function()
          require("dropbar.api").pick()
        end,
        desc = "Pick Breadcrumb",
      },
      {
        "[;",
        function()
          require("dropbar.api").goto_context_start()
        end,
        desc = "Go to Context Start",
      },
      {
        "];",
        function()
          require("dropbar.api").select_next_context()
        end,
        desc = "Select Next Context",
      },
    },
    opts = {
      menu = { win_configs = { border = "rounded" } },
    },
  },

  -- 快捷键提示
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      spec = {
        {
          mode = { "n", "x" },
          { "<leader>b", group = "buffer" },
          { "<leader>c", group = "code" },
          { "<leader>f", group = "file/find" },
          { "<leader>g", group = "git" },
          { "<leader>gh", group = "hunks" },
          { "<leader>m", group = "multicursor" },
          { "<leader>q", group = "quit/session" },
          { "<leader>s", group = "search" },
          { "<leader>u", group = "ui" },
          { "<leader>w", group = "windows", proxy = "<c-w>" },
          { "<leader>x", group = "diagnostics/quickfix" },
          { "<leader>z", group = "fold" },
          { "[", group = "prev" },
          { "]", group = "next" },
          { "g", group = "goto" },
          { "gp", group = "peek" },
          { "gs", group = "surround" },
          { "z", group = "fold" },
        },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Keymaps",
      },
    },
  },

  -- 通知
  {
    "j-hui/fidget.nvim",
    event = "VeryLazy",
    opts = {
      progress = { display = { done_icon = "\u{f00c}" } },
      notification = {
        override_vim_notify = true,
        window = { winblend = 0, border = "none", x_padding = 1, align = "bottom" },
      },
    },
  },

  -- 缩进线
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = "VeryLazy",
    opts = {
      indent = { char = "│", tab_char = "│", highlight = "UiIndent" },
      scope = { show_start = false, show_end = false, highlight = "UiScope" },
      exclude = {
        filetypes = {
          "dashboard",
          "help",
          "neo-tree",
          "Trouble",
          "trouble",
          "lazy",
          "mason",
          "toggleterm",
          "aerial",
          "bigfile",
        },
      },
    },
  },

  -- 左侧栏：git 标记 · 诊断 · 行号 · 折叠
  {
    "luukvbaal/statuscol.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local builtin = require("statuscol.builtin")
      require("statuscol").setup({
        relculright = true,
        ft_ignore = { "dashboard", "neo-tree", "aerial", "Trouble", "trouble", "toggleterm", "help", "lazy", "mason" },
        segments = {
          { sign = { namespace = { "gitsigns" }, maxwidth = 1, colwidth = 1, auto = false }, click = "v:lua.ScSa" },
          { sign = { namespace = { "diagnostic" }, maxwidth = 1, colwidth = 2, auto = false }, click = "v:lua.ScSa" },
          {
            sign = { name = { ".*" }, namespace = { ".*" }, maxwidth = 1, colwidth = 2, auto = true },
            click = "v:lua.ScSa",
          },
          { text = { builtin.lnumfunc, " " }, click = "v:lua.ScLa" },
          { text = { builtin.foldfunc, " " }, click = "v:lua.ScFa" },
        },
      })
    end,
  },

  -- Sticky context
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "VeryLazy",
    opts = { max_lines = 3, multiline_threshold = 1, trim_scope = "outer", mode = "cursor" },
    keys = {
      {
        "[x",
        function()
          require("treesitter-context").go_to_context(vim.v.count1)
        end,
        desc = "Go to Context",
      },
    },
  },

  -- 平滑滚动（只对翻页类按键生效）
  {
    "karb94/neoscroll.nvim",
    keys = function()
      local function scroll(fn, native)
        return function()
          if vim.g.smooth_scroll and not vim.b.bigfile then
            fn()
          else
            vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(native, true, false, true))
          end
        end
      end
      local function ns()
        return require("neoscroll")
      end
      local maps = {
        ["<C-u>"] = function()
          ns().ctrl_u({ duration = 150 })
        end,
        ["<C-d>"] = function()
          ns().ctrl_d({ duration = 150 })
        end,
        ["<C-b>"] = function()
          ns().ctrl_b({ duration = 250 })
        end,
        ["<C-f>"] = function()
          ns().ctrl_f({ duration = 250 })
        end,
        ["zt"] = function()
          ns().zt({ half_win_duration = 150 })
        end,
        ["zz"] = function()
          ns().zz({ half_win_duration = 150 })
        end,
        ["zb"] = function()
          ns().zb({ half_win_duration = 150 })
        end,
      }
      local keys = {}
      for lhs, fn in pairs(maps) do
        keys[#keys + 1] = { lhs, scroll(fn, lhs), mode = { "n", "x" }, desc = "Smooth " .. lhs }
      end
      return keys
    end,
    opts = { mappings = {}, easing = "quadratic", hide_cursor = true, respect_scrolloff = true },
  },

  -- 颜色代码预览
  {
    "brenoprata10/nvim-highlight-colors",
    event = "VeryLazy",
    opts = { render = "virtual", virtual_symbol = "●", virtual_symbol_position = "inline", enable_tailwind = true },
  },
}
