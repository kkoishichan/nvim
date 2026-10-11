# buffer 标签栏重设计

2026-10-12，基于 `a298a93` 之后的工作树。标签栏由 bufferline.nvim 提供，standard / extra 开启（`ui_panels` 能力），fast 没有。本方案分功能和样式两部分；样式按透明与不透明两种哲学分别设计，互不影响。

## 1. 功能

### 1.1 它是什么

这套配置用标签页承载工作区：每个 tab 一个项目根（`vim.t.user_project_root`、`tcd`），搜索、终端、任务都跟着当前 tab 的工作区走。标签栏因此应该回答一个问题："当前工作区打开了哪些文件、我在哪一个"，而不是"整个进程打开了哪些 buffer"。

### 1.2 现状与决定

| 编号 | 现状 | 决定 |
|---|---|---|
| F1 | `mode = "buffers"` 列出全部 buffer，不分工作区；多项目并行时每个 tab 都看到别的项目的文件 | 按工作区过滤：只列文件在当前 tab 工作区（`project.root()`）之内、或 `b.user_project_root` 绑定到该工作区的 buffer。没有工作区归属的 buffer（临时、无名）归当前 tab。实现用 bufferline 的 `custom_filter`，过滤只影响显示，不改 buffer 列表本身 |
| F2 | 右侧没有任何工作区信息 | 右侧固定区（`custom_areas.right`）显示工作区名，多于一个 tab 时加 `n/N`：`nvim 2/3`。这是切换 tab 时唯一的锚点 |
| F3 | `<M-1>`…`<M-9>` 按序号跳转，但 `numbers = "none"`，序号看不见，要数 | 显示序号：`numbers = "ordinal"`，用 `muted` 色、不加粗，紧贴名字前（`1 init.lua`）。序号随过滤后的列表排，和按键一致 |
| F4 | `always_show_bufferline = false`，第二个文件打开时整栏突然出现，编辑区下移一行 | 常显。栏同时承担工作区头部（F2），单文件时也有内容 |
| F5 | `sort_by = "id"`，新文件总排在最右 | `insert_after_current`：新打开的文件排在当前项之后，和阅读顺序一致，也是 VSCode 的做法 |
| F6 | 标签里显示 error 和 warning 计数 | 只显示 error 计数；warning 在行号列和状态栏已经有，标签里保留最严重的一档就够 |
| F7 | 修改标记 `●`，关闭按钮悬停才出现，中键无动作 | 保留 `●`；去掉悬停关闭按钮（它依赖未开启的 `mousemoveevent`，出现时还会改变标签宽度），中键关闭（`middle_mouse_command`）补上，右键、中键、`<leader>bd` 三个入口足够 |
| F8 | pin 用插件默认图标，置顶后混在列表里 | 置顶项排最前，图标统一为 `󰐃`（nf-md-pin），`muted` 色 |
| F9 | 同名文件显示目录前缀（`show_duplicate_prefix`） | 保留，前缀用 `muted` |
| F10 | 侧栏偏移标题 `Explorer` | 保留；标题随侧栏底色，分隔格延续窗口分隔线（现有做法） |
| F11 | `tab_size = 0`、`max_name_length = 24`、截断标记 | 保留 |

过滤（F1）的边界：`:ProjectPick` / `:Cd` 改变工作区后栏立即换内容（bufferline 在 `DirChanged` / `TabEnter` 上重绘，必要时手动 `BufferLineRefresh`）；关闭当前 buffer 时 `user.core.buffers` 选替代 buffer 的逻辑不变，但候选优先取同工作区的。

## 2. 样式

两种模式各自成立，切换即时生效，互不借用对方的元素。

### 2.1 不透明：层

| 元素 | 样式 |
|---|---|
| 栏底 | `sunken`（比编辑区低一阶，和 sticky context 同一层） |
| 未选中项 | 文字 `muted`，底 `sunken`，无边框 |
| 当前项 | 文字 `fg`，底 `bg`（编辑区色，从栏里"抬"出来），不加粗不斜体 |
| 可见但非当前（其他分屏里的）项 | 文字 `dim`，底 `sunken` |
| 分隔 | 无分隔符，相邻项之间一格空白；填充与底色区分已足够 |
| 序号 / 前缀 / pin | `muted`，当前项上随文字为 `fg` |
| 修改标记 `●` | `accent` |
| error 计数 | `error` 色 |
| 右侧工作区名 | `dim`，底 `sunken` |
| 侧栏标题 | 侧栏底色，分隔格延续 `WinSeparator` |

### 2.2 透明：线与字

| 元素 | 样式 |
|---|---|
| 栏底 | 无 |
| 整栏 | 一条 `line` 色下划线，把栏和编辑区分开而不占行 |
| 当前项 | 文字 `fg`，下划线同为 `line` 色，只靠文字区分（试过 VS Code 式的断开基线加竖线分隔，不好看，已撤销） |
| 未选中项 | 文字 `muted` |
| 可见项 | 文字 `dim` |
| 分隔 | 无 |
| 序号 / 前缀 / pin / 修改标记 / error 计数 | 同不透明 |
| 右侧工作区名 | `dim` |
| 侧栏标题 | 无底，不画下划线：它是侧栏的头部而不是标签列表的一部分 |

### 2.3 共同规则

- 所有颜色来自色板键；图标来自 `user.core.icons`（文件图标由 mini.icons 提供，fast 没有图标时只显示文字）。
- 不透明时没有任何线条，透明时没有任何填充。`ui_themes` 的整表往返对比继续作为护栏。

## 3. 实施

1. `lua/user/specs/ui.lua`：`custom_filter`、`custom_areas.right`、`numbers = "ordinal"`、`always_show_bufferline = true`、`sort_by = "insert_after_current"`、`middle_mouse_command`、pin 图标、诊断只 error；`bufferline_highlights` 按 2.1 / 2.2 重写（两个分支各自完整，不共享"先一套再覆盖"的写法）。
2. `lua/user/core/buffers.lua`：替代 buffer 候选优先同工作区。
3. 工作区变化时刷新：`DirChanged`、`TabEnter`、`User ProjectChanged`（如有）上 `BufferLineRefresh`。
4. 检查：`integration/startup.lua` 的 bufferline 断言改为新选项；新增用例：两个 tab 各绑一个临时项目，各开一个文件，断言每个 tab 的标签栏只含本工作区的文件、右侧显示 `name n/N`、序号从 1 起；`ui_themes` 在两种模式下断言当前项与未选中项的底色 / 下划线按 2.1 / 2.2。
5. 文档：README 标签栏段落、`docs/editor-modes.md` 的按模式 UI 表、本方案归档。

验收：`./scripts/check.sh static integration ui_themes layout_session`，再真实终端两种模式各看一次。

## 4. 结论（2026-10-12）

- F3：不显示序号，`<M-1>`…`<M-0>` 键位删除；跳转用 `]b` / `[b`、`<leader>bp` 拾取和 fzf 的 buffer 列表。
- F4：先按常显实施，使用后改回只在多于一个 buffer 时显示；工作区名随栏出现。
- F6：不显示计数，文件名按最严重的 error / warning 着色；info / hint 不改颜色。
- 每个标签只剩图标、名字、修改标记三样。

## 5. 结果

已按上述实施：`lua/user/specs/ui.lua`（过滤、右侧工作区区、常显、排序、中键、pin 图标、两套高亮）、`lua/user/core/buffers.lua`（替代 buffer 优先同工作区）、`lua/user/core/icons.lua`（`pinned`）；`integration/startup.lua` 新增两标签页两工作区的过滤与标签用例，`ui_themes` 断言两种模式的栏底、当前项与下划线。
