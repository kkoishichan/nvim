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
- `snacks.nvim` 提供 dashboard、scratch、input 与 zen；通知由 `nvim-notify` 提供。

当前在 Neovim `0.12.x` 上验证，并使用了 0.12 的公开 API，因此要求 `0.12+`。

## 依赖

必需：

- Neovim `>= 0.12`
- `git`、C 编译器（Tree-sitter 编译 parser 用）
- `ripgrep`、`fd`（fzf-lua 查找 / grep）
- 一款 Nerd Font 字体（图标显示）

推荐：

- `kitty` 终端（内联图片 / PDF 预览基于 kitty graphics）
- `ImageMagick`（图片处理）与 `poppler`（`pdftoppm`，PDF 预览渲染）
- `lazygit`、`node`、`typst`、`latexmk`、`tinymist`
- `sqlite3` 与 [ECDICT-ultimate](https://github.com/skywind3000/ECDICT-ultimate)
  数据库 `~/.local/share/trans/ultimate.db`（离线词典）。下载 Release 里的
  [`ecdict-ultimate-sqlite.zip`](https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip)
  解压到该目录，或用 `./deploy.sh --dict` 自动安装（解压后约 1.2GB）
- Java 开发需要 JDK 21+ 与 Python 3.9+ 来运行 Mason 的 JDTLS launcher；项目
  本身仍可使用 JDK 8+，部署时可用 `./deploy.sh --java` 安装 Java 环境。
- C# 开发需要 PATH 中有兼容项目的 [.NET SDK](https://dotnet.microsoft.com/download)。
- Kotlin 的格式化、检查与调试需要 PATH 中有 Java；可用 `./deploy.sh --java --mason`
  同时安装 JDK 和固定版本的 Kotlin 工具。

普通文件不会加载 Mason、刷新 registry 或下载工具。`:MasonToolsInstall` 会按需恢复
`lua/user/toolchain.lua` 中带版本的语言服务器、formatter、linter 与 DAP 适配器；
也可用 `:MasonInstall` / `:DapInstall` 单独安装（安装后重启 Neovim 以启用新工具）。
`:MasonCSharpInstall`、`:MasonJavaInstall` 与 `:MasonKotlinInstall` 可只恢复对应语言工具。
Java 是例外：打开 Java 文件时若
缺少 JDTLS，只会安装固定版本的 JDTLS。Tree-sitter parser 的 revision 随
`lazy-lock.json` 锁定的 `nvim-treesitter` 定义一同固定。
Selene、Stylelint、golangci-lint 仅在项目存在对应配置时运行，避免套用不存在的规则集。

## 目录结构

```text
~/.config/nvim
├── .github/
│   └── workflows/
│       └── ci.yml             -- GitHub Actions 回归检查
├── .gitignore                 -- 本地状态、日志与临时文件忽略规则
├── after/
│   └── ftplugin/
│       └── markdown.lua       -- 内置 Markdown ftplugin 兼容补丁
├── lua/
│   └── user/
│       ├── lazy.lua           -- lazy.nvim bootstrap 与 setup
│       ├── toolchain.lua      -- 带版本的 Mason 工具清单
│       ├── core/
│       │   ├── ai.lua         -- AI provider 路由与上下文操作
│       │   ├── ai_terminal.lua -- AI CLI 的 toggleterm 生命周期与通信
│       │   ├── autocmds.lua   -- 通用自动命令与生命周期
│       │   ├── backdrop.lua   -- 浮窗背景调暗
│       │   ├── commands.lua   -- 自定义命令
│       │   ├── conflicts.lua  -- Git conflict 高亮、跳转与选择
│       │   ├── diagnostics.lua -- 诊断 UI
│       │   ├── dict.lua       -- ECDICT 离线词典浮窗
│       │   ├── highlights.lua -- 主题切换后的高亮重放 helper
│       │   ├── java.lua       -- Java root / runtime / workspace 解析
│       │   ├── keymaps.lua    -- 全局非插件键位
│       │   ├── layout.lua     -- 窗口布局工具
│       │   ├── lsp_progress.lua -- LSP 进度通知
│       │   ├── options.lua    -- vim 选项
│       │   ├── palette.lua    -- 从当前主题推导语义色
│       │   ├── panels.lua     -- 侧边面板尺寸常量
│       │   ├── pdf.lua        -- PDF 状态栏数据
│       │   ├── pdf_preview.lua -- PDF 渲染、缓存、按键与文件监听
│       │   ├── sensitive.lua  -- 密钥文件与剪贴板保护
│       │   ├── statuscolumn.lua -- IDE 风格 gutter 排布
│       │   ├── testing.lua    -- 按项目/语言加载 neotest adapter
│       │   ├── theme.lua      -- 主题切换与持久化
│       │   └── ui_highlights.lua -- 跟随主题的 UI 高亮
│       └── plugins/           -- 每个文件一组 lazy.nvim spec
│           ├── claudecode.lua
│           ├── completion.lua
│           ├── dap.lua
│           ├── edgy.lua
│           ├── editor.lua
│           ├── folding.lua
│           ├── formatting.lua
│           ├── git.lua
│           ├── java.lua
│           ├── lang.lua
│           ├── lint.lua
│           ├── lsp.lua
│           ├── media.lua
│           ├── multicursor.lua
│           ├── navigation.lua
│           ├── neogen.lua
│           ├── opencode.lua
│           ├── performance.lua
│           ├── picker.lua
│           ├── tasks.lua
│           ├── terminal.lua
│           ├── test.lua
│           ├── tools.lua
│           ├── treesitter.lua
│           └── ui.lua
├── scripts/
│   ├── check.lua              -- Neovim 集成回归
│   └── check.sh               -- 静态检查与无头启动入口
├── spell/
│   ├── en.utf-8.add           -- 自定义英文词表
│   └── en.utf-8.add.spl       -- Neovim 编译后的词表
├── deploy.sh                  -- 跨设备部署脚本
├── init.lua                   -- 入口：版本检查、core、lazy
├── lazy-lock.json             -- 插件版本锁
├── LICENSE                    -- MIT 许可证
├── neovim.yml                 -- Selene 的 Neovim 标准库声明
├── README.md                  -- 配置说明、依赖与快捷键
└── selene.toml                -- Selene 规则
```

`after/` 与 `spell/` 是 Neovim 会按约定自动发现的 `runtimepath` 目录，移动到
`lua/` 后不会再自动生效；`neovim.yml` 只为 Selene 提供 Neovim API 类型声明，
不会被 Neovim 运行时加载。

## 部署

新机器上一条命令完成（安装依赖 + 克隆配置 + 无头安装插件）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kkoishichan/nvim/main/deploy.sh)
```

或已克隆仓库时直接 `./deploy.sh`。支持 Arch / Debian·Ubuntu / Fedora /
openSUSE / macOS(Homebrew)；发行版仓库里的 Neovim 过旧时会自动从官方
Release 安装到 `~/.local`。已有的 `~/.config/nvim` 会先备份为
`nvim.bak.<时间戳>`；如果它本身就是本仓库则改为 `git pull`。

常用选项：`--ssh`（SSH 克隆）、`--with-extras`（lazygit / node / ImageMagick /
poppler / typst / latexmk 等可选依赖）、`--java`（JDK / JDTLS / Java 调试与测试，也满足
Kotlin 工具的 JVM 依赖）、`--mason`（安装所需的
Node.js / Python / Go / Cargo 运行时并批量预装固定版本的开发工具链）、
`--dict`（下载 ECDICT-ultimate 离线词典）、
`--no-deps`、`--no-sync`。详见 `./deploy.sh --help`。

## 首次启动

把配置放到 `~/.config/nvim`（或使用上面的 `deploy.sh`），然后：

```bash
nvim
```

首次启动会自动安装 `lazy.nvim` 与全部插件。之后可在 Neovim 内：

```vim
:Lazy                 " 插件管理
:Mason                " 语言服务 / 工具安装
:MasonToolsInstall    " 恢复固定版本的预设工具链
:MasonCSharpInstall   " 只安装 C# LSP / formatter / debugger
:MasonKotlinInstall   " 只安装 Kotlin LSP / formatter / debugger
:DapInstall           " 安装单个 DAP 适配器
:checkhealth          " 健康检查
```

## Java

打开 Java 文件时会验证 PATH 中确实有 Java 21+ 运行时，并按需安装、启动 JDTLS。首次打开
Java 项目前，建议安装
调试和测试扩展：

```vim
:MasonJavaInstall
:TSInstall java
```

支持 Maven、Gradle、Ant、独立 Java 文件、Lombok、格式化、源码下载、主类调试，
以及 JUnit / TestNG 测试。每个项目使用独立的持久化 JDTLS workspace。

Java buffer 中的附加键位：

| 键 | 作用 |
| --- | --- |
| `<leader>rr` | 运行光标附近的测试方法 |
| `<leader>rf` | 运行当前测试类 |
| `<leader>rd` | 调试光标附近的测试方法 |
| `<leader>rs` | 选择并运行 Java 测试 |
| `<leader>ro` / `<leader>rO` | 打开调试 REPL / 切换调试 UI |
| `<leader>rx` | 停止 Java 调试会话 |
| `<localleader>o` | 整理 imports |
| `<localleader>v` / `<localleader>c` | 提取变量 / 常量 |
| Visual `<localleader>m` | 提取方法 |
| `<localleader>tp` | 选择并运行当前文件中的测试 |

## C#

安装 [.NET SDK](https://dotnet.microsoft.com/download) 后，在 Neovim 内执行：

```vim
:MasonCSharpInstall
:TSInstall c_sharp
```

`.sln`、`.slnx` 与 `.csproj` 项目使用 Roslyn 提供补全、诊断、跳转和重构；CSharpier
负责保存时格式化。`neotest-vstest` 通过 VSTest / Microsoft Testing Platform 支持
各类 .NET 测试框架，沿用 `<leader>rr` / `<leader>rf` / `<leader>rd` 等通用测试键位。
`<F5>` 调试使用 netcoredbg；
先执行 `dotnet build`，再从提示中选择 `bin/Debug/...` 下的 DLL，或选择 attach 配置。

## Kotlin

安装 Java 后，在 Neovim 内执行：

```vim
:MasonKotlinInstall
:TSInstall kotlin
```

配置使用 JetBrains 官方 Kotlin LSP，支持 Gradle、Maven 和实验性 Android Gradle Plugin
项目；ktlint 负责格式化与检查。该 LSP 当前仍处于 Alpha 阶段。`<F5>` 使用 Kotlin Debug
Adapter；启动前先用 Gradle/Maven 编译，再确认提示的完整主类名（顶层 `main` 默认推导为
`包名.文件名Kt`），也可 attach 到 `localhost:5005`。

Kotlin 的 Neotest 适配器目前只支持带 `gradlew` 的 Gradle 项目和部分 Kotest spec，尚不支持
JUnit、`kotlin.test`、Maven 或测试调试；这些测试请通过 `<leader>j` 的 Overseer 任务或终端
运行，应用程序调试使用 `<F5>`。配置会阻止 Kotlin buffer 中的 `<leader>rd`，避免把有限的适配器
能力误认为完整测试支持。

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

## 行为与维护

- 敏感文件采用精确的文件名、扩展名和目录规则；禁用该 buffer 的持久 undo / swap，
  但保留当前会话的撤销；ShaDa 不持久化寄存器。复制内容若 60 秒内未变化会从
  寄存器和系统剪贴板清除，可将 `vim.g.user_sensitive_clipboard_timeout_ms = 0` 关闭。
- 外部文件变化默认在聚焦、切换 buffer 或离开终端时检查。需要空闲轮询时设置
  `vim.g.user_external_change_poll_ms`（毫秒）；默认不开启全 buffer 定时扫描。
- Mason 不修改全局 `PATH`；LSP、formatter、linter 与 debugger 会逐项解析系统工具，
  找不到时才使用 Mason 的绝对路径，因此普通终端不会继承 Mason 环境。
- 写入不存在的父目录不会再静默创建目录；确认路径后使用 `:WriteCreateDirs`。
- PDF PNG 缓存目录权限设为仅当前用户可访问，保留不超过 30 天且总量限制为 512 MiB。
- 修改配置后运行 `./scripts/check.sh`，检查 Shell、Lua、YAML、lockfile 和无头启动。
