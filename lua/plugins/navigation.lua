local function fzf(cmd, opts)
  return function()
    require("fzf-lua")[cmd](opts or {})
  end
end

return {
  -- 模糊搜索
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    init = function()
      -- vim.ui.select 第一次被调用时再加载 fzf-lua
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.select = function(...)
        require("lazy").load({ plugins = { "fzf-lua" } })
        return vim.ui.select(...)
      end
    end,
    opts = {
      "default-title",
      fzf_colors = true,
      fzf_opts = { ["--no-scrollbar"] = true },
      winopts = {
        height = 0.85,
        width = 0.85,
        row = 0.5,
        col = 0.5,
        border = "rounded",
        backdrop = 100,
        preview = { layout = "flex", flip_columns = 130, scrollbar = false, border = "rounded" },
      },
      keymap = {
        fzf = {
          ["ctrl-q"] = "select-all+accept",
          ["ctrl-d"] = "preview-page-down",
          ["ctrl-u"] = "preview-page-up",
        },
        builtin = {
          ["<C-d>"] = "preview-page-down",
          ["<C-u>"] = "preview-page-up",
        },
      },
      files = { cwd_prompt = false, formatter = "path.filename_first" },
      oldfiles = { include_current_session = true, formatter = "path.filename_first" },
      grep = { formatter = "path.filename_first" },
      lsp = { jump1 = true, code_actions = { previewer = "codeaction_native" } },
    },
    config = function(_, opts)
      require("fzf-lua").setup(opts)
      require("fzf-lua").register_ui_select(function(o, items)
        local min_h, max_h = 0.15, 0.7
        local h = (#items + 4) / vim.o.lines
        h = math.max(min_h, math.min(max_h, h))
        if o.kind == "codeaction" then
          return { winopts = { height = 0.6, width = 0.7, preview = { layout = "vertical", vertical = "down:50%" } } }
        end
        return { winopts = { height = h, width = 0.5, row = 0.4 } }
      end)
    end,
    keys = {
      { "<leader><space>", fzf("files"), desc = "Find Files" },
      { "<leader>/", fzf("live_grep"), desc = "Grep" },
      { "<leader>,", fzf("buffers", { sort_mru = true, sort_lastused = true }), desc = "Buffers" },
      { "<leader>:", fzf("command_history"), desc = "Command History" },
      -- find
      { "<leader>ff", fzf("files"), desc = "Find Files" },
      { "<leader>fr", fzf("oldfiles"), desc = "Recent Files" },
      { "<leader>fR", fzf("oldfiles", { cwd_only = true }), desc = "Recent Files (cwd)" },
      { "<leader>fc", fzf("files", { cwd = vim.fn.stdpath("config") }), desc = "Find Config File" },
      { "<leader>fg", fzf("git_files"), desc = "Find Git Files" },
      { "<leader>fb", fzf("buffers"), desc = "Buffers" },
      -- git
      { "<leader>gs", fzf("git_status"), desc = "Git Status" },
      { "<leader>gl", fzf("git_commits"), desc = "Git Log" },
      { "<leader>gf", fzf("git_bcommits"), desc = "Git File History" },
      { "<leader>gL", fzf("git_bcommits"), mode = "x", desc = "Git History (Selection)" },
      { "<leader>gb", fzf("git_blame"), desc = "Git Blame (Search)" },
      { "<leader>gB", fzf("git_branches"), desc = "Git Branches" },
      -- search
      { "<leader>sb", fzf("blines"), desc = "Buffer Lines" },
      { "<leader>sw", fzf("grep_cword"), desc = "Grep Word" },
      { "<leader>sw", fzf("grep_visual"), mode = "x", desc = "Grep Selection" },
      { '<leader>s"', fzf("registers"), desc = "Registers" },
      { "<leader>sa", fzf("autocmds"), desc = "Autocmds" },
      { "<leader>sc", fzf("command_history"), desc = "Command History" },
      { "<leader>sC", fzf("commands"), desc = "Commands" },
      { "<leader>sd", fzf("diagnostics_document"), desc = "Document Diagnostics" },
      { "<leader>sD", fzf("diagnostics_workspace"), desc = "Workspace Diagnostics" },
      { "<leader>sh", fzf("helptags"), desc = "Help Pages" },
      { "<leader>sH", fzf("highlights"), desc = "Highlights" },
      { "<leader>sj", fzf("jumps"), desc = "Jumplist" },
      { "<leader>sk", fzf("keymaps"), desc = "Keymaps" },
      { "<leader>sl", fzf("loclist"), desc = "Location List" },
      { "<leader>sm", fzf("marks"), desc = "Marks" },
      { "<leader>sM", fzf("manpages"), desc = "Man Pages" },
      { "<leader>sq", fzf("quickfix"), desc = "Quickfix List" },
      { "<leader>sR", fzf("resume"), desc = "Resume" },
      { "<leader>ss", fzf("treesitter"), desc = "Symbols (Treesitter)" },
      { "<leader>su", "<cmd>packadd nvim.undotree | Undotree<cr>", desc = "Undo Tree" },
    },
  },

  -- 文件树（只当侧边栏用；目录 buffer 交给 oil）
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-mini/mini.icons" },
    keys = {
      {
        "<leader>e",
        function()
          local cmd = require("neo-tree.command")
          if vim.bo.filetype == "oil" then
            -- oil 里：以 oil 当前目录为根打开（oil:// 路径无法 reveal）
            cmd.execute({ toggle = true, dir = require("oil").get_current_dir() })
          else
            cmd.execute({ toggle = true, reveal = true })
          end
        end,
        desc = "File Explorer",
      },
      { "<leader>ge", "<cmd>Neotree float git_status<cr>", desc = "Git Explorer" },
      { "<leader>be", "<cmd>Neotree toggle buffers<cr>", desc = "Buffer Explorer" },
    },
    opts = {
      close_if_last_window = true,
      popup_border_style = "rounded",
      sources = { "filesystem", "buffers", "git_status" },
      open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "aerial" },
      filesystem = {
        bind_to_cwd = false,
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        hijack_netrw_behavior = "disabled",
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = true,
          hide_by_name = { ".git", "node_modules" },
          never_show = { ".DS_Store" },
        },
      },
      window = {
        width = 32,
        mappings = {
          ["l"] = "open",
          ["h"] = "close_node",
          ["<space>"] = "none",
          ["P"] = { "toggle_preview", config = { use_float = true } },
          -- 在编辑窗口里用 oil 打开选中的目录（选中文件时打开其所在目录）
          ["O"] = {
            function(state)
              local node = state.tree:get_node()
              local path = node.type == "directory" and node:get_id() or vim.fs.dirname(node:get_id())
              local target
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype ~= "neo-tree" and vim.api.nvim_win_get_config(win).relative == "" then
                  target = win
                  break
                end
              end
              if target then
                vim.api.nvim_set_current_win(target)
              else
                vim.cmd("botright vnew")
              end
              require("oil").open(path)
            end,
            desc = "Open in Oil",
          },
          ["Y"] = {
            function(state)
              local path = state.tree:get_node():get_id()
              vim.fn.setreg("+", path)
              vim.notify(path, vim.log.levels.INFO, { title = "Copied path" })
            end,
            desc = "Copy Path",
          },
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true,
          expander_collapsed = "\u{f460}",
          expander_expanded = "\u{f47c}",
          indent_marker = "│",
          last_indent_marker = "└",
        },
        modified = { symbol = "●" },
        git_status = {
          symbols = {
            added = "\u{f457}",
            modified = "\u{f459}",
            deleted = "\u{f458}",
            renamed = "󰁕",
            untracked = "\u{f128}",
            ignored = "\u{f474}",
            unstaged = "󰄱",
            staged = "\u{f00c}",
            conflict = "\u{e727}",
          },
        },
      },
    },
  },

  -- 目录 buffer：nvim 目录、:e 目录、gf 到目录都由 oil 打开，像编辑文本一样管理文件
  -- 不懒加载：必须在任何目录 buffer 出现前接管（加载约 1ms）
  {
    "stevearc/oil.nvim",
    lazy = false,
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open Parent Directory (Oil)" },
    },
    opts = {
      default_file_explorer = true,
      -- 顶部显示当前目录路径
      win_options = { winbar = "%!v:lua.require'ui.oil'.winbar()" },
      columns = { "icon" },
      skip_confirm_for_simple_edits = true,
      watch_for_changes = true,
      view_options = {
        show_hidden = true,
        is_always_hidden = function(name)
          return name == ".." or name == ".git"
        end,
      },
      float = { border = "rounded", max_width = 100, max_height = 30 },
      confirmation = { border = "rounded" },
      keymaps = {
        -- 让出与全局按键冲突的默认键：<C-h>/<C-l> 切窗口、<C-s> 保存（在 oil 里即应用修改）
        ["<C-h>"] = false,
        ["<C-l>"] = false,
        ["<C-s>"] = false,
        ["<C-p>"] = false,
        ["<C-v>"] = { "actions.select", opts = { vertical = true }, desc = "Open in Vertical Split" },
        ["<C-x>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in Horizontal Split" },
        ["P"] = "actions.preview",
        ["R"] = "actions.refresh",
        ["q"] = "actions.close",
      },
    },
  },

  -- 符号大纲
  {
    "stevearc/aerial.nvim",
    event = "LspAttach",
    cmd = { "AerialToggle", "AerialOpen" },
    keys = { { "<leader>cs", "<cmd>AerialToggle<cr>", desc = "Symbols Outline" } },
    opts = {
      backends = { "lsp", "treesitter", "markdown", "man" },
      layout = {
        default_direction = "right",
        min_width = 30,
        max_width = { 40, 0.2 },
        win_opts = {
          winhl = "Normal:UiSidebar,NormalNC:UiSidebar,EndOfBuffer:UiSidebar,WinSeparator:UiSidebarSeparator,SignColumn:UiSidebar",
        },
      },
      attach_mode = "global",
      show_guides = true,
      highlight_on_hover = true,
      filter_kind = false,
      guides = { mid_item = "├╴", last_item = "└╴", nested_top = "│ ", whitespace = "  " },
      on_attach = function(buf)
        vim.keymap.set("n", "{", "<cmd>AerialPrev<cr>", { buffer = buf, desc = "Prev Symbol" })
        vim.keymap.set("n", "}", "<cmd>AerialNext<cr>", { buffer = buf, desc = "Next Symbol" })
      end,
    },
  },

  -- 跳转
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter Search",
      },
      {
        "<c-s>",
        mode = "c",
        function()
          require("flash").toggle()
        end,
        desc = "Toggle Flash Search",
      },
    },
  },

  -- 预览定义 / 引用（VSCode peek 风格）
  {
    "dnlhc/glance.nvim",
    cmd = "Glance",
    keys = {
      { "gpd", "<cmd>Glance definitions<cr>", desc = "Peek Definition" },
      { "gpr", "<cmd>Glance references<cr>", desc = "Peek References" },
      { "gpi", "<cmd>Glance implementations<cr>", desc = "Peek Implementations" },
      { "gpy", "<cmd>Glance type_definitions<cr>", desc = "Peek Type Definitions" },
    },
    opts = {
      height = 20,
      border = { enable = true, top_char = "─", bottom_char = "─" },
      theme = { enable = false },
      list = { position = "right", width = 0.33 },
      preview_win_opts = { cursorline = true, number = true, wrap = false },
      folds = { fold_closed = "\u{f460}", fold_open = "\u{f47c}", folded = true },
      indent_lines = { enable = true, icon = "│" },
      winbar = { enable = true },
    },
  },
}
