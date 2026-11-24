# Neovim 配置计划

> 定位：功能强大的编辑器，而非大型 IDE。现代、美观、一致、快速。
> 环境：Neovim 0.12.6 · kitty · Wayland · fcitx5 · JetBrainsMono Nerd Font

## 1. 原则

- 能用 0.12 内置的就不用插件（`vim.lsp.config/enable`、`winborder`、`gc`、`:Undotree`、LSP 折叠）
- 除主题、treesitter、启动页、状态栏外，全部插件按需加载；启动目标 < 40ms
- 主题只提供配色，界面结构样式和透明处理由自建的 UI 层统一控制
- snacks.nvim 只启用部分模块（缩进线、界面开关、终端与 lazygit、大文件、Git 链接、图片），UI 风格不合的模块不用

## 2. 目录结构

```
init.lua
lua/config/   options · keymaps · autocmds · lazy · icons
lua/ui/       palette（取色）· highlights（界面层）· transparent（透明层）· themes（主题注册与持久化）
lua/plugins/  ui · navigation · editor · treesitter · lsp · completion · format · lang · diagnostics · git · tools
.luarc.json  .stylua.toml
```

## 3. UI 设计系统

### 三层架构（每次触发 ColorScheme 事件时重新生成）
1. **主题层**：主题始终以不透明方式加载，从中提取语义颜色
   `bg` `fg` `surface` `border` `muted` `accent` `error` `warn` `info` `hint` `ok`
2. **界面层**：用语义颜色统一生成浮窗、边框、侧边栏、补全、诊断、git、缩进线、
   fzf、neo-tree、dropbar、treesitter-context 等高亮组；
   lualine、bufferline 的主题也由这组颜色生成
3. **透明层**（可开关）：
   - 遍历所有高亮组，背景色等于 `bg`（以及侧边栏、浮窗底色）的改成 NONE
   - 界面层自己设置的组跳过（它们已按透明模式取色，如代码块、inlay hint 的淡底色）；
     表示选区、当前项、匹配、计数的组（`ColorColumn`、`QuickFixLine`、`*Sel`、`*CursorLine`、`*Match` 等）保留
   - 主题加载后立即处理一次（避免启动第一帧闪出不透明底色），插件高亮应用后再处理一次
   - 侧边栏、状态栏、标签栏、winbar 改成透明，用细分隔线区分
   - 选区、补全选中项、搜索、diff、诊断气泡、模式标签保留底色（以保存下来的 `bg` 为基准计算混合色）
   - 浮窗透明并带圆角边框；补全菜单在透明模式下也加边框

### 视觉规范
| 元素 | 规则 |
|---|---|
| 层次 | 不透明模式分三层：外框（侧边栏、标签栏、状态栏、命令行，同为 `chrome`，比编辑区深）→ 编辑区（`bg`）→ 浮层（`surface`，比编辑区浅）；透明模式下靠分隔线和强调色区分 |
| 边框 | 全部圆角，颜色为 `border` |
| 强调色 | 只用来表示焦点：当前模式、选中项、当前标签、浮窗标题、当前行号 |
| 状态栏 | 外框底色上的圆角胶囊，模式标签用 accent 实心块 |
| 标签栏 | 卡片式：未选中标签融入外框底色，当前标签与编辑区同色、左侧 accent 竖条，标签间留空隙 |
| 侧边栏 | 不透明模式下为外框色，与标签栏、状态栏相连；透明模式下透明并加分隔线 |
| 当前行 | 淡背景（混合色），当前行号用 accent 加粗 |
| 诊断 | 彩色波浪下划线，气泡背景为语义色按 15% 混合 |
| 缩进线 | muted 按 15% 混合，当前作用域用 accent 按 50% 混合 |
| 字体样式 | 注释斜体，标题加粗 |
| 图标 | 只用 mini.icons 和 `config/icons.lua` |

### 主题（按需加载）
catppuccin（默认 mocha）· tokyonight · kanagawa · rose-pine · nightfox 系列 · gruvbox-material · everforest · onedarkpro

- `<leader>uC`：主题选择器，实时预览；`<leader>ut`：切换透明
- 命令 `:Theme <名称>`、`:Transparent`；选择保存到 `stdpath("state")`
- 默认：catppuccin mocha，不透明
- kitty 的 `background_opacity` 由用户自己设置

## 4. 插件清单

| 分组 | 插件 |
|---|---|
| 基础 | lazy.nvim |
| 界面 | dashboard-nvim（居中样式）· lualine · bufferline · dropbar · which-key（helix 预设）· mini.icons · fidget · snacks.indent · nvim-treesitter-context · neoscroll · nvim-highlight-colors |
| 导航 | fzf-lua · neo-tree（plenary、nui；只当侧边栏）· oil（接管所有目录 buffer，`-` 打开）· aerial · flash · glance（不兼容 0.12 时改用 goto-preview） |
| 编辑 | mini.ai · mini.surround（gs 前缀）· mini.pairs · mini.bufremove · multicursor.nvim · grug-far · nvim-ts-autotag · ts-comments |
| 语言 | nvim-treesitter（main 分支）+ textobjects · mason · mason-lspconfig · nvim-lspconfig · blink.cmp · friendly-snippets · conform · lazydev · SchemaStore · crates.nvim · vimtex · typst-preview · render-markdown · live-preview |
| 诊断 | tiny-inline-diagnostic · trouble · todo-comments |
| Git | gitsigns · diffview |
| 工具 | snacks（terminal 浮动终端 · lazygit · toggle 界面开关 · bigfile · gitbrowse · image）· persistence |

**不用插件实现**：fcitx5 输入法切换 · 自动切到 git 根目录 · 状态列（`ui/statuscolumn.lua`）·
LSP 同名词高亮与 `]]`/`[[` 跳转 · 复制路径 · 保存时删除行尾空格

状态列和同名词高亮没用 statuscol / snacks：它们每次重绘或光标移动都要遍历整个 buffer 的标记或引用，
LSP 语义高亮（如 clangd）会留下大量标记，快速滚动时明显卡顿；自写版本每行只查询这一行

## 5. 语言

| 语言 | LSP | 格式化 |
|---|---|---|
| Lua | lua_ls（系统）+ lazydev | stylua（系统） |
| Python | basedpyright + ruff（优先用项目 `.venv` 里的） | ruff（格式化 + 整理 import，优先用 `.venv` 里的） |
| JS/TS | vtsls · eslint · biome（后两者只在有对应配置的项目里启动，用项目自己的版本） | 有 Biome 配置用 biome，否则 prettierd |
| HTML/CSS | html · cssls | prettierd（CSS 在 Biome 项目里用 biome） |
| C/C++ | clangd（系统） | clang-format（由 clangd 提供） |
| Bash | bashls（系统） | shfmt（系统） |
| JSON/YAML | jsonls · yamlls（系统）（+ SchemaStore） | prettierd（JSON 在 Biome 项目里用 biome） |
| TOML | taplo（系统） | taplo |
| Markdown | marksman（系统） | prettierd |
| Go | gopls（系统） | gofumpt + goimports（系统） |
| Rust | rust-analyzer（系统，clippy 检查） | rustfmt（系统） |
| LaTeX | texlab（系统） | latexindent（系统） |
| Typst | tinymist（系统） | typstyle（系统） |
| Dockerfile | dockerls（系统；compose 文件由 yamlls 按 schema 校验） | — |
| SQL | —（不连数据库） | sql-formatter（项目里的 `.sql-formatter.json` 可设方言） |

- 工具查找顺序：项目本地（`.venv` / `node_modules`）→ 系统 → mason（加在 PATH 末尾，只作后备）。编辑器、命令行、CI、AI agent 用同一个版本
- 官方源（pacman）里有的工具用系统版本，跟随系统更新；mason 只装官方源没有的：basedpyright、vtsls、eslint/html/css/json 语言服务、prettierd、sql-formatter
- Biome 项目缺少 biome（没装依赖）时只提示、不格式化，不会改用 Prettier
- LaTeX：vimtex + latexmk + XeLaTeX；zathura 用 `zathura_simple` 模式（Wayland），支持 SyncTeX
- Typst：typst-preview.nvim 浏览器实时预览（光标同步）· tinymist 导出 PDF · zathura 查看
- SQL：关闭自带 SQL 插件插入模式下 `<C-c>` 开头的补全键（否则 `<C-c>` 退出插入模式会卡一下）
- 其他语言打开时自动安装 treesitter parser

## 6. 行为默认值

- 保存时格式化（`<leader>uf` 开关）；保存时删除行尾空格
- 剪贴板与系统共用（启动后再设置）
- 外部修改文件后自动重载：切回窗口、切换 buffer 时检查，普通模式下每秒检查一次（适配 AI agent 改代码）
- 补全：`<CR>` 确认 · `<Tab>` 选下一个 · 不预选 · 文档窗口自动弹出 · 开启命令行补全
- 诊断：tiny-inline 气泡，可切换为行下虚拟行；插入模式下不刷新
- 折叠：LSP 优先 → treesitter → 缩进；打开文件时全部展开；折叠行带语法高亮并显示行数
- 行内 blame、类型提示默认关闭
- 不带参数启动时显示启动页，会话不自动恢复（启动页按 `s` 或 `<leader>qs` 手动恢复）
- fcitx：离开插入模式时切到英文，进入插入模式时恢复之前的状态（按 buffer 分别记录）
- 平滑滚动：只对翻页类按键生效，约 150ms，大文件里关闭

## 7. 快捷键（leader = 空格，localleader = `\`）

| 前缀 | 用途 |
|---|---|
| 单键 | `<space>` 找文件 · `/` 全局搜索 · `,` 切 buffer · `e` 文件树 · `;` 面包屑 |
| `f` | 文件：`ff` `fr` `fc` `fn` |
| `s` | 搜索：`sw` `sd` `sD` `sh` `sk` `ss` `sr`（grug-far）`sR`（恢复上次搜索） |
| `c` | 代码：`ca` `cr` `cf` `cd` `cs`（大纲） |
| `g` | Git：`gg` lazygit · `gs` `gl` `gb` `gf` `gL` · `gd`/`gD`/`gH` diffview · `gh*` 改动块 |
| `b` | buffer：`bd` `bo` `bp` `bP` `bl` `br` |
| `u` | 界面开关：`uC` 主题 · `ut` 透明 · `uf` 格式化 · `uh` 类型提示 · `uB` blame · `uS` 平滑滚动 … |
| `x` | trouble / quickfix |
| `q` | 会话 / 退出 |
| `m` | 多光标（`ms` `mS` `mA`）|
| `\`（localleader） | 文件类型专属：Markdown `\p` 浏览器预览（HTML 也可用）、`\r` 渲染开关 · Typst `\p` 预览、`\c` 导出 PDF、`\v` zathura 查看 · LaTeX `\l*`（vimtex） |

其他：`gd` `grr` `gI` `gy` `K` · `gpd` `gpr` `gpi` `gpy`（glance）· `s` `S`（flash）·
`gsa` `gsd` `gsr` · `<C-n>` `<C-↑/↓>`（多光标）· `]f` `]c` `]h` `]d` `]e` `]x` `]t` ·
`<C-/>` 终端 · `]]`/`[[` 同名引用 · `<C-s>` 保存 · `<A-j/k>` 移动行 · `<S-h/l>` 切 buffer · `<leader>zi` 折叠 import

## 8. 实施步骤

1. 基础：调整已写好的 config 文件，补上自动命令、`.luarc.json`、`.stylua.toml`
2. UI 设计系统：palette / highlights / transparent / themes
3. 界面插件
4. 导航
5. 编辑
6. 语言
7. 诊断和 Git
8. 工具
9. 验收：无界面模式启动无报错、测启动时间、确认 LSP/treesitter/格式化正常、写快捷键速查

每完成一步就启动一次检查报错，再进入下一步。
