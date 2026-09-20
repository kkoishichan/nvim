# Neovim 配置

一份现代化的个人 Neovim 配置，目标是在保留 Vim 编辑模型的前提下，把
Neovim 打磨成接近 IDE 的日常工作流。

- `lazy.nvim` 管理插件，首次启动自动 bootstrap。
- 默认 `vscode` Dark+ 主题（可持久切换），`<Space>` 作为 leader，`\` 作为 localleader。
- `fzf-lua` 负责查找、搜索、符号 / 调用关系与 Git 列表，并接管 `vim.ui.select`。
- `glance.nvim` 提供定义、声明、实现、类型与引用的双栏 Peek 界面。
- `oil.nvim` 像编辑 buffer 一样管理文件系统；`neo-tree.nvim` 提供侧边文件树。
- `blink.cmp` 负责补全、snippet 与签名帮助；`Tab` / `Enter` 确认候选，方向键选择，
	`Alt-Space` 主动唤起（`Ctrl-Space` 留给输入法）；当前重载默认以带函数标记的虚拟文本显示，并在空间允许时借用可见的相邻行，
	长签名按窗口宽度省略，优先显示正在填写的参数；缩放、滚动和补全菜单出现时重新布局。
	`Ctrl-K` 切换完整签名浮窗，`Ctrl-B` / `Ctrl-F` 滚动超出屏幕的签名。
- `nvim-lspconfig` + Mason 负责语言服务与外部工具安装。
- `conform.nvim` 格式化，`nvim-lint` 静态检查。
- `nvim-ufo` + Tree-sitter 折叠。
- `toggleterm.nvim` 提供 VSCode 风格的多终端管理。
- `overseer.nvim` 任务运行，`neotest` 测试，`nvim-dap` + `dap-ui` 调试。
- `snacks.nvim` 提供 dashboard、scratch、input 与 zen；通知由 `nvim-notify` 提供。
- LSP 任务持续至少 500 ms 才显示进度，短检查静默完成；长任务按 250 ms 刷新，完成后提示保留 1.2 秒。
- 除通知外，小型临时弹窗统一使用 Pmenu 背景的无边框 padding 设计；`Esc` 一次收起当前
  标签页内重叠的补全、签名、文档、提示与预览。通知按超时自动消失（`<leader>un` 可立即
  清空），Glance、Fzf、Lazy、Mason、Oil 等界面走各自关闭接口；终端、scratch、zen 等
  编辑工作区不会被误关。
- `:Lazy` 与 `:Mason` 共用同一个 80% 纯无边框矩形，并校正两插件不同的高度计算方式。

当前在 Neovim `0.12.x` 上验证，并使用了 0.12 的公开 API，因此要求 `0.12+`。

## 依赖

必需：

- Neovim `>= 0.12`
- `git`、C 编译器（Tree-sitter 编译 parser 用）
- `fzf >= 0.36.0`、`ripgrep`、`fd`（fzf-lua 查找 / grep；部署时检查 fzf 版本）
- 一款 Nerd Font 字体（图标显示）

推荐：

- `kitty` 终端（内联图片 / PDF 预览基于 kitty graphics）
- `ImageMagick`（图片处理）与 `poppler`（`pdftoppm`，PDF 预览渲染）
- `lazygit`、`node`、`typst`、`latexmk`、`tinymist`
- `sqlite3` 与 [ECDICT-ultimate](https://github.com/skywind3000/ECDICT-ultimate)
  数据库 `~/.local/share/trans/ultimate.db`（离线词典）。下载 Release 里的
  [`ecdict-ultimate-sqlite.zip`](https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip)
  解压到该目录，或用 `./scripts/deploy.sh --dict` 自动安装（解压后约 1.2GB）
- 按项目准备对应的编译器、SDK、构建系统或运行时；完整对应关系见“语言支持”矩阵。

普通文件不会加载 Mason、刷新 registry 或下载工具。`:MasonToolsInstall` 会显式恢复
`lua/user/toolchain.lua` 中带版本的语言服务器、formatter、linter 与 DAP 适配器；
也可用 `:MasonInstall` / `:DapInstall` 单独安装。安装完成会刷新工具发现，也可运行
`:ToolsRefresh`；新工具用于后续附加，已运行的语言服务保留当前进程，必要时用 `:LspRestart`。
部署脚本的 `--mason` 还会准备这些工具共用的 Node.js / npm、Python 3.9+ / pip、Go、
Cargo、Perl 与 JDK 21+；项目自身锁定的版本和构建系统仍由项目管理。
Tree-sitter parser 的 revision 随 `lazy-lock.json` 锁定的 `nvim-treesitter` 定义一同固定。
Selene、Stylelint、golangci-lint 仅在项目存在对应配置时运行，避免套用不存在的规则集。

## 目录结构

```text
~/.config/nvim
├── .gitignore                 -- 本地状态、日志与临时文件忽略规则
├── .github/workflows/check.yml -- 固定依赖版本的 CI
├── docs/                      -- 路线、实施记录与分层验收证据
├── after/
│   └── ftplugin/
│       └── markdown.lua       -- 内置 Markdown ftplugin 兼容补丁
├── lua/
│   └── user/
│       ├── health.lua         -- 项目、工具来源与缺项健康报告
│       ├── lazy.lua           -- lazy.nvim bootstrap 与 setup
│       ├── toolchain.lua      -- 带版本的 Mason 工具清单
│       ├── core/
│       │   ├── ai.lua         -- AI provider 路由与上下文操作
│       │   ├── ai_terminal.lua -- AI CLI 的 toggleterm 生命周期与通信
│       │   ├── autocmds.lua   -- 通用自动命令与生命周期
│       │   ├── backdrop.lua   -- 浮窗背景调暗
│       │   ├── buffer_policy.lua -- 有界成本判定与各功能准入
│       │   ├── buffers.lua    -- 保留分屏的文件关闭与保存选择
│       │   ├── blink_signature.lua -- 签名提示稳定入口
│       │   ├── signature/     -- 调用解析、参数选择、渲染与 Blink 适配
│       │   ├── commands.lua   -- 自定义命令
│       │   ├── conflicts.lua  -- Git conflict 高亮、跳转与选择
│       │   ├── diagnostics.lua -- 诊断 UI
│       │   ├── dict.lua       -- ECDICT 离线词典浮窗
│       │   ├── float_style.lua -- 无边框 padding 浮窗共享样式
│       │   ├── format_policy.lua -- 保存预算、异步格式化与汇编边界
│       │   ├── highlights.lua -- 具名高亮回调，重载时替换
│       │   ├── java.lua       -- Java root / runtime / workspace 解析
│       │   ├── keymaps.lua    -- 全局非插件键位
│       │   ├── layout.lua     -- 窗口布局工具
│       │   ├── lazy_bootstrap.lua -- 从同源锁文件启动 Lazy
│       │   ├── lsp_progress.lua -- LSP 进度通知
│       │   ├── options.lua    -- vim 选项
│       │   ├── palette.lua    -- 从当前主题推导语义色
│       │   ├── panels.lua     -- 面板空间分配与正文保护
│       │   ├── pdf.lua        -- PDF 状态栏数据
│       │   ├── pdf_registration.lua -- PDF 轻量注册，首次使用再加载实现
│       │   ├── pdf_preview.lua -- PDF 渲染、缓存、按键与文件监听
│       │   ├── popups.lua     -- Esc 统一关闭临时弹窗
│       │   ├── preferences.lua -- 类型检查后的机器偏好
│       │   ├── project.lua    -- 工作区、语言项目与仓库上下文
│       │   ├── sensitive.lua  -- 密钥文件与剪贴板保护
│       │   ├── session.lua    -- 多标签工作区会话与项目元数据
│       │   ├── window_roles.lua -- 正文、面板与临时窗口角色
│       │   ├── workflows.lua  -- 项目 build/run/test 与失败位置
│       │   ├── statuscolumn.lua -- IDE 风格 gutter 排布
│       │   ├── testing.lua    -- 按项目/语言加载 neotest adapter
│       │   ├── theme.lua      -- 主题切换与持久化
│       │   ├── treesitter.lua -- parser 与 FileType 的统一清单
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
│   ├── check.sh               -- 静态检查与分组回归入口
│   ├── check-workflows.sh     -- 显式执行真实语言工作流
│   ├── run-check.lua          -- 独立进程中的行为回归加载器
│   ├── checks/                -- 按主题分组的行为与集成回归
│   ├── prepare-checks.sh      -- 显式准备隔离的锁定依赖
│   ├── verify-lock.lua        -- 依赖版本、修改状态与可加载性校验
│   ├── benchmark.py           -- 可重复的启动测量
│   ├── ui-smoke.py            -- 真实 PTY 按键与补全检查
│   └── deploy.sh              -- 跨设备部署脚本
├── spell/
│   ├── en.utf-8.add           -- 自定义英文词表
│   └── en.utf-8.add.spl       -- Neovim 编译后的词表
├── init.lua                   -- 入口：版本检查、core、lazy
├── lazy-lock.json             -- 插件版本锁
├── LICENSE                    -- GNU GPL v3 许可证
├── neovim.yml                 -- Selene 的 Neovim 标准库声明
├── README.md                  -- 配置说明、依赖与快捷键
└── selene.toml                -- Selene 规则
```

`after/` 与 `spell/` 是 Neovim 会按约定自动发现的 `runtimepath` 目录，移动到
`lua/` 后不会再自动生效；`neovim.yml` 只为 Selene 提供 Neovim API 类型声明，
不会被 Neovim 运行时加载。

## 部署

新机器先预览安装计划，再按需要选择语言工具：

```bash
./scripts/deploy.sh --dry-run --ref main --profile minimal
./scripts/deploy.sh --ref main --nvim-version v0.12.5 --profile python --profile web
```

脚本包含 Arch / Debian·Ubuntu / Fedora / openSUSE / macOS(Homebrew) 的依赖分支，
默认固定 Neovim 0.12.5，必要时从官方 Release 安装到 `~/.local`。
`--ref` 接受分支、tag 或提交；要重复同一配置，请指定完整提交号。
先在同目录的暂存区完成克隆和插件校验，再备份旧配置并切换符号链接。
原目录中的未提交修改也保留在备份中；不会通过自动 `git pull` 合并它们。

`--profile` 可重复选择 `minimal`、`python`、`web`、`java`、`native`、`docs`，
`full` 包含完整 Mason 清单，`--mason` 为其兼容别名。默认仅安装 minimal。
其他选项包括 `--ssh`、`--with-extras`、`--dict`、`--no-deps`、`--no-sync` 和
`--config-dir`。部分工具失败会返回非零状态并说明当前配置与备份的位置。
完整流程、限制及恢复步骤见 [部署说明](docs/deployment.md)。

## 首次启动

把配置放到 `~/.config/nvim`（或使用上面的 `./scripts/deploy.sh`），然后：

```bash
nvim
```

首次启动会自动安装 `lazy.nvim` 与全部插件。之后可在 Neovim 内：

```vim
:Lazy                 " 插件管理
:Mason                " 语言服务 / 工具安装
:MasonToolsInstall    " 恢复固定版本的预设工具链
:MasonInstall <tool>  " 安装单个工具
:DapInstall           " 安装单个 DAP 适配器
:checkhealth          " 健康检查
```

## 性能策略

面向日常轻量编辑和服务器环境的[快速模式设计](docs/fast-mode.md)已确定功能取舍、缓存策略与精简部署范围；目前为待实现方案，文中的新入口尚不可用。

共享 buffer 策略会在读取和编辑时识别超过 1.5 MiB、10,000 行、单行超过 2,000 字节，
或平均行长过高的文件，按 buffer 关闭 Tree-sitter、LSP、颜色扫描和 indent guide 等高成本功能。
保留文件类型和撤销；语言服务仅脱离该文件，不关闭其他文件共享的服务。
`:BufferFeatures` 查看原因，`:BufferFeatures on|off|auto` 手动启用、停用或恢复自动判断。
`faster.nvim` 继续负责宏执行优化。普通文件保留完整语言功能；lint 调度会按 buffer 去重、防抖并缓存
工具和配置查找结果。聚焦 Neovim 时先检查可见文件，隐藏 buffer 按批次检查，避免长会话
一次性 `stat` 所有文件。可按机器调整：

```lua
vim.g.user_checktime_batch_size = 16 -- 每批检查的隐藏 buffer 数
```

Git 行 blame 默认启用，可用 `<leader>ghB` 切换；scrollview 搜索结果标记保持启用，
不设置单独开关。Neo-tree 保持目录 watcher、Git 状态和诊断功能。

滚轮和触控板使用原生滚动；颜色预览按 50 ms 时间窗合并视口刷新，让正文先响应输入，
并清理重复的字面量高亮。CSS 变量按文件文本版本复用解析结果，颜色请求先检查语言服务能力。
滚动条按 40 ms 时间窗合并事件，保留折叠和拖动；全局状态栏每批只计算活动窗口一次。
分屏分别绘制可见区域，键盘分页动画保持原有行为。验证方法、测量结果及适用范围见
[滚动性能验证](docs/scrolling.md)和[后续性能优化](docs/performance-followup.md)。
Python 高亮使用原生查询，保留原有颜色和范围；已撤除收益有限、增加首次打开开销的谓词缓存。
启动与滚动取舍见[启动优化复核](docs/startup-tradeoffs.md)。其他九种语言的历史试验见
[多语言滚动对照](docs/multilanguage-scrolling.md)。
修复 warning 后的真实 LSP、诊断绘制和配对提示成本见[Python 诊断与滚动复测](docs/python-lsp-scrolling.md)。
配对提示复用未变化的查询结果和跳过区域，保留原有提示及跳转；效果与适用范围见
[vim-matchup 缓存验证](docs/matchup-scrolling.md)。
自动配对搜索遇到待处理输入时让行，空闲后完整重算；进一步的慢事件对照见
[配对提示与滚轮慢事件](docs/matchup-tail-latency.md)。

右侧滚动条采用单轨概览设计：滑块、诊断、搜索、mark、TODO、冲突和 Git 改动始终
共用一列，同一高度只显示优先级最高的标记。诊断沿用左列的 `E/W/I/H`，FIX、TODO、
HACK、WARN/XXX 也沿用对应图标；Git 使用粗实线 `┃`，搜索 `━`、冲突 `×`，mark 保留字母。
左右两侧的 Git 新增/修改标记均使用居中的 `┃`；所有标记固定占用一个字符，并使用与
左列一致的主题语义色。
右侧发生位置碰撞时，诊断、冲突、搜索、mark 和关键词均优先于 Git；精确 Git 状态仍由
左侧专用车道持续显示。

## 语言支持

这里的“支持”按层次区分：Tree-sitter 负责语法与文本对象，LSP 提供补全、诊断和重构，
formatter / linter、Neotest、DAP 与预览工具则按语言独立配置。表中 `—` 表示没有专用集成，
不代表文件无法编辑。

<!-- markdownlint-disable MD013 -->

| 语言 / 文件类型 | LSP / 语义支持 | 格式化 / 检查 | 测试 / 调试 / 预览 | 项目环境 / 限制 |
| --- | --- | --- | --- | --- |
| Assembly / RISC-V | asm-lsp | asmfmt 仅用于识别到的 Go Plan 9 汇编 | — | 对应汇编工具链 |
| C / C++ | clangd | clang-format、clang-tidy | codelldb 调试 | C / C++ 工具链；调试前先构建可执行文件 |
| CMake、Make、Autotools | neocmake、autotools-language-server | cmake-format、cmakelint、checkmake | — | 对应构建工具 |
| Go | gopls | goimports、gofumpt、staticcheck；按项目启用 golangci-lint | neotest-golang；Delve 调试 | Go toolchain |
| Java | JDTLS / nvim-jdtls | JDTLS formatter | JUnit / TestNG；Java Debug Adapter | JDTLS 需 JDK 21+，Mason launcher 另需 Python 3.9+；项目可使用旧 JDK |
| Rust | rust-analyzer / rustaceanvim | rustfmt、Clippy | rustaceanvim Neotest；codelldb 调试 | Rust / Cargo toolchain |
| Python | BasedPyright、Ruff | Ruff | neotest-python；debugpy 调试 | Python |
| JavaScript、TypeScript、React | vtsls；按项目启用 Biome / Tailwind CSS | Biome 或 Prettier | Jest / Vitest；js-debug 调试 | Node.js |
| Vue | vue_ls、vtsls、Tailwind CSS | Prettier；按项目启用 Biome | Jest / Vitest；Node / 浏览器调试 | Node.js |
| HTML / CSS | html-lsp、css-lsp、Emmet、Tailwind CSS | Prettier；按项目启用 Biome / Stylelint | HTML live preview | Node.js 用于相关工具 |
| Lua | lua-language-server | StyLua；按项目启用 Selene | — | — |
| Bash / POSIX sh | bash-language-server | shfmt、ShellCheck | — | 对应 shell |
| SQL / PostgreSQL | sql-language-server（补全，关闭其通用 SQL 诊断） | sqruff（postgres 方言，含语法错误检查） | — | 表名、列名补全需配置数据库连接；支持 psql 元命令 |
| Dockerfile | dockerfile-language-server | hadolint | — | 运行容器时需要 Docker / Podman |
| Verilog / SystemVerilog | Verible LSP | Verible formatter / rules | — | HDL 工具链按项目安装 |
| JSON / YAML / TOML | json-lsp、yaml-language-server、Taplo | Biome / Prettier、yamllint、Taplo | — | — |
| Markdown | Marksman | Prettier、markdownlint-cli2 | Markview、浏览器预览 | Node.js 用于相关工具 |
| LaTeX | TexLab | latexindent | VimTeX、latexmk 编译与预览 | TeX distribution、latexmk |
| Typst | Tinymist | typstyle | typst-preview、PDF 编译 | Typst |

<!-- markdownlint-enable MD013 -->

此外，Tree-sitter 还覆盖 NASM、diff、Git 配置与提交信息、Go module 文件、Hyprlang、Zsh、
Vim / Vimdoc、Doxygen、查询文件等；这些项目属于语法级支持，不应等同于完整 LSP、测试或调试。
typos-lsp 会为代码和结构化数据提供低优先级拼写提示，普通文本则使用 Neovim spell。

### 安装与通用工作流

`:MasonToolsInstall` 只恢复 Mason 管理的固定版本工具；部署脚本的 `--mason` 还会准备这些
工具安装和运行时共用的前置环境，但不会代替项目自己的 SDK、编译器或构建系统。Tree-sitter
parser 会在插件安装或更新时统一同步，也可用 `:TSInstall <language>` 单独修复。

支持 Neotest 的语言共用 `<leader>rr`（最近测试）、`<leader>rf`（当前文件）、
`<leader>rd`（调试测试）、`<leader>rw`（watch）以及输出、停止和 summary 键位；应用调试共用
`<F5>`、`<F10>`、`<F11>` 与 `<leader>d` 组。

Biome、Stylelint、golangci-lint 与 Selene 只在项目存在对应配置时启用，避免凭空套用规则集。
受限或未集成的测试可通过 `<leader>j` 的 Overseer 任务或终端运行。

## 键位

### 项目和环境

默认工作区取当前文件的仓库根，独立项目或单文件再回退到项目根或文件目录。
`:ProjectPick`、`:DirectoryPick`、`:Cd <目录>` 和 `:FileDir` 会显式选择当前标签页的工作区；
`:ProjectRoot` 重新按当前文件定位项目根。搜索、新终端和任务使用所选工作区，
语言服务和项目工具仍根据文件所在的语言项目查找配置，支持 monorepo 的包级规则。

`:ProjectContext` 显示工作区、语言项目、仓库和实际 cwd；`:checkhealth user` 解释工具来源、
版本、缺失依赖及当前语言服务路径。`:ToolsRefresh` 刷新安装、PATH 和环境变更后的发现结果。
项目内 Node 工具优先于系统/Mason；Python 目标解释器优先使用项目 `.venv` / `venv`，
其次 `VIRTUAL_ENV`、PATH。debugpy 自身的宿主环境与目标解释器分开。
JDTLS 先检查 JAVA_HOME，再检查 PATH，选取可用的 JDK 21+ 并明确传给启动器；项目 JDK 独立。

Jest/Vitest 根据文件所属项目识别；两者同处一个范围且无法区分时，
使用 `:TestAdapter jest` 或 `:TestAdapter vitest` 选择，`:TestAdapter auto` 恢复自动识别。
重跑任务只选当前工作区最近完成的任务，模板已有的包级运行目录会保留。

普通终端、Codex 和 OpenCode 按工作区保留进程，切换项目会选择该项目的会话。
OpenCode 使用仅绑定本机的独立端口，并核对服务目录后再传递上下文。
Claude 原生 IDE 集成在一个 Neovim 中只有一个终端：首次打开时绑定工作区，
切到其他项目后会阻止误发；回到原项目继续使用，或另开 Neovim 为另一项目建立会话。

机器偏好放在未跟踪的 `~/.config/nvim/preferences.json`，例如：

```json
{
  "tools": { "prefer_mason": false },
  "format": { "timeout_ms": 800 },
  "runtime": { "mode": "auto", "state_dir": "", "persistent_undo": false }
}
```

修改后运行 `:ToolsRefresh`；无效值采用默认设置，并在健康报告中说明。
项目自身的格式化和检查规则继续放在项目原生配置文件中。

## 运行模式

`full` 是默认模式，保留本文描述的全部功能。`fast` 保留熟悉的编辑方式、主题和
Tree-sitter 语法高亮，默认不启动语言服务、补全、Git 标记、装饰、折叠提供者和
附加界面，适合 SSH、容器和资源有限的服务器。

```sh
NVIM_MODE=fast nvim path/to/file.py
NVIM_MODE=full nvim path/to/file.py
```

显式环境变量优先，其次是 `preferences.json` 的 `runtime.mode`（`full` / `fast` /
`auto`），未配置时仍用 `full`。`auto` 只看连接本身：`SSH_CONNECTION` 或 `SSH_TTY`
非空时选择 `fast`。模式在启动时确定，换模式需要重启；快速模式的原生状态栏显示
`FAST`，`:ModeInfo` 按需列出选择来源、关闭的能力、降级原因和存储路径。

`runtime.state_dir` 可把 swap、undo、view 和 ShaDa 指向本机磁盘，目录由当前用户拥有
且权限为 `0700`。目录不可用时仍可编辑，但磁盘恢复关闭并在 `:ModeInfo` 与
`:checkhealth user` 中说明。`runtime.persistent_undo` 在快速模式下重新打开持久撤销。

缺少 lazy.nvim 或所选插件时进入不依赖插件管理器的原生入口：原生目录浏览、保存、
文件类型缩进和退出仍然可用，缺失项留给 `:ModeInfo`。

快速模式需要语言服务时用 `:FastLspStart [server]`：只为当前缓冲区选择并启动一个
已安装的主要语言服务，复用现有工具路径和项目根规则；拼写服务和辅助检查器只在显式
点名时出现。之后使用原生 hover、跳转、重命名、手动补全（`omnifunc`）和签名浮窗，
诊断通过 `<leader>cd` 浮窗或 `<leader>cD` 位置列表查看，默认不画下划线和虚拟行。
`:FastLspStop` 只撤销本模式建立的附着，最后一个受管缓冲区退出后停止该客户端。
缺少可执行文件时只提示安装要求，不启动 Mason、不下载 SDK。

快速模式关闭自动 `unnamedplus` 同步，普通寄存器始终可用；`<leader>y` / `<leader>Y` / `<leader>p`
显式使用系统剪贴板，支持 OSC 52 的连接由 Neovim 自带的提供者带出。界面符号改用 ASCII，
真彩色由 Neovim 自己的终端检测决定，不强制开启。

缺少 fzf 时，搜索入口改用原生方式：`vim.ui.input` 的文件名补全打开文件，
`:vimgrep` 把匹配送进 quickfix，缓冲区和最近文件用原生选择列表；
没有原生替代的入口会说明可用的替代命令，而不是静默做别的事。

侧栏和输出面板会为正文保留默认 40 列、8 行；可在偏好中设置
`ui.min_editor_width` / `ui.min_editor_height`。小屏会收起辅助面板，终端进程继续运行；
修改中的面板和手工建立的正文分屏受到保护。

文件关闭入口保留各标签页的分屏，未保存文件提供保存、放弃、取消选择。
`Esc` 只收起临时提示，编辑浮窗使用自己的关闭操作。会话保存整个多标签工作区及各自项目目录，
继续兼容旧 Persistence 会话；恢复前检查未保存内容。行为边界及终端验收见
[窗口与会话验收](docs/ui-validation.md)。

`:TaskBuild`、`:TaskRun`、`:TaskTest`（`<leader>jb` / `jx` / `jT`）根据当前项目发现常用入口，
在 Overseer 中保留输出和结果，构建错误可从 quickfix 跳转。
支持 package scripts、Cargo、Go、Maven/Gradle、CMake/Make、pytest，以及当前 Python/Shell 文件与 TeX/Typst 构建。
CMake 初次执行先生成 `build/`，再次构建；自定义任务继续使用 `:OverseerRun` 或 `:OverseerShell`。

普通保存格式化默认限时 800 ms，`<leader>cf` 可手动异步格式化。
TeX 在保存后异步格式化，期间的新编辑会受到保护；完成后的格式化结果会再写入磁盘。
Go 汇编仅在 `.s`、Go 项目和 Plan 9 指令特征同时匹配时使用 asmfmt，
可用 `vim.b.user_go_asm = true/false` 明确指定；GNU/RISC-V 汇编不自动交给它。

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

- `<Esc>` ：关闭当前标签页内的临时弹窗；没有弹窗时清除搜索高亮
- `-` ：oil 编辑当前目录
- `s` / `S` ：flash 跳转 / treesitter 跳转
- `gd` / `gD` / `gi` / `gy` / `gr` ：Peek 定义 / 声明 / 实现 / 类型 / 引用
- `gsa` / `gsd` / `gsr` ：添加 / 删除 / 替换 surround
- `<M-1>` … `<M-9>` ：跳到第 N 个 buffer，`<M-0>` 跳到最后一个
- `<C-/>` ：切换底部终端（兼容传统终端的 `<C-_>` 编码）
- `<leader>k` ：离线词典；`<leader>ut` ：选择并持久保存主题
- `<leader>uT` / `:TransparentToggle` ：切换并持久保存透明背景，切换主题后仍生效。编辑区、行号栏及文件树透明，弹窗和选中行保留底色；透明程度由终端设置决定。状态保存在 `stdpath("state")/transparent.txt`，默认关闭。
- `<leader>ghB` ：切换当前行 Git blame
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

终端模式内：`<Esc><Esc>` 回到普通模式，`<C-hjkl>` 切换窗口，`<C-方向键>` 调整窗口大小，
普通模式 `q` 关闭。

## 行为与维护

- 敏感文件采用精确的文件名、扩展名和目录规则；禁用该 buffer 的持久 undo / swap，
  但保留当前会话的撤销；ShaDa 不持久化寄存器。复制内容若 60 秒内未变化会从
  寄存器和系统剪贴板清除，可将 `vim.g.user_sensitive_clipboard_timeout_ms = 0` 关闭。
- 外部文件变化默认在聚焦、切换 buffer 或离开终端时检查。需要空闲轮询时设置
  `vim.g.user_external_change_poll_ms`（毫秒）；默认不开启全 buffer 定时扫描。
- 连续编辑按变化行判断文件开销；已发现的超长行保持位置记录，删除后再确认是否恢复。
  手动关闭增强功能也不会触发逐键全文扫描。Git 概览在同文件多分屏时只计算一次，
  未变化的窗口尺寸和标记不重复写入，连续更新合并刷新。
- Oil 在第一次浏览目录时加载；目录参数、`:edit`、`:Oil`、快捷键和旧目录会话仍可直接使用。
- Mason 不修改全局 `PATH`；LSP、formatter、linter 与 debugger 会逐项解析系统工具，
  找不到时才使用 Mason 的绝对路径，因此普通终端不会继承 Mason 环境。
- 写入不存在的父目录不会再静默创建目录；确认路径后使用 `:WriteCreateDirs`。
- PDF PNG 缓存目录权限设为仅当前用户可访问，保留不超过 30 天且总量限制为 512 MiB。
- PDF 渲染与缓存扫描按需启动；关闭文件和重载时取消该实例的进程与监听。
  无图形协议或缺少可选工具时显示原因与外部打开入口。
- 签名提示的解析与 Blink 适配分离，插件内部接口缺失时回退到普通签名提示。
  AI 操作也按首次使用加载；主题回调使用具名替换，避免重载时重复注册。
- 修改配置后运行 `./scripts/check.sh`，执行静态、部署故障检查及核心行为回归。
  每个 Neovim 组使用独立进程与临时 config / cache / state / log，复用已安装的插件和工具；
  先核对版本锁与补全二进制，缺少依赖时失败并提示准备，不在检查中安装。
  可用 `./scripts/check.sh performance` 或 `./scripts/check.sh --group static --group ai` 仅运行指定组。
- `python3 scripts/benchmark.py` 保留启动输入、各次日志与结果 JSON；默认每场景四次、丢弃首轮。
  `--baseline /path/to/old-checkout` 可交错对比新旧配置，`--cache warm` 复用各场景的编译缓存。
  `--scene empty` 可缩小测量范围；启动报错会使测量失败。
  此工具只测无头启动，补全、语言服务就绪和终端绘制分别验收。
- `python3 scripts/benchmark-runtime.py --baseline /path/to/old-checkout` 使用同一组场景对比
  项目查找、连续编辑和界面回调，隔离个人缓存与状态，记录耗时及 API 次数。
  这是核心回调微基准，不代表完整按键到屏幕的延迟；方法和结果见 [性能验证](docs/performance.md)。
- `python3 scripts/ui-smoke.py` 在三个尺寸的真实 PTY 中检查按键、终端模式和补全菜单，
  保存终端日志与窗口数据。它模拟无图片协议与 SSH 环境变量，不连接远程主机。
- `python3 scripts/benchmark-scroll.py --baseline /path/to/old-checkout` 对比完整配置中的原生
  滚轮输入到屏幕刷新；`python3 scripts/scroll-smoke.py` 验证终端鼠标协议、分屏和颜色更新。
  添加 `--file /path/to/code.py` 可在原项目内来回滚动实文件；本次结果见 [Python 滚动验证](docs/python-scrolling.md)。
- `python3 scripts/benchmark-wheel-pty.py --file /path/to/code.py --baseline /path/to/old-checkout`
  使用 kitty 终端类型和定频 SGR 滚轮事件测量 Neovim 重绘，包含终端输入解码，不包含 kitty 的实际显示。
  文件需至少 140 行；保留诊断虚拟行和折行，按解码事件配对视口重绘。可加 `--settle-ms 8000` 测量初始化后的状态。
- 依赖准备与 CI 复跑见 [CI 验证](docs/ci-validation.md)，语言端到端检查见
  [工作流矩阵](docs/workflow-matrix.md)，升级和恢复见 [维护指南](docs/maintenance.md)。
