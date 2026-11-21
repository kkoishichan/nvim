local prettier = { "prettierd", "prettier", stop_after_first = true }

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    dependencies = { "mason-org/mason.nvim" },
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true })
        end,
        mode = { "n", "x" },
        desc = "Format",
      },
    },
    init = function()
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
    end,
    opts = {
      default_format_opts = { lsp_format = "fallback" },
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_organize_imports", "ruff_format" },
        javascript = prettier,
        javascriptreact = prettier,
        typescript = prettier,
        typescriptreact = prettier,
        vue = prettier,
        html = prettier,
        css = prettier,
        scss = prettier,
        json = prettier,
        jsonc = prettier,
        yaml = prettier,
        markdown = prettier,
        sh = { "shfmt" },
        bash = { "shfmt" },
        go = { "goimports", "gofumpt" },
        rust = { "rustfmt" },
        tex = { "latexindent" },
        typst = { "typstyle" },
        -- c/cpp/toml 使用 LSP（clangd / taplo）格式化
      },
      format_on_save = function(buf)
        if not vim.g.autoformat or vim.b[buf].autoformat == false or vim.b[buf].bigfile then
          return
        end
        return { timeout_ms = 1500 }
      end,
    },
  },
}
