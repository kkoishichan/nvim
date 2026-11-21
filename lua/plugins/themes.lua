-- 所有主题都懒加载：执行 :colorscheme 时由 lazy.nvim 自动加载对应插件
-- 主题只负责配色，界面样式和透明由 lua/ui 统一处理，所以这里都用默认的不透明配置
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = true,
    opts = {
      term_colors = true,
      styles = { comments = { "italic" }, keywords = { "italic" } },
      auto_integrations = true,
    },
  },
  { "folke/tokyonight.nvim", lazy = true, opts = { style = "night" } },
  { "rebelot/kanagawa.nvim", lazy = true, opts = { compile = false } },
  { "rose-pine/neovim", name = "rose-pine", lazy = true, opts = {} },
  { "EdenEast/nightfox.nvim", lazy = true },
  {
    "sainnhe/gruvbox-material",
    lazy = true,
    init = function()
      vim.g.gruvbox_material_better_performance = 1
      vim.g.gruvbox_material_enable_italic = 1
      vim.g.gruvbox_material_foreground = "material"
    end,
  },
  {
    "sainnhe/everforest",
    lazy = true,
    init = function()
      vim.g.everforest_better_performance = 1
      vim.g.everforest_enable_italic = 1
    end,
  },
  { "olimorris/onedarkpro.nvim", lazy = true },
}
