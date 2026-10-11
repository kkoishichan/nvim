# UI 设计整改方案

状态：2026-10-11 已实施，见文末「结果」。

2026-10-11，基于工作树（`1f884a2` 之后：无框弹窗样式已删除，签名重载适配已加入，状态栏正在迁出 `specs/ui.lua`）。目标是三个词：简洁、美观、一致；透明背景是一等状态，不是事后补丁。

本方案先定规则，再列现状与规则的差距，最后按阶段给出改动和验收。每条差距都带文件位置，实施时逐条对照。

## 1. 设计原则

1. **一种词汇表**。同一概念在所有表面用同一种表达：一种边框、一套诊断图形、一套 Git 图形、一种提示符写法、一种标题写法。差异只允许来自角色（弹窗 / 面板 / 全屏应用），不允许来自插件默认值。
2. **颜色只有一个来源**。所有自定义高亮从 `palette` 推导，`palette` 只从当前主题的标准组推导。配置里不出现十六进制颜色，混合比例有名字。
3. **一条推导链**。主题切换 → 透明处理 → 一次性重算全部自定义高亮。不允许各模块自己挂 ColorScheme 回调、各自判断透明。
4. **不动插件内部**。只用插件公开选项和高亮组。需要修插件行为的地方走已有的哈希锁定适配器，不新增。
5. **透明模式按角色决定**。哪些表面清底色、哪些保持实底、线条用什么颜色，由角色规则给出，对五个主题一律适用，不按主题名硬编码。

## 2. 规则

### 2.1 色板（`lua/user/core/palette.lua`）

只保留这些键，每个键一句话定义，所有消费者只能用键名：

| 键 | 来源 | 用途 |
|---|---|---|
| `fg` / `bg` | `Normal` | 基准 |
| `surface` | 不透明时 `NormalFloat.bg`，透明时 nil | 浮窗和通知的填充 |
| `line` | `blend(fg, bg, 0.20)` | 窗口分隔线、buffer 标签下划线、透明模式的浮窗边框 |
| `muted` | `blend(fg, bg, 0.60)` | 次要文字：非当前 buffer 标签、Oil 隐藏项、重载标记 |
| `dim` | `blend(fg, bg, 0.72)` | 可见但退后：可见 buffer 标签、which-key 低优先级图标 |
| `subtle` / `strong` | 0.15 / 0.25 | 柔和 / 较重的高亮底：光标词、折叠行、MatchParen、snippet 位点 |
| `accent` | `DiagnosticInfo.fg` | 唯一强调色：滚动条悬停、通知标题 |
| `error` `warn` `info` `hint` | `Diagnostic*` | 严重度 |

删除 `panel`（无人使用）；`accent` 的注释改掉"浮窗边框"的旧说法。现在散落的比例 0.13 / 0.16 / 0.28 / 0.38 / 0.55 / 0.7 / 0.72 全部映射到上表（签名当前参数底 → `subtle`，重载标记 → `muted`，滚动条轨 → `line`，悬停 → `accent` 与 `bg` 的固定混合由色板给出 `accent_soft`，通知边框 → `muted`）。回退值改为中性灰而不是 gruvbox 的色值。

### 2.2 推导链（`theme.lua` → `transparency.lua` → `highlights.lua` → `ui_highlights.lua`）

- 只保留一个 ColorScheme 入口（`user.core.highlights`）。顺序固定：先 `transparency.apply`（同步，不再 `vim.schedule`），再按注册顺序执行所有具名回调。`ui_highlights.apply`、bufferline 的 `highlights` 函数、`backdrop.lua:13`、`conflicts.lua:207`、`statusline_refresh.lua:85`、`ui.lua:534` 的直接调用，全部改为注册到这一个入口。
- 透明开关切换走同一条链（`:colorscheme` 重载后自然触发），不再在 `transparency.toggle` 里手动 `apply`。
- `palette.get()` 在链的开头取一次快照，回调共享同一份，避免某个回调在透明清理前读到实底色。

### 2.3 浮窗

| 角色 | 边框 | 大小 | 背景遮罩 | 例子 |
|---|---|---|---|---|
| 提示 / 预览 | `winborder`（rounded） | 内容决定 | 无 | hover、诊断、签名、补全文档、gitsigns 预览、折叠预览、quickfix 预览、词典、crates、dap-ui 浮窗、outline 预览 |
| 对话框 | `winborder` | 宽 60 以内，居中标题 | 无 | vim.ui.input、vim.ui.select、neo-tree 弹窗、overseer 表单 |
| 应用浮窗 | `winborder` | 0.9 × 0.9，居中 | 60 | fzf 主选择器、Oil、浮动终端、lazygit、scratch |
| 全屏管理器 | none | 0.9 × 0.9，居中 | 60 | Lazy、Mason |
| 内嵌 peek | none，用 winbar 分区 | 高 18 | 无 | Glance |

- 单一来源：`winborder` 是唯一的边框值。fzf、Oil、toggleterm、neo-tree 里显式写的 `"rounded"` 删除（neo-tree 传 `""` 跟随全局）。不读 `winborder` 的插件（ufo、bqf、outline、dap-ui、crates）在 spec 里写 `border = vim.o.winborder`，不再依赖上游默认（现在分别是 rounded+winblend 12、rounded+winblend 12、single、single、none）。
- `winblend` 一律 0（ufo、bqf 的 12 改掉）；`pumblend` 已是 0。
- 遮罩只保留一种实现：`user.core.backdrop`，透明度 60，颜色用 `bg`（透明模式下跳过）。fzf 和 Lazy/Mason 自带的遮罩参数保持 60，zen 的 40 改 60。
- 尺寸只有两档：应用浮窗 0.9（fzf、Oil 的 0.86 和管理器的 0.8 统一到 0.9，`layout.lua` 只留 `float_scale`），对话框按内容。`ui.select` 的 `row 0.4` 与主选择器 `0.48` 统一。
- toggleterm 的两份相同 `float_opts`（`terminal.lua:249` 与 `:320`）合并为一处。

### 2.4 面板

- 尺寸只从 `panels.lua` 取：左 34 列、右 40%、底 35%。`terminal.lua:16` 的 `clamp(28%, 10, 18)`、`native.lua:30` 的 12 行、`ai_terminal.lua:186` 与 `claudecode.lua:52` 各自的 40% 全部改为读 `panels.budget`。
- Outline 的宽度（`navigation.lua:148`，25% 相对宽）改为与左栏同宽 34，standard 没有 Edgy 时两者才对齐。
- 分隔线：所有模式下 `WinSeparator`、`NeoTreeWinSeparator`、`BufferLineOffsetSeparator` 统一为 `line`；不再只在透明模式、只对两个主题修正。
- Edgy 标题图标跟随 `icons` 能力（它只在 extra 加载，但规则要写明）。

### 2.5 状态栏、标签栏、侧栏

- lualine：无分段形状（已是），模式段用主题色，其余段 `fg` 在 `StatusLine` 底上。透明模式下状态栏**保持实底**，作为画面的锚；候选菜单（Pmenu）同样保持实底。这两条是透明模式仅有的实底例外，写进检查。
- bufferline：透明模式下标签底色清空、用 `line` 色下划线连成一条（现有做法，颜色从 `strong` 改为 `line`）；不透明时 `thin` 分隔。非当前标签 `muted`、可见标签 `dim`。
- 行号列：`statuscolumn` 顺序不变（标记、行号、折叠、Git 两格）。

### 2.6 图形词汇

| 概念 | 密集单格场景（signcolumn、滚动条轨） | 带标签场景（状态栏、标签栏、通知） |
|---|---|---|
| 诊断 | 字母 `E W I H` | Nerd 图标 󰅚 󰀪 󰋽 󰌶（无图标能力时 `E: W: I: H:`） |
| Git 行状态 | `┃`（删除 U+F0DA，未跟踪 `┆`） | 计数 `+ ~ -` |
| 修改未保存 | — | `●` |
| 折叠 | U+F47C / U+F460（无图标时 `v` / `>`） | 同左 |

- lightbulb 不再复用 hint 的 󰌶，改用 󰛨（nf-md-lightbulb_on），避免"有提示"和"有操作"看起来一样。
- bufferline 诊断图标（`ui.lua:603-612`，U+F057 等 Font Awesome 系）换成和 lualine 相同的 Material 一组。
- 提示符：fzf 一律 `名称> `（已有 `Projects> ` 等），`vim.ui.input` 一律 `名称: `，`vim.ui.select` 的 prompt 不带标点（fzf 会补 `> `）。标题一律 `" 名称 "` 两侧各一个空格，居中。
- 通知必须有 `title`（来源模块名）。`theme.lua:65,73,79`、`transparency.lua:188,194`、`dict.lua:150`、`folding.lua:110` 补上。

### 2.7 透明模式

按角色而不是按组名清理：

1. **清底色**：编辑区、行号 / 标记 / 折叠列、文件树与所有侧栏、Edgy、TabLine、WinBar、sticky context、Trouble、所有带边框浮窗及其边框和标题、fzf 全部表面、通知正文与边框。现有列表（`transparency.lua:9-111`）保留作为实现，但新增表面时按角色归类，并在检查里以角色断言。
2. **保持实底**：`Pmenu*`（原生候选菜单）、`PmenuSel` / `CursorLine` 类选中行、状态栏。
3. **线条可见**：透明后主题的分隔线和 `FloatBorder.fg` 往往接近原底色而看不见。统一把 `WinSeparator`、`NeoTreeWinSeparator`、`BufferLineOffsetSeparator`、`FloatBorder`、`FloatTitle`（fg）、`FzfLuaBorder`、`BlinkCmp*Border`、`WhichKeyBorder` 的 fg 设为 `line`（标题用 `dim`）。这替代现在只对 tokyonight / catppuccin 的硬编码（`transparency.lua:153-173`）。
4. **遮罩**：透明时没有底色可压暗，`user.core.backdrop` 跳过（现有行为），fzf / Lazy / Mason 的自带遮罩在透明时同样关闭，避免只有它们带黑幕。
5. **通知**：正文、空行、标题留白一起清底（现有 `notify_style` 做法），边框 `muted`，图标与标题保留严重度色。
6. **bufferline**：如 2.5。
7. 主题自带的透明选项（gruvbox `transparent_mode`、vscode `transparent`）继续关闭，透明只由这一处处理。

## 3. 现状与规则的差距

编号对应实施清单。

- D1 边框混用：rounded（全局及 fzf / Oil / toggleterm / neo-tree 显式）、none（Lazy / Mason / Glance / crates / Trouble）、single（dap-ui、outline 预览上游默认）、lazygit 自绘。规则 2.3。
- D2 `plugin_ui.lua:7-9` 的 `assert_default_border` 只断言"用户没设"，上游默认各不相同；README:24 与 :458 的描述与实际不符。规则 2.3，检查改为断言"等于 winborder 或角色允许的 none"。
- D3 `winblend` 12（ufo、bqf）与 0 不一致。
- D4 三套遮罩（fzf、Lazy/Mason、`user.core.backdrop`），zen 用 40。
- D5 toggleterm 浮窗配置重复两份。
- D6 旧注释残留：`terminal.lua:312`、`ui.lua:262-264`、`palette.lua:56-58`。
- D7 `palette.panel` 无消费者。
- D8 已停用的 snacks notifier 仍设样式并被断言（`ui.lua:255-257`、`plugin_ui.lua:49`）；`snacks_notif` / `snacks_picker_*` / `TelescopePrompt` 的排除项散落在 `popups.lua`、`window_roles.lua`、`ui.lua`、`folding.lua`、`editor.lua`；ibl 排除 `dashboard` 但真实 filetype 是 `snacks_dashboard`。
- D9 诊断图形三套（字母、Font Awesome、Material），lightbulb 与 hint 同形。规则 2.6。
- D10 Git 图形按场景不同是合理的，但没有写成规则。规则 2.6 把它写明。
- D11 透明逻辑分散在 transparency 列表、bufferline 分支、ts-context、notify 的 `float=nil`、按主题名的分隔线修正；状态栏未定义。规则 2.7。
- D12 高亮推导有四条以上路径。规则 2.2。
- D13 硬编码颜色：`backdrop.lua:9` 的 `#000000`、`palette.lua` 的 gruvbox 回退、`startup.lua:8` 的 vscode Visual 值（后者是主题回归断言，可保留但要注释）。
- D14 混合比例散落且无名。规则 2.1。
- D15 浮窗比例 0.8 / 0.86 / 0.9，`ui.select` 行位 0.4 与主选择器 0.48。规则 2.3。
- D16 面板尺寸多处定义，Outline 与文件树宽度不一致。规则 2.4。
- D17 显式 `"rounded"` 重复全局值。规则 2.3。
- D18 提示符、标题、通知标题写法不一。规则 2.6。
- D19 Lazy 安装回退主题 `habamax` 不在主题表里；`vim.o.background` 强制 dark（保留，写明）。
- D20 文档过期：`docs/editor-modes.md:3` 的"弹窗样式"、`docs/ui-validation.md:21` 的"四个主题"、`improvement-roadmap.md:54` 与 `standard-boundary-plan.md:57` 对 `float_style.lua` 的引用、`windows.lua:221` 的变量名 `padded`。

## 4. 实施阶段

每阶段独立提交，提交前跑列出的检查组。阶段 0 到 2 不改变外观，只改结构；阶段 3 到 4 改变外观。

### 阶段 0：清理（D5 D6 D7 D8 D19 D20）

删除死代码、重复配置、过期注释和文档引用；`habamax` 回退改为 `default`。不改任何可见行为。

验收：`./scripts/check.sh static integration ui_themes windows`。

### 阶段 1：色板与推导链（D11 的一部分、D12 D13 D14）

1. `palette.lua` 改为 2.1 的键集合，加 `accent_soft`，回退值改中性。
2. `highlights.lua` 成为唯一 ColorScheme 入口，`transparency.apply` 同步排在最前；其余回调迁入注册表；`transparency.toggle` 只改状态并重载主题。
3. 所有混合比例改为色板键。

验收：`ui_themes`（五个主题 × 透明开关，对比度 ≥ 4.5 不变）、`integration`、`statusline_refresh`、`scrolling_colors`；新增断言：仓库 Lua 里没有 `0x` 开头的颜色字面量（允许列表：`startup.lua` 的主题回归值）。

### 阶段 2：边框、尺寸、遮罩（D1 D2 D3 D4 D15 D16 D17）

按 2.3 和 2.4 改每个 spec；`plugin_ui.lua` 的 `assert_default_border` 改为按角色断言；新增一个 `floats` 检查用例：打开每类浮窗，断言 `nvim_win_get_config().border` 等于 winborder 的字符集或角色允许的 none，`winblend == 0`。

验收：`integration floats navigation_ui plugin_ui windows layout_session terminals`。

### 阶段 3：透明模式（D11 其余）

按 2.7 实现角色化清理和线条着色；移除按主题名的分支；`backdrop` 与插件遮罩在透明时统一关闭；bufferline 下划线改 `line`。

验收：`ui_themes` 增加透明场景断言：五个主题下分隔线、浮窗边框、标签下划线与 `bg` 的对比度 ≥ 1.5（线条可见），状态栏与 Pmenu 仍有底色，其余角色无底色；`theme-contrast.json` 记录两种模式。真实终端各主题截图一次，放进 `docs/ui-validation.md`。

### 阶段 4：图形与文字词汇（D9 D10 D18）

按 2.6 统一诊断图标、lightbulb 图标、提示符、标题、通知标题。

验收：`integration`（更新 `navigation_ui` 的滚动条符号表与 bufferline 图标断言）、`mode`（fast 无图标回退）、新增静态检查：`vim.notify(` 调用都带 `title`（脚本 grep，允许列表为空）。

### 阶段 5：文档

README 的 UI 段落、`docs/editor-modes.md`、`docs/ui-validation.md`、`docs/fast-mode.md` 按最终规则重写；本方案归档到 `docs/archive/`。

## 5. 不做的事

- 不恢复 Pmenu 风格的无框弹窗注入，不做 WinNew 兜底重样式。
- 不包装插件内部函数，不新增哈希锁定适配器；现有的保持不动。
- 不引入新插件（noice、dressing、telescope 都不需要）。
- 不做浅色主题支持；`background=dark` 保持强制。
- 不改变键位和工作流，本方案只涉及外观。

## 结果（2026-10-11）

- 阶段 0 到 4 一次实施。`palette` 改为 2.1 的键集合（另加 `accent_soft`、`warn_soft`、`shade`），`highlights` 成为唯一 ColorScheme 入口：同步跑透明处理与各注册回调，再调度一次透明处理清理插件在自己的 ColorScheme 回调里重画的表面；`transparency.toggle` 在主题重载后再跑一次同样的处理。
- 透明处理按角色（editor / chrome / panel / float）清底色，分隔线、浮窗边框、标题统一着色，删除了按主题名的分支。
- `layout.float_border()`、`layout.backdrop()`、`layout.float_scale` 成为边框、遮罩和尺寸的唯一来源；`panels.right_ratio` / `bottom_ratio` 供终端、AI 面板和原生回退共用。
- `user.core.icons` 定义诊断、Git、折叠和代码操作图形；私有区字形以码点书写，避免被工具静默丢弃。
- 27 处无标题的 `vim.notify` 补上标题；`scripts/lint-ui.py` 进入静态检查组。
- 偏离方案的两点：TreesitterContext 直接链接到 Normal，而不是设底色后再清；`gray` 键并入 `muted`。
- 未做：真实终端截图（需交互终端）；`docs/improvement-roadmap.md` 与 `docs/standard-boundary-plan.md` 作为历史记录保留对 `float_style.lua` 的引用。
