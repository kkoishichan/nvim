local ensure = {
  "bash",
  "bibtex",
  "c",
  "cpp",
  "css",
  "diff",
  "dockerfile",
  "git_config",
  "git_rebase",
  "gitcommit",
  "gitignore",
  "go",
  "gomod",
  "gosum",
  "gowork",
  "html",
  "javascript",
  "jsdoc",
  "json",
  "lua",
  "luadoc",
  "luap",
  "make",
  "markdown",
  "markdown_inline",
  "printf",
  "python",
  "query",
  "regex",
  "rust",
  "scss",
  "sql",
  "toml",
  "tsx",
  "typescript",
  "typst",
  "vim",
  "vimdoc",
  "xml",
  "yaml",
}

-- 这些文件类型用其他方式高亮（LaTeX 用 vimtex 的语法高亮）
local skip_highlight = { tex = true, latex = true, bigfile = true }

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      ts.setup()

      local installed = {}
      for _, lang in ipairs(ts.get_installed()) do
        installed[lang] = true
      end
      local missing = vim.tbl_filter(function(lang)
        return not installed[lang]
      end, ensure)
      if #missing > 0 then
        ts.install(missing)
      end

      local function attach(buf, lang)
        if not vim.api.nvim_buf_is_valid(buf) or not pcall(vim.treesitter.start, buf, lang) then
          return false
        end
        if vim.treesitter.query.get(lang, "indents") then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
        return true
      end

      local available
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_treesitter", { clear = true }),
        callback = function(ev)
          if skip_highlight[ev.match] then
            return
          end
          local lang = vim.treesitter.language.get_lang(ev.match)
          if not lang then
            return
          end
          if vim.treesitter.language.add(lang) then
            attach(ev.buf, lang)
            return
          end
          -- 没装过的语言：自动安装 parser，装好后启用
          available = available or ts.get_available()
          if vim.tbl_contains(available, lang) then
            ts.install(lang):await(function()
              vim.schedule(function()
                attach(ev.buf, lang)
              end)
            end)
          else
            vim.opt_local.foldmethod = "indent"
          end
        end,
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = "VeryLazy",
    config = function()
      require("nvim-treesitter-textobjects").setup({ move = { set_jumps = true } })
      local move = require("nvim-treesitter-textobjects.move")
      local maps = { f = "@function.outer", c = "@class.outer", a = "@parameter.inner" }
      for key, query in pairs(maps) do
        local function go(fn, native)
          return function()
            -- diff 模式下 ]c/[c 保留原生的跳改动块
            if key == "c" and vim.wo.diff then
              return vim.cmd("normal! " .. native)
            end
            move[fn](query, "textobjects")
          end
        end
        local name = query:gsub("@", ""):gsub("%..*", "")
        vim.keymap.set(
          { "n", "x", "o" },
          "]" .. key,
          go("goto_next_start", "]c"),
          { desc = "Next " .. name .. " start" }
        )
        vim.keymap.set(
          { "n", "x", "o" },
          "[" .. key,
          go("goto_previous_start", "[c"),
          { desc = "Prev " .. name .. " start" }
        )
        vim.keymap.set(
          { "n", "x", "o" },
          "]" .. key:upper(),
          go("goto_next_end", "]c"),
          { desc = "Next " .. name .. " end" }
        )
        vim.keymap.set(
          { "n", "x", "o" },
          "[" .. key:upper(),
          go("goto_previous_end", "[c"),
          { desc = "Prev " .. name .. " end" }
        )
      end
    end,
  },
}
