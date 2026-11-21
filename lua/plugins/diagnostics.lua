return {
  -- 行内诊断气泡
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "LspAttach",
    priority = 1000,
    opts = function()
      local p = require("ui").palette
      return {
        preset = "modern",
        hi = { mixing_color = p and p.bg or "None" },
        options = {
          show_source = { enabled = true, if_many = true },
          multilines = { enabled = true },
          show_all_diags_on_cursorline = true,
          throttle = 20,
          overflow = { mode = "wrap" },
        },
      }
    end,
    config = function(_, opts)
      local tiny = require("tiny-inline-diagnostic")
      tiny.setup(opts)
      -- 混合色始终用调色板保存的 bg（透明模式下 Normal 没有背景色可取）
      vim.api.nvim_create_autocmd("User", {
        pattern = "UiRefresh",
        group = vim.api.nvim_create_augroup("user_tiny_inline", { clear = true }),
        callback = function()
          local cfg, p = tiny.config, require("ui").palette
          if cfg and p then
            cfg.hi.mixing_color = p.bg
            require("tiny-inline-diagnostic.highlights").setup_highlights(cfg.blend, cfg.hi, cfg.transparent_bg)
          end
        end,
      })
      -- <leader>uv：在气泡和行下虚拟行之间切换
      vim.keymap.set("n", "<leader>uv", function()
        local lines = not vim.diagnostic.config().virtual_lines
        vim.diagnostic.config({ virtual_lines = lines and { current_line = false } or false })
        if lines then
          require("tiny-inline-diagnostic").disable()
        else
          require("tiny-inline-diagnostic").enable()
        end
      end, { desc = "Toggle Diagnostic Style" })
    end,
  },

  -- 诊断面板
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = { focus = true },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
      { "<leader>xs", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols (Trouble)" },
      { "<leader>xL", "<cmd>Trouble lsp toggle<cr>", desc = "LSP References/Definitions (Trouble)" },
      { "<leader>xl", "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List (Trouble)" },
    },
  },
}
