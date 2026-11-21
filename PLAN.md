# Neovim 配置计划

> 定位：功能强大的编辑器，而非大型 IDE。现代、美观、一致、快速。
> 环境：Neovim 0.12.6 · kitty · Wayland · fcitx5 · JetBrainsMono Nerd Font

## 1. 原则

- 能用 0.12 内置的就不用插件（`vim.lsp.config/enable`、`winborder`、`gc`、`:Undotree`、LSP 折叠）
- 除主题、treesitter、启动页、状态栏外，全部插件按需加载；启动目标 < 40ms
- 主题只提供配色，界面结构样式和透明处理由自建的 UI 层统一控制
- 不使用 snacks.nvim

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
   - 遍历所有高亮组，背景色等于 `bg` 的改成 NONE
   - 侧边栏、状态栏、标签栏、winbar 改成透明，用细分隔线区分
   - 选区、补全选中项、搜索、diff、诊断气泡、模式标签保留底色（以保存下来的 `bg` 为基准计算混合色）
   - 浮窗透明并带圆角边框；补全菜单在透明模式下也加边框

### 视觉规范
| 元素 | 规则 |
|---|---|
| 边框 | 全部圆角，颜色为 `border` |
| 强调色 | 只用来表示焦点：当前模式、选中项、当前标签、浮窗标题、当前行号 |
| 状态栏 | 圆角胶囊样式，模式标签用 accent 实心块 |
| 标签栏 | 细竖线分隔，当前标签用 accent 下划线 |
| 侧边栏 | 不透明模式下比编辑区略深；透明模式下透明并加分隔线 |
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
| 界面 | dashboard-nvim（居中样式）· lualine · bufferline · dropbar · which-key（helix 预设）· mini.icons · fidget · indent-blankline · statuscol · nvim-treesitter-context · neoscroll · nvim-highlight-colors |
| 导航 | fzf-lua · neo-tree（plenary、nui；只当侧边栏）· oil（接管所有目录 buffer，`-` 打开）· aerial · flash · glance（不兼容 0.12 时改用 goto-preview） |
| 编辑 | mini.ai · mini.surround（gs 前缀）· mini.pairs · mini.bufremove · multicursor.nvim · grug-far · nvim-ts-autotag · ts-comments |
| 语言 | nvim-treesitter（main 分支）+ textobjects · mason · mason-lspconfig · nvim-lspconfig · blink.cmp · friendly-snippets · conform · lazydev · SchemaStore · crates.nvim · vimtex · typst-preview · render-markdown · live-preview |
| 诊断 | tiny-inline-diagnostic · trouble · todo-comments |
| Git | gitsigns · diffview |
| 工具 | toggleterm（浮动终端、lazygit）· persistence |

**不用插件实现**：fcitx5 输入法切换 · 自动切到 git 根目录 · 大文件保护 · LSP 同名词高亮 ·
界面开关 · 复制路径和 GitHub 链接 · 保存时删除行尾空格

## 5. 语言

| 语言 | LSP | 格式化 |
|---|---|---|
| Lua | lua_ls + lazydev | stylua |
| Python | basedpyright + ruff | ruff（格式化 + 整理 import） |
| JS/TS | vtsls | prettierd |
| HTML/CSS | html · cssls | prettierd |
| C/C++ | clangd | clang-format（由 clangd 提供） |
| Bash | bashls | shfmt |
| JSON/YAML | jsonls · yamlls（+ SchemaStore） | prettierd |
| TOML | taplo | taplo |
| Markdown | marksman | prettierd |
| Go | gopls（系统） | gofumpt + goimports |
| Rust | rust-analyzer（系统，clippy 检查） | rustfmt（系统） |
| LaTeX | texlab | latexindent（系统） |
| Typst | tinymist（系统） | typstyle（系统） |

- 系统里已装的语言服务优先用系统版本，其余由 mason 安装
- LaTeX：vimtex + latexmk + XeLaTeX；zathura 用 `zathura_simple` 模式（Wayland），支持 SyncTeX
- Typst：typst-preview.nvim 浏览器实时预览（光标同步）· tinymist 导出 PDF · zathura 查看
- 其他语言打开时自动安装 treesitter parser

## 6. 行为默认值

- 保存时格式化（`<leader>uf` 开关）；保存时删除行尾空格
- 剪贴板与系统共用（启动后再设置）
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
`<C-/>` 终端 · `<C-s>` 保存 · `<A-j/k>` 移动行 · `<S-h/l>` 切 buffer · `<leader>zi` 折叠 import

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
