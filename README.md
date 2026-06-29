# Neovim 配置

这是一个从零整理的现代 Neovim 配置。目标是让 Neovim 更接近
IDE 的日常工作流，同时保留 Vim 的编辑模型：

- `lazy.nvim` 管理插件，首次启动自动 bootstrap。
- `gruvbox` dark hard 主题。
- `fzf-lua` 负责查找、搜索、LSP 列表和 Git 列表。
- `oil.nvim` 负责像编辑 buffer 一样管理文件系统。
- `neo-tree.nvim` 负责左侧文件树、buffer 页和 Git 状态页。
- `blink.cmp` 负责补全、snippet、签名帮助。
- `nvim-lspconfig` + Mason 负责语言服务和外部工具安装。
- `conform.nvim` 负责格式化，`nvim-lint` 负责 lint。
- `nvim-ufo` + Tree-sitter 负责现代折叠。
- `toggleterm.nvim` 负责交互式终端。
- `overseer.nvim` 负责可重复运行的任务。
- `neotest` 负责测试，`nvim-dap` + `dap-ui` 负责调试。

当前环境验证过的 Neovim 版本是 `0.12.3`。建议使用 Neovim `0.11+`。

## 目录结构

```text
~/.config/nvim
├── init.lua
├── lazy-lock.json
├── lua/user/core
│   ├── autocmds.lua
│   ├── commands.lua
│   ├── diagnostics.lua
│   ├── keymaps.lua
│   ├── layout.lua
│   ├── options.lua
│   ├── panels.lua
│   └── pdf.lua
└── lua/user/plugins
    ├── completion.lua
    ├── dap.lua
    ├── editor.lua
    ├── folding.lua
    ├── formatting.lua
    ├── git.lua
    ├── lang.lua
    ├── lint.lua
    ├── lsp.lua
    ├── media.lua
    ├── multicursor.lua
    ├── navigation.lua
    ├── performance.lua
    ├── picker.lua
    ├── tasks.lua
    ├── terminal.lua
    ├── test.lua
    ├── tools.lua
    ├── treesitter.lua
    └── ui.lua
```

## 首次启动

把配置放在：

```bash
~/.config/nvim
```

启动：

```bash
nvim
```

首次启动会自动安装 `lazy.nvim` 和插件。之后可以在 Neovim 内运行：

```vim
:Lazy
:Mason
:MasonToolsInstall
:checkhealth
```

## 系统依赖

基础依赖：

- `git`：安装插件。
- `rg`：全文搜索。
- `fd`：文件和目录查找。
- `fzf`：`fzf-lua` 后端。
- `curl` 或系统网络工具：部分插件和 Mason 工具安装需要。

建议安装：

- `lazygit`：`<leader>gg` Git TUI。
- `zoxide`：项目选择器会把打开过的目录加入 zoxide，并从 zoxide 收集项目。
- `kitty`：`image.nvim` 使用 kitty 图像协议。
- `magick`：图片处理。
- `poppler`：`pdftoppm` / `pdfinfo`，用于 PDF 图片式预览。
- `zathura` 或 `xdg-open`：外部 PDF 查看。
- `latexmk`：LaTeX 编译。
- `typst`：Typst 编译。
- `yarn`：`markdown-preview.nvim` 构建。
- `fcitx5-remote` 或 `fcitx-remote`：中文输入法模式切换。

## 基础约定

- `<leader>` 是空格。
- `<localleader>` 是反斜杠。
- 鼠标启用。
- 使用系统剪贴板 `unnamedplus`。
- 默认显示绝对行号和相对行号。
- `Esc` 清搜索高亮。
- `<Space>` 本身被设为 `<Nop>`，避免和 leader 冲突。

## Dashboard

启动无文件时显示 `snacks.dashboard`。

Dashboard 入口：

| 键 | 功能 |
| --- | --- |
| `f` | Find File |
| `n` | New File |
| `g` | Find Text |
| `p` | Find Project |
| `d` | Open Directory |
| `s` | Restore Session |
| `q` | Quit |

`snacks.nvim` 当前只启用 dashboard、input、scratch、zen。
snacks 的 picker、notifier、scroll、indent、words、terminal、lazygit、explorer、quickfile
都已关闭，由更适合当前需求的插件接管。

## 常用键位

### 基础

| 键 | 功能 |
| --- | --- |
| `<leader>w` | 保存 |
| `<leader>q` | 关闭当前窗口 |
| `<leader>Q` | 退出全部 |
| `<leader>L` | Lazy |
| `<leader>M` | Mason |
| `<leader>?` | 键位搜索 |
| `<leader>:` | 命令历史 |
| `<leader>.` | Scratch buffer |
| `<leader>z` | Zen mode |

### 窗口

| 键 | 功能 |
| --- | --- |
| `<leader>-` | 下方横向 split |
| `<leader>\|` | 右侧纵向 split |
| `<C-h>` / `<C-j>` / `<C-k>` / `<C-l>` | 切换窗口焦点 |
| `<C-Up>` / `<C-Down>` | 调整窗口高度 |
| `<C-Left>` / `<C-Right>` | 调整窗口宽度 |

### 编辑

| 键 | 功能 |
| --- | --- |
| `gc` | 注释选区或 motion |
| `gcc` | 注释当前行 |
| `<` / `>` | visual 模式缩进和反缩进，并保留选区 |
| `J` / `K` | visual 模式移动选区 |
| `J` | normal 模式合并行并保持视图 |
| `n` / `N` | 搜索下一项/上一项并居中 |

### Quickfix 和 Location List

| 键 | 功能 |
| --- | --- |
| `]q` / `[q` | quickfix 下一条/上一条 |
| `]Q` / `[Q` | quickfix 最后一条/第一条 |
| `]l` / `[l` | loclist 下一条/上一条 |
| `<leader>xq` | Trouble quickfix |
| `<leader>xl` | Trouble loclist |

## 查找和项目

主要由 `fzf-lua` 提供。

| 键 | 功能 |
| --- | --- |
| `<leader><space>` | Smart find |
| `<leader>ff` | 查找文件 |
| `<leader>fg` / `<leader>/` | live grep |
| `<leader>fG` | grep glob |
| `<leader>fb` / `<leader>,` | buffers |
| `<leader>fo` | recent files |
| `<leader>fl` | 当前 buffer 行 |
| `<leader>fL` | 已打开 buffer 行 |
| `<leader>fw` | 搜索光标词或 visual 选区 |
| `<leader>fR` | 搜索替换 |
| `<leader>fq` | quickfix picker |
| `<leader>fc` | commands |
| `<leader>fh` | help |
| `<leader>fk` | keymaps |

`<leader>ff` 查找隐藏文件和被 ignore 的文件，但跳过 `.git` 和 `.jj`
这类版本控制元数据目录。

项目和目录：

| 键 | 功能 |
| --- | --- |
| `<leader>fp` | 选择项目，设置 tab-local cwd，并打开 Oil |
| `<leader>fd` | 选择目录，设置 tab-local cwd，并打开 Oil |
| `<leader>fr` | 将当前文件所在项目设为 tab-local cwd，并打开 Oil |
| `<leader>f.` | 将当前文件目录设为 tab-local cwd，并打开 Oil |

工作目录使用 `:tcd`，因此每个 tab 可以有自己的 cwd。查看当前目录：

```vim
:pwd
```

## 文件管理

### Oil

`oil.nvim` 用 buffer 编辑文件系统。修改文件名、移动文件、删除文件、新建文件后，
像普通 buffer 一样 `:w` 应用改动。

| 键 | 功能 |
| --- | --- |
| `-` | 打开当前文件所在目录 |
| `<leader>E` | 打开当前 cwd |

Oil 会显示隐藏文件，但总是隐藏 `.git` 和 `.jj` 目录。删除文件默认进入 trash。

### Neo-tree

`neo-tree.nvim` 是左侧侧边栏，包含三个页：

- Files
- Buffers
- Git

| 键 | 功能 |
| --- | --- |
| `<leader>e` | toggle 左侧 Neo-tree，并 reveal 当前文件 |

Neo-tree 默认显示 dotfiles，但隐藏 gitignored 文件。需要查看 gitignored 文件时，
在 Neo-tree 内使用过滤相关内置动作。

## Buffer 和标签栏

`bufferline.nvim` 显示 buffer 标签栏。

| 键 | 功能 |
| --- | --- |
| `[b` / `]b` | 上一个/下一个 buffer |
| `<M-1>` 到 `<M-9>` | 跳到对应序号 buffer |
| `<M-0>` | 跳到最后一个 buffer |
| `[B` / `]B` | 向左/向右移动 buffer |
| `<leader>bd` | 关闭当前 buffer |
| `<leader>bD` | 选择并关闭 buffer |
| `<leader>bp` | 选择 buffer |
| `<leader>bP` | pin/unpin buffer |
| `<leader>bo` | 关闭其他 buffers |
| `<leader>bl` / `<leader>br` | 关闭左侧/右侧 buffers |

## LSP 和代码导航

LSP 由 `nvim-lspconfig` 和 `mason-lspconfig` 管理。补全能力来自 `blink.cmp`。

| 键 | 功能 |
| --- | --- |
| `K` | hover |
| `gd` | Glance definition |
| `gD` | Glance declaration |
| `gi` | Glance implementation |
| `gy` | Glance type definition |
| `gr` | Glance references |
| `<leader>ca` | code action |
| `<leader>cr` | rename symbol |
| `<leader>ci` | incoming calls |
| `<leader>co` | outgoing calls |
| `<leader>cs` | document symbols |
| `<leader>cS` | workspace symbols |
| `<leader>cl` | 手动 lint |
| `<leader>cf` | 格式化 |
| `<leader>cb` | breadcrumb pick |
| `<leader>uh` | toggle inlay hints，只有服务端支持时存在 |

Glance 窗口里：

- `q` / `Q` / `Esc` 关闭。
- `<CR>` 跳转。
- `s` / `v` / `t` 分别用 split、vsplit、tab 打开。
- `<C-q>` 将当前结果送入 quickfix。

## 补全

补全使用 `blink.cmp`，preset 是 `enter`。

主要行为：

- `Enter` 接受候选。
- `Tab` / `S-Tab` 使用该 preset 的默认候选和 snippet 行为。
- 自动显示文档窗口，延迟 `300ms`。
- 启用 ghost text。
- 启用签名帮助。

补全来源：

- `lazydev`
- LSP
- path
- snippets
- buffer

## 诊断

诊断显示采用当前行展开的 virtual lines，避免很长的 inline diagnostic 撑出屏幕。

| 键 | 功能 |
| --- | --- |
| `[d` / `]d` | 上一个/下一个 diagnostic |
| `<leader>cd` | 当前行 diagnostic float |
| `<leader>cD` | diagnostics 放入 loclist |
| `<leader>ud` | 诊断显示模式循环：lines -> text -> off |
| `<leader>xx` | Trouble workspace diagnostics |
| `<leader>xX` | Trouble buffer diagnostics |

## 折叠和上下文

折叠由 `nvim-ufo` 提供，provider 优先使用 Tree-sitter，其次 indent。

| 键 | 功能 |
| --- | --- |
| `zR` | 打开所有 folds |
| `zM` | 关闭所有 folds |
| `zr` | 逐级打开 folds |
| `zm` | 逐级关闭 folds |
| `zK` | 预览当前 fold |
| `<leader>uc` | toggle sticky context |
| `[c` | 跳到 sticky context |

Sticky context 使用 `nvim-treesitter-context`，最多显示 5 行。

## Tree-sitter

Tree-sitter 使用 `nvim-treesitter` 的 `main` 分支，手动调用
`vim.treesitter.start()` 启用高亮和缩进。

已安装 parser 覆盖：

```text
asm bash c cmake cpp css diff dockerfile git_config gitcommit gitignore
go gomod gosum gowork html hyprlang javascript json latex lua make
markdown markdown_inline nasm python query rust sql systemverilog toml
tsx typescript typst vim vimdoc vue yaml zsh
```

RISC-V 文件类型映射到 `riscv`，Tree-sitter parser 使用 `asm` 注册。

Tree-sitter textobjects 只负责跳转：

| 键 | 功能 |
| --- | --- |
| `]m` / `[m` | 下一个/上一个函数开头 |
| `]M` / `[M` | 下一个/上一个函数结尾 |
| `]]` / `[[` | 下一个/上一个 class 开头 |
| `][` / `[]` | 下一个/上一个 class 结尾 |

## 终端

终端使用 `toggleterm.nvim`，实现接近 VSCode 的底部终端区：

- 一个底部终端面板可以管理多个 terminal。
- 可以新建、切换、split、选择、杀掉、重命名。
- 另有浮动 terminal。

| 键 | 功能 |
| --- | --- |
| `<C-/>` | toggle 底部 terminal |
| `<leader>tt` | toggle 底部 terminal |
| `<leader>tn` | 新建 terminal |
| `<leader>ts` | split terminal |
| `<leader>t]` / `<leader>t[` | 下一个/上一个 terminal |
| `<leader>tl` | 选择 terminal |
| `<leader>tk` | kill 当前 terminal |
| `<leader>tr` | 重命名 terminal |
| `<leader>tf` | 浮动 terminal |

终端内：

| 键 | 功能 |
| --- | --- |
| `<Esc><Esc>` | 回到 normal mode |
| `<C-h/j/k/l>` | 离开 terminal mode 并切换窗口 |
| `<C-Up/Down/Left/Right>` | 调整窗口大小 |
| `q` | normal mode 下隐藏 terminal |

## 任务

任务使用 `overseer.nvim`。适合运行构建、测试、lint、脚本和项目任务。

| 键 | 功能 |
| --- | --- |
| `<leader>jr` | 选择并运行任务 |
| `<leader>jt` | toggle task list |
| `<leader>jo` | 打开 task list |
| `<leader>jc` | 关闭 task list |
| `<leader>ja` | task action |
| `<leader>jR` | 重跑最近完成的任务 |
| `<leader>js` | 创建 shell task |

交互式 shell 用 terminal。可重复、可查看状态、可重跑的命令用 Overseer。

## Git

| 键 | 功能 |
| --- | --- |
| `<leader>gg` | LazyGit |
| `<leader>gG` | LazyGit current file |
| `<leader>gd` | toggle Diffview |
| `<leader>gf` | 当前文件历史 |
| `<leader>gr` | 仓库历史 |
| `<leader>gs` | fzf git status |
| `<leader>gc` | fzf git commits |

Hunk：

| 键 | 功能 |
| --- | --- |
| `]h` / `[h` | 下一个/上一个 hunk |
| `<leader>ghs` | stage hunk |
| `<leader>ghr` | reset hunk |
| `<leader>ghS` | stage buffer |
| `<leader>ghu` | undo stage hunk |
| `<leader>ghp` | preview hunk |
| `<leader>ghb` | blame line |
| `<leader>ghB` | toggle line blame |
| `<leader>ghd` | diff buffer |
| `ih` | hunk text object |

Conflict：

| 键 | 功能 |
| --- | --- |
| `]x` / `[x` | 下一个/上一个 conflict |
| `<leader>gxo` | choose ours |
| `<leader>gxt` | choose theirs |
| `<leader>gxb` | choose both |
| `<leader>gx0` | choose none |
| `<leader>gxl` | conflicts 放入 quickfix |

## 测试

测试使用 `neotest`。

| 键 | 功能 |
| --- | --- |
| `<leader>rr` | 运行最近的测试 |
| `<leader>rf` | 运行当前文件测试 |
| `<leader>rd` | 用 DAP debug 最近的测试 |
| `<leader>rx` | 停止测试 |
| `<leader>rs` | toggle summary |
| `<leader>ro` | 打开测试输出 |
| `<leader>rO` | toggle output panel |
| `<leader>rw` | watch 当前文件 |

已配置 adapters：

- Python
- Go
- Jest
- Vitest
- Rust

## 调试

调试使用 `nvim-dap`、`dap-ui`、`nvim-dap-virtual-text`。

| 键 | 功能 |
| --- | --- |
| `<F5>` / `<leader>dc` | continue / start |
| `<F10>` / `<leader>do` | step over |
| `<F11>` / `<leader>di` | step into |
| `<S-F11>` / `<leader>dO` | step out |
| `<leader>dC` | run to cursor |
| `<leader>db` | toggle breakpoint |
| `<leader>dB` | conditional breakpoint |
| `<leader>dr` | toggle DAP REPL |
| `<leader>dl` | run last |
| `<leader>dt` | terminate |
| `<leader>du` | toggle DAP UI |
| `<leader>de` | eval expression |

已配置：

- C/C++：`codelldb`
- Go：`delve`
- Python：`debugpy`
- JavaScript/TypeScript/Vue：`js-debug-adapter`

## 多光标

多光标使用 `jake-stewart/multicursor.nvim`。

| 键 | 功能 |
| --- | --- |
| `<M-n>` / `<leader>vn` | 添加下一个匹配 |
| `<M-p>` / `<leader>vN` | 添加上一个匹配 |
| `<M-s>` / `<leader>vs` | 跳过下一个匹配 |
| `<leader>vS` | 跳过上一个匹配 |
| `<M-a>` / `<leader>va` | 添加所有匹配 |
| `<M-Down>` / `<leader>vj` | 向下添加光标 |
| `<M-Up>` / `<leader>vk` | 向上添加光标 |
| `<leader>vm` | 在 visual selection 中匹配 |
| `<leader>vc` | selection 转 cursors |
| `<leader>v=` | 对齐 cursors |
| `<leader>vl` | toggle cursor lock |
| `<leader>vx` / `<M-x>` | 删除 cursor |
| `<leader>vr` | 恢复上次 cursors |
| `<Esc>` | 多光标会话中清空 cursors |

多光标激活时会临时禁用 `mini.pairs`，避免自动括号和多光标输入回放打架。

## Markup

### Markdown

- `markview.nvim` 提供 Neovim 内部渲染。
- `markdown-preview.nvim` 提供浏览器预览。

| 键 | 功能 |
| --- | --- |
| `<leader>mp` | Markview toggle |
| `<leader>ms` | Markview split preview |
| `<leader>mh` | Markview hybrid mode |
| `<leader>mv` | Markdown browser preview |

### LaTeX

LaTeX 使用 `vimtex`，编译器是 `latexmk`，查看器是 `zathura`。

| 键 | 功能 |
| --- | --- |
| `<leader>mc` | 编译 |
| `<leader>mv` | 预览 |
| `<leader>mt` | TOC |
| `<leader>me` | errors |
| `<leader>mk` | stop compiler |
| `<leader>mx` | clean aux files |
| `<leader>mi` | info |

### Typst

Typst 使用 `typst-preview.nvim` 和 `tinymist`。

| 键 | 功能 |
| --- | --- |
| `<leader>mc` | 编译 PDF |
| `<leader>mv` | preview toggle |
| `<leader>mk` | stop preview |
| `<leader>mf` | follow cursor toggle |
| `<leader>my` | sync cursor |

## 图片和 PDF

图片使用 `image.nvim`，backend 是 kitty，processor 是 `magick_cli`。

| 键 | 功能 |
| --- | --- |
| `<leader>mI` | toggle images |
| `<leader>mr` | image report |

支持直接打开：

```text
avif bmp gif jpeg jpg png svg webp
```

PDF 当前实现为图片式 buffer 预览，不是完整 PDF 阅读器。

PDF buffer 内：

| 键 | 功能 |
| --- | --- |
| `j/k/h/l` 或方向键 | 平移页面 |
| `<PageDown>` / `<Space>` | 向下滚动 |
| `<PageUp>` | 向上滚动 |
| `]p` / `J` | 下一页 |
| `[p` / `K` | 上一页 |
| `gg` / `G` | 第一页/最后一页 |
| `g` | 跳到指定页 |
| `+` / `=` | 放大 |
| `-` | 缩小 |
| `0` | 重置缩放 |
| `r` | 重新渲染 |
| `o` | 外部打开 PDF |
| `q` | 关闭 PDF preview buffer |

外部打开 PDF：

| 键 | 功能 |
| --- | --- |
| `<leader>mo` | `:PdfOpen` |

## Session

Session 使用 `persistence.nvim`。

| 键 | 功能 |
| --- | --- |
| `<leader>ss` | 恢复当前目录 session |
| `<leader>sS` | 选择 session |
| `<leader>sl` | 恢复上次 session |
| `<leader>sd` | 停止保存 session |

恢复 session 会恢复 session 保存时的工作目录状态。

## UI

| 键 | 功能 |
| --- | --- |
| `<leader>ul` | toggle relative line numbers |
| `<leader>uw` | toggle wrap |
| `<leader>un` | dismiss notifications |
| `<leader>uu` | undo tree |
| `<leader>uc` | sticky context |
| `<leader>ud` | diagnostic display |
| `<leader>uh` | inlay hints，按 buffer 和 LSP 能力启用 |
| `<leader>n` | notification history |

通知使用 `nvim-notify`，右上角显示，slide 动画，LSP progress 会合并更新。

平滑滚动使用 `neoscroll.nvim`，接管：

```text
<C-u> <C-d> <C-b> <C-f> <C-y> <C-e> zt zz zb
```

## 支持的语言

LSP：

```text
asm_lsp autotools_ls bashls basedpyright biome clangd cssls dockerls
emmet_language_server gopls html jsonls lua_ls marksman neocmake ruff
rust_analyzer sqlls tailwindcss taplo texlab tinymist verible vtsls
vue_ls yamlls
```

Formatter / linter 工具：

```text
asmfmt checkmake clang-format cmakelang cmakelint gofumpt goimports
golangci-lint hadolint latexindent markdownlint-cli2 prettier selene
shellcheck shfmt sqruff stylelint stylua typstyle yamllint
```

常见语言覆盖：

- C/C++：`clangd`、`clang-format`、DAP 使用 `codelldb`。
- CMake：`neocmake`、`cmakelang`、`cmakelint`。
- Makefile：Tree-sitter make、`checkmake` lint。
- Shell/Zsh：`bashls`、`shellcheck`、`shfmt`。
- Python：`basedpyright`、`ruff`、`debugpy`、`neotest-python`。
- Rust：`rustaceanvim` 管理 `rust-analyzer`、DAP、neotest。
- Go：`gopls`、`goimports`、`gofumpt`、`golangci-lint`、`delve`。
- JS/TS/Vue：`vtsls`、`vue_ls`、`biome`、`prettier`、JS DAP。
- HTML/CSS/Tailwind：`html`、`cssls`、`tailwindcss`、`emmet`。
- Lua：`lua_ls`、`stylua`、`selene`。
- Markdown：`marksman`、`markdownlint-cli2`、`prettier`。
- LaTeX：`texlab`、`vimtex`、`latexindent`。
- Typst：`tinymist`、`typstyle`、`typst-preview`。
- SQL：`sqlls`、`sqruff`。
- Dockerfile：`dockerls`、`hadolint`。
- Verilog/SystemVerilog：`verible` LSP、lint、format。
- RISC-V/asm：`asm_lsp`、`asmfmt`，RISC-V 文件类型复用 asm parser。

大多数工具的项目级规则由工具自己查找配置文件。例如：

- `clangd` 查 `compile_commands.json`。
- `ruff` 查 `pyproject.toml` / `ruff.toml`。
- `stylua` 查 `stylua.toml`。
- `selene` 查 `selene.toml`。
- `verible` 使用 `--rules_config_search` 查项目级规则。
- `biome` 配置为必须在 cwd 中找到项目配置才格式化。

## 格式化和 lint

格式化：

| 键 | 功能 |
| --- | --- |
| `<leader>cf` | 格式化当前 buffer 或 visual selection |

自动格式化在保存前运行。关闭：

```vim
:FormatDisable
```

只关闭当前 buffer：

```vim
:FormatDisable!
```

重新启用：

```vim
:FormatEnable
```

Lint 自动在 `BufEnter`、`BufWritePost`、`InsertLeave` 触发。手动运行：

```vim
<leader>cl
```

## 外部文件变化

配置针对 AI agent 或外部工具批量改文件做了处理：

- focus/buffer/terminal 切换时自动 `:checktime`。
- 聚焦时每 2 秒轮询一次。
- 未修改 buffer 会自动 reload。
- 有未保存修改时不会覆盖，会通知用户。
- 删除的文件会保留 buffer。
- 多文件 reload 通知会合并。

## 大文件

`faster.nvim` 负责 bigfile/longline 优化。遇到大文件或超长行时会关闭重功能：

```text
bigfile flag, illuminate, matchparen, lsp, treesitter,
indent_blankline, vimopts, syntax, filetype
```

## 可用命令

常用自定义命令：

| 命令 | 功能 |
| --- | --- |
| `:DiffDisk` | 当前 buffer 与磁盘文件 diff |
| `:ProjectRoot` | 设置当前 tab cwd 到项目根，并打开 Oil |
| `:ProjectPick` | 选择项目，设置 cwd，并打开 Oil |
| `:DirectoryPick` | 选择目录，设置 cwd，并打开 Oil |
| `:FileDir` | 设置 cwd 到当前文件目录，并打开 Oil |
| `:PdfOpen [file]` | 外部打开 PDF |
| `:TypstCompilePdf` | 当前 Typst 编译为 PDF |
| `:FormatDisable[!]` | 关闭自动格式化 |
| `:FormatEnable` | 启用自动格式化 |
| `:OverseerRestartLast` | 重跑最近完成的 Overseer task |

## 维护

插件：

```vim
:Lazy
:Lazy sync
```

工具：

```vim
:Mason
:MasonToolsInstall
:MasonToolsUpdate
```

健康检查：

```vim
:checkhealth
```

Headless 启动检查：

```bash
nvim --headless '+qa'
```

格式化 Lua 配置：

```bash
stylua ~/.config/nvim/lua
```

查看启动耗时：

```bash
nvim --startuptime /tmp/nvim-startuptime.log '+qa'
```

## 设计取舍

- 文件查找、搜索、LSP picker 使用 `fzf-lua`，不使用 Snacks picker。
- 通知使用 `nvim-notify`，不使用 Snacks notifier。
- 滚动使用 `neoscroll.nvim`，不使用 Snacks scroll。
- 缩进线使用 `indent-blankline.nvim`，不使用 Snacks indent。
- 当前词高亮使用 `vim-illuminate`，不使用 Snacks words。
- 文件树使用 `neo-tree.nvim`，文件系统编辑使用 `oil.nvim`。
- 任务系统使用 `overseer.nvim`，交互式 shell 使用 `toggleterm.nvim`。
- 测试和调试分开：`neotest` 管测试结构，`nvim-dap` 管调试协议。
