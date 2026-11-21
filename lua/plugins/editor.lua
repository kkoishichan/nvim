return {
  -- 文本对象（配合 treesitter）
  {
    "nvim-mini/mini.ai",
    event = "VeryLazy",
    dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
    opts = function()
      local ai = require("mini.ai")
      return {
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          }),
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
          a = ai.gen_spec.treesitter({ a = "@parameter.outer", i = "@parameter.inner" }),
          t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
          d = { "%f[%d]%d+" },
          u = ai.gen_spec.function_call(),
          U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
          g = function()
            local from = { line = 1, col = 1 }
            local to = { line = vim.fn.line("$"), col = math.max(vim.fn.getline("$"):len(), 1) }
            return { from = from, to = to }
          end,
        },
      }
    end,
  },

  -- 包围符：gsa 添加 / gsd 删除 / gsr 替换
  {
    "nvim-mini/mini.surround",
    keys = {
      { "gsa", mode = { "n", "x" }, desc = "Add Surrounding" },
      { "gsd", desc = "Delete Surrounding" },
      { "gsf", desc = "Find Right Surrounding" },
      { "gsF", desc = "Find Left Surrounding" },
      { "gsh", desc = "Highlight Surrounding" },
      { "gsr", desc = "Replace Surrounding" },
      { "gsn", desc = "Update n_lines" },
    },
    opts = {
      mappings = {
        add = "gsa",
        delete = "gsd",
        find = "gsf",
        find_left = "gsF",
        highlight = "gsh",
        replace = "gsr",
        update_n_lines = "gsn",
      },
    },
  },

  -- 自动括号
  {
    "nvim-mini/mini.pairs",
    event = "InsertEnter",
    opts = { modes = { insert = true, command = true, terminal = false } },
  },

  -- 关闭 buffer 而不打乱窗口布局
  {
    "nvim-mini/mini.bufremove",
    keys = {
      {
        "<leader>bd",
        function()
          require("mini.bufremove").delete(0, false)
        end,
        desc = "Delete Buffer",
      },
      {
        "<leader>bD",
        function()
          require("mini.bufremove").delete(0, true)
        end,
        desc = "Delete Buffer (Force)",
      },
    },
  },

  -- 多光标
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    keys = function()
      local function mc(fn, ...)
        local args = { ... }
        return function()
          require("multicursor-nvim")[fn](unpack(args))
        end
      end
      return {
        { "<C-n>", mc("matchAddCursor", 1), mode = { "n", "x" }, desc = "Add Cursor (Next Match)" },
        { "<C-p>", mc("matchAddCursor", -1), mode = { "n", "x" }, desc = "Add Cursor (Prev Match)" },
        { "<leader>ms", mc("matchSkipCursor", 1), mode = { "n", "x" }, desc = "Skip Next Match" },
        { "<leader>mS", mc("matchSkipCursor", -1), mode = { "n", "x" }, desc = "Skip Prev Match" },
        { "<leader>mA", mc("matchAllAddCursors"), mode = { "n", "x" }, desc = "Add Cursors (All Matches)" },
        { "<C-Up>", mc("lineAddCursor", -1), mode = { "n", "x" }, desc = "Add Cursor Above" },
        { "<C-Down>", mc("lineAddCursor", 1), mode = { "n", "x" }, desc = "Add Cursor Below" },
        { "<C-q>", mc("toggleCursor"), mode = { "n", "x" }, desc = "Toggle Cursor" },
        { "<C-LeftMouse>", mc("handleMouse"), desc = "Add/Remove Cursor" },
        { "<C-LeftDrag>", mc("handleMouseDrag") },
        { "<C-LeftRelease>", mc("handleMouseRelease") },
      }
    end,
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      mc.addKeymapLayer(function(set)
        set({ "n", "x" }, "<left>", mc.prevCursor)
        set({ "n", "x" }, "<right>", mc.nextCursor)
        set({ "n", "x" }, "<leader>x", mc.deleteCursor)
        set("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)
    end,
  },

  -- 全局搜索替换
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = { headerMaxWidth = 80 },
    keys = {
      {
        "<leader>sr",
        function()
          local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
          require("grug-far").open({
            transient = true,
            prefills = { filesFilter = ext and ext ~= "" and "*." .. ext or nil },
          })
        end,
        mode = { "n", "x" },
        desc = "Search and Replace",
      },
    },
  },

  -- HTML/JSX 标签自动闭合与重命名
  { "windwp/nvim-ts-autotag", event = "VeryLazy", opts = {} },

  -- 嵌入语言中正确的注释符号（配合内置 gc）
  { "folke/ts-comments.nvim", event = "VeryLazy", opts = {} },

  -- TODO 高亮
  {
    "folke/todo-comments.nvim",
    event = "VeryLazy",
    cmd = { "TodoTrouble", "TodoFzfLua" },
    opts = {},
    keys = {
      {
        "]t",
        function()
          require("todo-comments").jump_next()
        end,
        desc = "Next Todo",
      },
      {
        "[t",
        function()
          require("todo-comments").jump_prev()
        end,
        desc = "Prev Todo",
      },
      { "<leader>st", "<cmd>TodoFzfLua<cr>", desc = "Todo" },
      { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Todo (Trouble)" },
    },
  },

  -- 会话
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    keys = {
      {
        "<leader>qs",
        function()
          require("persistence").load()
        end,
        desc = "Restore Session",
      },
      {
        "<leader>qS",
        function()
          require("persistence").select()
        end,
        desc = "Select Session",
      },
      {
        "<leader>ql",
        function()
          require("persistence").load({ last = true })
        end,
        desc = "Restore Last Session",
      },
      {
        "<leader>qd",
        function()
          require("persistence").stop()
        end,
        desc = "Don't Save Current Session",
      },
    },
  },
}
