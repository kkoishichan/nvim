local icons = require("config.icons")

-- 由 mason 安装的语言服务（mason-lspconfig 会自动启用）
local mason_servers = {
  "lua_ls",
  "basedpyright",
  "ruff",
  "vtsls",
  "html",
  "cssls",
  "clangd",
  "bashls",
  "jsonls",
  "yamlls",
  "taplo",
  "marksman",
  "texlab",
}

-- 使用系统已安装的语言服务
local system_servers = { "gopls", "rust_analyzer", "tinymist" }

-- 由 mason 安装的格式化工具
local mason_tools = { "stylua", "prettierd", "shfmt", "gofumpt", "goimports" }

local function server_configs()
  return {
    lua_ls = {
      settings = {
        Lua = {
          workspace = { checkThirdParty = false },
          completion = { callSnippet = "Replace" },
          hint = { enable = true, setType = false, paramType = true, arrayIndex = "Disable" },
          doc = { privateName = { "^_" } },
        },
      },
    },
    basedpyright = {
      settings = { basedpyright = { analysis = { typeCheckingMode = "standard" } } },
    },
    vtsls = {
      settings = {
        complete_function_calls = true,
        vtsls = {
          enableMoveToFileCodeAction = true,
          autoUseWorkspaceTsdk = true,
          experimental = { completion = { enableServerSideFuzzyMatch = true } },
        },
        typescript = {
          updateImportsOnFileMove = { enabled = "always" },
          suggest = { completeFunctionCalls = true },
          inlayHints = {
            enumMemberValues = { enabled = true },
            functionLikeReturnTypes = { enabled = true },
            parameterNames = { enabled = "literals" },
            parameterTypes = { enabled = true },
            propertyDeclarationTypes = { enabled = true },
            variableTypes = { enabled = false },
          },
        },
      },
    },
    clangd = {
      cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
        "--fallback-style=llvm",
      },
    },
    jsonls = {
      before_init = function(_, config)
        config.settings.json.schemas = require("schemastore").json.schemas()
      end,
      settings = { json = { validate = { enable = true } } },
    },
    yamlls = {
      before_init = function(_, config)
        config.settings.yaml.schemas = require("schemastore").yaml.schemas()
      end,
      settings = { yaml = { keyOrdering = false, schemaStore = { enable = false, url = "" } } },
    },
    gopls = {
      settings = {
        gopls = {
          gofumpt = true,
          staticcheck = true,
          usePlaceholders = true,
          completeUnimported = true,
          semanticTokens = true,
          analyses = { unusedparams = true, nilness = true, unusedwrite = true, useany = true },
          hints = {
            assignVariableTypes = true,
            compositeLiteralFields = true,
            compositeLiteralTypes = true,
            constantValues = true,
            functionTypeParameters = true,
            parameterNames = true,
            rangeVariableTypes = true,
          },
        },
      },
    },
    rust_analyzer = {
      settings = {
        ["rust-analyzer"] = {
          check = { command = "clippy" },
          cargo = { allFeatures = true },
          procMacro = { enable = true },
        },
      },
    },
    texlab = {
      settings = {
        texlab = {
          build = { onSave = false }, -- 编译交给 vimtex
          chktex = { onOpenAndSave = true, onEdit = false },
        },
      },
    },
    tinymist = {
      -- PDF 只在按 \c / \v 时导出；格式化交给 conform + typstyle
      settings = { exportPdf = "never", formatterMode = "disable" },
    },
  }
end

local function on_attach(client, buf)
  local function map(lhs, rhs, desc, mode)
    vim.keymap.set(mode or "n", lhs, rhs, { buffer = buf, desc = desc })
  end
  local function fzf(cmd, opts)
    return function()
      require("fzf-lua")[cmd](opts or {})
    end
  end

  map("gd", fzf("lsp_definitions"), "Goto Definition")
  map("grr", fzf("lsp_references", { ignore_current_line = true, includeDeclaration = false }), "References")
  map("gI", fzf("lsp_implementations"), "Goto Implementation")
  map("gy", fzf("lsp_typedefs"), "Goto Type Definition")
  map("gD", vim.lsp.buf.declaration, "Goto Declaration")
  map("<leader>ca", vim.lsp.buf.code_action, "Code Action", { "n", "x" })
  map("<leader>cA", function()
    vim.lsp.buf.code_action({ context = { only = { "source" }, diagnostics = {} } })
  end, "Source Action")
  map("<leader>cr", vim.lsp.buf.rename, "Rename")
  map("<leader>cl", "<cmd>checkhealth vim.lsp<cr>", "LSP Info")
  map("<leader>ss", fzf("lsp_document_symbols"), "Symbols")
  map("<leader>sS", fzf("lsp_live_workspace_symbols"), "Workspace Symbols")

  -- ruff 只负责 lint 和格式化，hover 交给 basedpyright
  if client.name == "ruff" then
    client.server_capabilities.hoverProvider = false
  end

  -- 光标下同名词高亮
  if client:supports_method("textDocument/documentHighlight", buf) then
    local group = vim.api.nvim_create_augroup("user_lsp_highlight_" .. buf, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = buf,
      callback = vim.lsp.buf.document_highlight,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
      group = group,
      buffer = buf,
      callback = vim.lsp.buf.clear_references,
    })
  end

  -- 折叠优先使用 LSP
  if client:supports_method("textDocument/foldingRange", buf) then
    local win = vim.fn.bufwinid(buf)
    if win ~= -1 then
      vim.wo[win][0].foldmethod = "expr"
      vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
    end
  end
end

return {
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    build = ":MasonUpdate",
    opts = {
      ui = {
        border = "rounded",
        icons = { package_installed = "\u{f00c}", package_pending = "\u{f110}", package_uninstalled = "\u{f00d}" },
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)
      -- 启动 3 秒后再检查并安装缺失的格式化工具，不占用启动时间
      vim.defer_fn(function()
        local registry = require("mason-registry")
        registry.refresh(function()
          for _, tool in ipairs(mason_tools) do
            local ok, pkg = pcall(registry.get_package, tool)
            if ok and not pkg:is_installed() and not pkg:is_installing() then
              pkg:install()
            end
          end
        end)
      end, 3000)
    end,
  },

  {
    "neovim/nvim-lspconfig",
    -- 第一帧画完后再启动 LSP（vim.lsp.enable 会连接已打开的 buffer）
    event = "VeryLazy",
    dependencies = {
      "mason-org/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
      { "b0o/SchemaStore.nvim", lazy = true },
    },
    config = function()
      vim.diagnostic.config({
        severity_sort = true,
        underline = true,
        update_in_insert = false,
        virtual_text = false, -- 由 tiny-inline-diagnostic 显示
        float = { border = "rounded", source = "if_many" },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
            [vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
            [vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
            [vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
          },
          numhl = {
            [vim.diagnostic.severity.ERROR] = "DiagnosticError",
            [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
            [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
            [vim.diagnostic.severity.HINT] = "DiagnosticHint",
          },
        },
      })

      for name, config in pairs(server_configs()) do
        vim.lsp.config(name, config)
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
        callback = function(ev)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client then
            on_attach(client, ev.buf)
          end
        end,
      })

      require("mason-lspconfig").setup({
        ensure_installed = mason_servers,
        automatic_enable = { exclude = { "stylua" } }, -- stylua 由 conform 调用
      })

      for _, name in ipairs(system_servers) do
        local cmd = vim.lsp.config[name] and vim.lsp.config[name].cmd
        if type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1 then
          vim.lsp.enable(name)
        end
      end
    end,
  },

  -- 编辑 Neovim 配置时补全 vim.* API
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = { { path = "${3rd}/luv/library", words = { "vim%.uv" } } },
    },
  },
}
