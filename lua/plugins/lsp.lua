local icons = require("config.icons")
local project = require("config.project")

-- 工具查找顺序：项目本地（.venv / node_modules）→ 系统 → mason（PATH 末尾，作后备）

-- 官方源（pacman）里有的用系统版本，跟随系统更新；只有 AUR 才有的由 mason 安装

-- 由 mason 安装的语言服务（mason-lspconfig 会自动启用）
local mason_servers = {
  "basedpyright",
  "vtsls",
  "eslint", -- 只在有 ESLint 配置的项目里启动，加载项目自己的 ESLint
  "html",
  "cssls",
  "jsonls",
}

-- 只用系统或项目里的语言服务：值为检测用的可执行文件；
-- false 表示总是启用（服务自己判断项目是否适用，并优先用项目里的版本）
local system_servers = {
  lua_ls = "lua-language-server",
  clangd = "clangd",
  gopls = "gopls",
  rust_analyzer = "rust-analyzer",
  ruff = "ruff",
  bashls = "bash-language-server",
  yamlls = "yaml-language-server",
  taplo = "taplo",
  marksman = "marksman",
  texlab = "texlab",
  tinymist = "tinymist",
  dockerls = "docker-langserver", -- Dockerfile（compose 文件由 yamlls 按 schema 校验）
  biome = false, -- 只在有 Biome 配置的项目里启动
}

-- 由 mason 安装的格式化工具（stylua、shfmt、gofumpt、goimports 等用系统的）
local mason_tools = { "prettierd", "sql-formatter" }

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
    -- Python 工具优先用项目虚拟环境里的版本
    basedpyright = {
      cmd = project.venv_cmd("basedpyright-langserver", { "--stdio" }),
      settings = { basedpyright = { analysis = { typeCheckingMode = "standard" } } },
    },
    ruff = {
      cmd = project.venv_cmd("ruff", { "server" }),
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

---跳到当前高亮的第 count 个同名引用（负数向前）
local function reference_jump(buf, count)
  local ns = vim.api.nvim_get_namespaces()["nvim.lsp.references"]
  local pos = {} ---@type {[1]:integer, [2]:integer}[]
  for _, m in ipairs(ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or {}) do
    local last = pos[#pos]
    if not (last and last[1] == m[2] and last[2] == m[3]) then -- 去重（按位置）
      pos[#pos + 1] = { m[2], m[3] }
    end
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local row, col = cur[1] - 1, cur[2]
  local idx = 0 -- 光标所在或之前的最后一个引用
  for i, p in ipairs(pos) do
    if p[1] < row or (p[1] == row and p[2] <= col) then
      idx = i
    end
  end
  local target = pos[idx + count]
  if not target or (target[1] == row and target[2] == col) then
    return
  end
  vim.cmd("normal! m'")
  vim.b[buf].reference_jump = true -- 跳到的是同一个符号，下一次光标移动不清除高亮
  vim.api.nvim_win_set_cursor(0, { target[1] + 1, target[2] })
  vim.cmd("normal! zv")
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

  -- 光标下同名词高亮：停下时高亮，移动时清除（不在每次移动时扫描引用列表，引用很多时滚动也不卡）
  if client:supports_method("textDocument/documentHighlight", buf) then
    local group = vim.api.nvim_create_augroup("user_lsp_highlight_" .. buf, { clear = true })
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = group,
      buffer = buf,
      callback = function()
        vim.lsp.buf.clear_references() -- 先清除，避免新旧结果叠加
        vim.lsp.buf.document_highlight()
      end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
      group = group,
      buffer = buf,
      callback = function()
        -- ]] / [[ 跳到的仍是同一个符号，保留高亮以便连续跳转
        if vim.b[buf].reference_jump then
          vim.b[buf].reference_jump = false
          return
        end
        vim.lsp.buf.clear_references()
      end,
    })
    map("]]", function()
      reference_jump(buf, vim.v.count1)
    end, "Next Reference")
    map("[[", function()
      reference_jump(buf, -vim.v.count1)
    end, "Prev Reference")
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
      PATH = "append", -- 系统和项目里有的工具优先，mason 只作后备
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
        automatic_enable = mason_servers, -- 只启用列表里的，mason 里残留的其他包不会被自动启用
      })

      for name, bin in pairs(system_servers) do
        if bin == false or vim.fn.executable(bin) == 1 then
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
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
        { path = "snacks.nvim", words = { "Snacks" } },
      },
    },
  },
}
