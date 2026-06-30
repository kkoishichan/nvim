# Neovim 配置

一份现代化的个人 Neovim 配置，目标是在保留 Vim 编辑模型的前提下，把
Neovim 打磨成接近 IDE 的日常工作流。

- `lazy.nvim` 管理插件，首次启动自动 bootstrap。
- `gruvbox` 主题，`<Space>` 作为 leader，`\` 作为 localleader。
- `fzf-lua` 负责查找、搜索、LSP / Git 列表，并接管 `vim.ui.select`。
- `oil.nvim` 像编辑 buffer 一样管理文件系统；`neo-tree.nvim` 提供侧边文件树。
- `blink.cmp` 负责补全、snippet、签名帮助。
- `nvim-lspconfig` + Mason 负责语言服务与外部工具安装。
- `conform.nvim` 格式化，`nvim-lint` 静态检查。
- `nvim-ufo` + Tree-sitter 折叠。
- `toggleterm.nvim` 提供 VSCode 风格的多终端管理。
- `overseer.nvim` 任务运行，`neotest` 测试，`nvim-dap` + `dap-ui` 调试。
- `snacks.nvim` dashboard、通知、各类小工具。

当前在 Neovim `0.12.x` 上验证，建议使用 `0.11+`。

## 依赖

必需：

- Neovim `>= 0.11`
- `git`、C 编译器（Tree-sitter 编译 parser 用）
- `ripgrep`、`fd`（fzf-lua 查找 / grep）
- 一款 Nerd Font 字体（图标显示）

推荐：

- `kitty` 终端（内联图片 / PDF 预览基于 kitty graphics）
- `poppler`（`pdftoppm`，PDF 预览渲染）
- `lazygit`、`node` + `yarn`（markdown / typst 预览）、`latexmk`、`tinymist`

其余语言服务器、formatter、linter、DAP 适配器由 Mason 在需要时安装。

## 目录结构

```text
~/.config/nvim
├── init.lua              -- 入口：leader、加载 core 与 lazy
├── lazy-lock.json
├── lua/user
│   ├── lazy.lua          -- lazy.nvim bootstrap 与 setup
│   ├── core
│   │   ├── options.lua       -- vim 选项
│   │   ├── keymaps.lua       -- 全局非插件键位
│   │   ├── commands.lua      -- 自定义命令
│   │   ├── autocmds.lua      -- 自动命令（外部改动 / 密钥保护 / PDF 预览）
│   │   ├── diagnostics.lua   -- 诊断 UI
│   │   ├── layout.lua        -- 窗口布局工具
│   │   ├── panels.lua        -- 侧边面板尺寸常量
│   │   └── pdf.lua           -- PDF 预览状态
│   └── plugins               -- 每个文件一组插件 spec
│       ├── ui.lua            -- dashboard / lualine / bufferline / notify / which-key
│       ├── navigation.lua    -- oil / neo-tree / outline / flash
│       ├── picker.lua        -- fzf-lua
│       ├── terminal.lua      -- toggleterm 多终端管理
│       ├── lsp.lua  completion.lua  formatting.lua  lint.lua
│       ├── dap.lua  test.lua  tasks.lua
│       ├── treesitter.lua  folding.lua  editor.lua  multicursor.lua
│       ├── git.lua  media.lua  lang.lua  tools.lua  performance.lua
```

## 首次启动

把配置放到 `~/.config/nvim`，然后：

```bash
nvim
```

首次启动会自动安装 `lazy.nvim` 与全部插件。之后可在 Neovim 内：

```vim
:Lazy                 " 插件管理
:Mason                " 语言服务 / 工具安装
:MasonToolsInstall    " 批量安装预设工具
:checkhealth          " 健康检查
```

## 键位

`leader` = `<Space>`，`localleader` = `\`。下面是各组入口，完整列表见
`:WhichKey` 或下方的 cheatsheet。

| 键 | 作用 |
| --- | --- |
| `<leader><Space>` | 智能查找（文件 / `` ` ``buffer / `@`符号 / `#`工作区符号 / `:N`行） |
| `<leader>/` | 全局 grep |
| `<leader>,` | buffer 列表 |
| `<leader>:` | 命令历史 |
| `<leader>?` | 键位 cheatsheet |
| `<leader>f` | 查找组（files / grep / help / keymaps / oldfiles …） |
| `<leader>g` | Git 组（commits / status …） |
| `<leader>e` | neo-tree 文件树 |
| `<leader>E` | oil 编辑项目目录 |
| `<leader>o` | 符号大纲（outline） |
| `<leader>t` | 终端组 |
| `<leader>j` | 任务组（overseer） |
| `<leader>u` | UI / toggle 组 |

常用单键 / 其他：

- `-` ：oil 编辑当前目录
- `s` / `S` ：flash 跳转 / treesitter 跳转
- `<M-1>` … `<M-9>` ：跳到第 N 个 buffer，`<M-0>` 跳到最后一个
- `<C-/>` ：切换底部终端
- `zR` / `zM` / `zr` / `zm` / `zK` ：折叠开关与预览

### 终端（VSCode 风格）

`toggleterm.nvim` 之上自建的多终端管理：

| 键 | 作用 |
| --- | --- |
| `<C-/>` | 切换底部终端 |
| `<leader>tt` | 切换底部终端 |
| `<leader>tn` | 新建终端 |
| `<leader>ts` | 分屏新终端 |
| `<leader>t]` / `<leader>t[` | 下一个 / 上一个终端 |
| `<leader>tl` | 选择终端（`:TermSelect`） |
| `<leader>tk` | 关闭当前终端 |
| `<leader>tr` | 重命名终端 |
| `<leader>tf` | 浮动终端 |

终端模式内：`<Esc><Esc>` 回到普通模式，`<C-hjkl>` / `<C-方向键>` 切换窗口，
普通模式 `q` 关闭。

## 语言支持

LSP、formatter、linter、DAP 适配器经由 Mason 安装；已配置：

- Lua（`lazydev` 增强）、Python（`dap-python` / `neotest-python`）
- Go（`dap-go` / `neotest-golang`）、Rust（`rustaceanvim`）
- JS/TS（`dap-vscode-js` / `neotest-jest` / `neotest-vitest`）
- LaTeX（`vimtex`）、Typst（`typst-preview`）、Markdown（`markview` / 预览）

## 值得注意的子系统

- **外部改动处理**：文件在磁盘上被外部修改时自动检测并提示重载。
- **密钥保护**：对 `.env`、`*.pem`、`*.key`、`*/.ssh/*`、`*/.aws/credentials`、
  以及含 `secret` / `password` / `credentials` 的路径，自动禁用 `undofile`
  与 `swapfile`，避免敏感内容落盘。
- **内联 PDF 预览**：基于 kitty graphics + `pdftoppm`，翻页时预热相邻
  页面以减少黑屏间隔。
- **dashboard**：`snacks.nvim` 启动页，自定义 braille 头图与最近文件。

## 致谢

构建于 lazy.nvim 生态及众多优秀社区插件之上 —— folke、stevearc、
ibhagwan、akinsho、nvim-treesitter、neovim/nvim-lspconfig 等作者，感谢。
