local lazygit

return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      { "<C-/>", "<cmd>ToggleTerm direction=float<cr>", mode = { "n", "t" }, desc = "Terminal" },
      { "<C-_>", "<cmd>ToggleTerm direction=float<cr>", mode = { "n", "t" }, desc = "which_key_ignore" },
      {
        "<leader>gg",
        function()
          if not lazygit then
            lazygit = require("toggleterm.terminal").Terminal:new({
              cmd = "lazygit",
              direction = "float",
              hidden = true,
              float_opts = { width = math.floor(vim.o.columns * 0.9), height = math.floor(vim.o.lines * 0.9) },
              on_open = function(term)
                -- lazygit 自己要用 Esc，不要被双击 Esc 截走
                vim.keymap.set("t", "<esc>", "<esc>", { buffer = term.bufnr, nowait = true })
              end,
            })
          end
          lazygit:toggle()
        end,
        desc = "Lazygit",
      },
    },
    opts = {
      direction = "float",
      shade_terminals = false,
      float_opts = { border = "rounded", winblend = 0 },
      highlights = {
        NormalFloat = { link = "NormalFloat" },
        FloatBorder = { link = "FloatBorder" },
      },
    },
  },
}
