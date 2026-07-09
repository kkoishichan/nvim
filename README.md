# Neovim 配置

一份现代化的个人 Neovim 配置，目标是在保留 Vim 编辑模型的前提下，把
Neovim 打磨成接近 IDE 的日常工作流。

- `lazy.nvim` 管理插件，首次启动自动 bootstrap。
- 默认 `catppuccin` 主题（可持久切换），`<Space>` 作为 leader，`\` 作为 localleader。
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
- `sqlite3` 与 [ECDICT-ultimate](https://github.com/skywind3000/ECDICT-ultimate)
  数据库 `~/.local/share/trans/ultimate.db`（离线词典）。下载 Release 里的
  [`ecdict-ultimate-sqlite.zip`](https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip)
  解压到该目录，或用 `./deploy.sh --dict` 自动安装（解压后约 1.2GB）

语言服务器会在相应文件首次打开时由 Mason 检查安装；formatter / linter 通过
`:MasonToolsInstall` 按需批量安装，DAP 适配器可用 `:DapInstall` 或 `:Mason` 安装。
Selene、Stylelint、golangci-lint 仅在项目存在对应配置时运行，避免套用不存在的规则集。

## 目录结构

```text
~/.config/nvim
├── init.lua              -- 入口：leader、加载 core 与 lazy
├── deploy.sh             -- 跨设备部署脚本
├── lazy-lock.json
├── selene.toml           -- 本配置的 Selene 规则
├── neovim.yml            -- Selene 的 Neovim 标准库声明
├── after/ftplugin        -- 少量内置 ftplugin 兼容补丁
├── spell                 -- 拼写检查词表
└── lua/user
    ├── lazy.lua          -- lazy.nvim bootstrap 与 setup
    ├── core
    │   ├── options.lua       -- vim 选项
    │   ├── keymaps.lua       -- 全局非插件键位
    │   ├── commands.lua      -- 自定义命令
    │   ├── autocmds.lua      -- 自动命令（外部改动 / 密钥保护 / PDF 预览）
    │   ├── diagnostics.lua   -- 诊断 UI
    │   ├── statuscolumn.lua  -- IDE 风格 gutter 排布
    │   ├── theme.lua         -- 主题切换与持久化
    │   ├── palette.lua       -- 从当前主题推导语义色
    │   ├── highlights.lua    -- 换主题后重放高亮覆盖的 helper
    │   ├── ui_highlights.lua -- 跟随主题的 UI 高亮（浮窗 / 通知等）
    │   ├── backdrop.lua      -- 浮窗后的调暗背景
    │   ├── dict.lua          -- ECDICT 离线词典浮窗
    │   ├── ai.lua            -- AI CLI（codex / claude / opencode）面板管理
    │   ├── layout.lua        -- 窗口布局工具
    │   ├── panels.lua        -- 侧边面板尺寸常量
    │   └── pdf.lua           -- PDF 预览状态
    └── plugins               -- 每个文件一组插件 spec
        ├── ui.lua            -- dashboard / lualine / bufferline / notify / which-key
        ├── edgy.lua          -- 辅助窗口固定停靠布局
        ├── navigation.lua    -- oil / neo-tree / outline / flash
        ├── picker.lua        -- fzf-lua
        ├── terminal.lua      -- toggleterm 多终端管理
        ├── neogen.lua        -- 文档注释生成
        ├── lsp.lua  completion.lua  formatting.lua  lint.lua
        ├── dap.lua  test.lua  tasks.lua
        ├── treesitter.lua  folding.lua  editor.lua  multicursor.lua
        ├── git.lua  media.lua  lang.lua  tools.lua  performance.lua
        └── claudecode.lua  codex.lua  opencode.lua   -- AI CLI 集成
```

## 部署

新机器上一条命令完成（安装依赖 + 克隆配置 + 无头安装插件）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkoishichan/nvim/main/deploy.sh)
```

或已克隆仓库时直接 `./deploy.sh`。支持 Arch / Debian·Ubuntu / Fedora /
openSUSE / macOS(Homebrew)；发行版仓库里的 Neovim 过旧时会自动从官方
Release 安装到 `~/.local`。已有的 `~/.config/nvim` 会先备份为
`nvim.bak.<时间戳>`；如果它本身就是本仓库则改为 `git pull`。

常用选项：`--ssh`（SSH 克隆）、`--with-extras`（lazygit / node / poppler
等可选依赖）、`--mason`（批量预装 formatter / linter）、`--dict`（下载
ECDICT-ultimate 离线词典）、`--no-deps`、`--no-sync`。详见
`./deploy.sh --help`。

## 首次启动

把配置放到 `~/.config/nvim`（或使用上面的 `deploy.sh`），然后：

```bash
nvim
```

首次启动会自动安装 `lazy.nvim` 与全部插件。之后可在 Neovim 内：

```vim
:Lazy                 " 插件管理
:Mason                " 语言服务 / 工具安装
:MasonToolsInstall    " 批量安装预设工具
:DapInstall           " 安装单个 DAP 适配器
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
- `gsa` / `gsd` / `gsr` ：添加 / 删除 / 替换 surround
- `<M-1>` … `<M-9>` ：跳到第 N 个 buffer，`<M-0>` 跳到最后一个
- `<C-/>` ：切换底部终端
- `<leader>k` ：离线词典；`<leader>ut` ：选择并持久保存主题
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
| `<leader>tl` | 选择已管理的底部终端 |
| `<leader>tk` | 关闭当前终端 |
| `<leader>tr` | 重命名终端 |
| `<leader>tf` | 浮动终端 |
| `<leader>te` / `<leader>tE` | 在文件目录 / cwd 打开外部终端 |

终端模式内：`<Esc><Esc>` 回到普通模式，`<C-hjkl>` / `<C-方向键>` 切换窗口，
普通模式 `q` 关闭。
