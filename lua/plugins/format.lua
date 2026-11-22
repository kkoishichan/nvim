local prettier = { "prettierd", "prettier", stop_after_first = true }

-- Biome 能处理的文件类型：项目有 Biome 配置时用 Biome，否则用 Prettier
local biome_files = { "biome.json", "biome.jsonc", ".biome.json", ".biome.jsonc" }
local function web(buf)
  if vim.fs.root(buf, biome_files) then
    -- 优先用项目 node_modules 里的；找不到时只提示，不改用 Prettier 或 LSP 格式化
    if not vim.b[buf].biome_warned and not require("conform").get_formatter_info("biome", buf).available then
      vim.b[buf].biome_warned = true
      vim.notify(
        "项目使用 Biome，但找不到 biome（先安装项目依赖），本文件暂不格式化",
        vim.log.levels.WARN
      )
    end
    return { "biome", lsp_format = "never" }
  end
  return prettier
end

-- ruff 优先用项目虚拟环境里的版本
local function ruff(_, ctx)
  return require("config.project").venv_bin("ruff", ctx.dirname) or "ruff"
end

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
        javascript = web,
        javascriptreact = web,
        typescript = web,
        typescriptreact = web,
        json = web,
        jsonc = web,
        css = web,
        vue = prettier,
        html = prettier,
        scss = prettier,
        yaml = prettier,
        markdown = prettier,
        sh = { "shfmt" },
        bash = { "shfmt" },
        go = { "goimports", "gofumpt" },
        rust = { "rustfmt" },
        tex = { "latexindent" },
        typst = { "typstyle" },
        sql = { "sql_formatter" },
        -- c/cpp/toml 使用 LSP（clangd / taplo）格式化
      },
      formatters = {
        ruff_format = { command = ruff },
        ruff_organize_imports = { command = ruff },
        -- 在文件所在项目里查找 .sql-formatter.json（可设置方言，如 {"language": "postgresql"}）
        sql_formatter = {
          cwd = function(_, ctx)
            return vim.fs.root(ctx.dirname, { ".sql-formatter.json" })
          end,
        },
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
