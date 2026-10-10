# standard 与 extra 的边界整理：实施方案

交付对象：代码代理（Codex）。本文是完整的实施说明，按顺序执行即可；每一步都给出改动位置、验收方式和不要做的事。基线为 `b5faaa0`（auto 模式已移除）之后的工作树，工作树里已有本轮未提交的其他改动，不要回退它们。

## 1. 目标与判定规则

三档的定位：

| 档 | 定位 | 做什么 | 不做什么 |
| --- | --- | --- | --- |
| fast | 编辑器 | 编辑、高亮、手动唤起语言能力 | 不自动启动任何进程 |
| standard | 工作区编辑器 | 编辑、导航、检视：在项目里移动、看文件和代码的状态、改代码 | 不执行、不渲染、不自动化、不接管布局、不常驻扫描 |
| extra | IDE | 在 standard 之上加执行、渲染、自动化、停靠布局和常驻装饰层 | 无 |

standard 与 extra 的边界用五个动词判定，功能满足任何一条就归 extra：

1. **执行**：启动或驱动进程来跑代码（调试、测试、任务编排、AI 代理）。
2. **渲染**：把非文本内容画进编辑器（图片、PDF、Markdown 与 Typst 渲染、浏览器预览）。
3. **自动化**：不经用户请求就做事（读取或离开插入模式时的 lint、自动会话、自动拼写、插件自动安装、输入法切换）。
4. **停靠**：接管窗口布局（Edgy、dashboard）。
5. **常驻**：随光标或重绘持续计算的装饰层（matchup、illuminate、缩进线、颜色、TODO、lightbulb、dropbar、scrollview、行内 blame）。

"按需打开、看完即走"的检视和导航工具属于 standard，不管它长得多像 IDE：文件树、标签栏、Peek、Problems 列表、Diffview、终端开关都留在 standard。保存是显式请求，所以保存时的格式化和 lint 属于 standard。

本次改动的结果（其余不动）：

| 功能 | 现状 | 目标 | 依据 |
| --- | --- | --- | --- |
| Outline 符号大纲 | extra | standard | 导航，命令触发，闲置零成本 |
| crates.nvim | extra | standard | Cargo.toml 的检视与补全，属于语言能力 |
| 词典 `<leader>k` | extra | standard | 按需检视；缺 sqlite3 或词库时沿用现有提示 |
| scratch `<leader>.` | extra | standard | 编辑功能 |
| lint 在保存时运行 | extra | standard | 保存是显式请求；顺带补上 standard 的 SQL 没有诊断的缺口 |
| 诊断显示 | standard 只画下划线和标记 | standard 行尾短消息，extra 当前行展开 | 检视归 standard；展开消息是常驻重排 |
| gitsigns 行内 blame | standard 默认开 | standard 默认关，`<leader>ghB` 可开；extra 默认开 | 常驻层 |

fast 不动，extra 不减。性能预期：移入的项目都按键或命令触发，不进热路径；唯一热路径变化是 blame 默认关。

## 2. 改动清单

### 2.1 `lua/user/core/mode.lua`

在 `optional_capabilities` 里新增三项，放在字母序合适的位置并写注释：

```lua
"diagnostics_text", -- trailing virtual text for the diagnostic on each line
"lint_on_write", -- standalone linter runs after a save (BufWritePost only)
"workspace_tools", -- on-request inspection: Outline, crates.nvim, dictionary, scratch
```

把 `decorations` 的注释改为 `-- matchup, illuminate, indent lines, colours, TODO, line blame`。

`standard` 白名单新增 `"diagnostics_text"`、`"lint_on_write"`、`"workspace_tools"`。extra 自动获得全部能力；`diagnostics_expanded` 优先于 `diagnostics_text`，见 2.5。

### 2.2 `lua/user/specs/navigation.lua`

第 136 行 `if profile.extra then`（outline.nvim 所在块）改为 `if require("user.core.mode").capabilities().workspace_tools then`。模块顶部已有 `local panels`、`local float_style`，按文件习惯取 `mode`。其余 `profile.extra` 不动。

### 2.3 `lua/user/specs/languages.lua`

第 124 行 crates.nvim 所在的 `if profile.extra then` 改为按 `workspace_tools` 判断。crates 依赖 Blink，standard 有 Blink。第 64、103、197、226、277 行的 `profile.extra`（Rust 调试键位和适配器、markview、markdown-preview、vimtex 等）不动。

### 2.4 `lua/user/specs/ui.lua`

- 第 245 行 `scratch = { enabled = profile.extra == true }` 改为按 `workspace_tools`。
- 第 277 行起的 `keys`：`<leader>.`（scratch）在 `workspace_tools` 时提供，`<leader>z` 始终提供。现有写法是 `profile.extra and {两项} or {一项}`，改成按 capability 组装列表。
- 第 161（dropbar）、190（dashboard）、336（scrollview）的 `profile.extra` 不动。

### 2.5 `lua/user/core/diagnostics.lua`

第 50 行：

```lua
local mode = capabilities.diagnostics_expanded and "lines" or (capabilities.diagnostics_text and "text") or "off"
```

`<leader>ud` 的循环顺序 `lines -> text -> off` 不变。文件顶部注释补一句：standard 从 `text` 开始，extra 从 `lines` 开始，fast 从 `off` 开始。

### 2.6 `lua/user/specs/lint.lua`

- 第 3 行旁增加 `local on_write = require("user.core.mode").capabilities().lint_on_write`。
- 第 7 行 `ft = automatic and {...} or nil` 改为 `ft = (automatic or on_write) and {...} or nil`，文件类型列表不变。
- 第 341 行起的自动命令块：`BufWritePost` 在 `automatic or on_write` 时注册（含现有的配置文件名重置逻辑），`BufReadPost` 和 `InsertLeave` 只在 `automatic` 时注册。
- 第 396 行加载时的 `schedule_lint(current, false, 400)` 保持只在 `automatic` 时执行。
- 手动 `:Lint` 和 `<leader>cl` 不变。

### 2.7 `lua/user/plugins/git.lua`

第 115 行 `current_line_blame = true` 改为 `current_line_blame = require("user.core.mode").capabilities().decorations`。`<leader>ghB` 的切换键保留。

### 2.8 `lua/user/core/keymaps.lua`

第 35 到 43 行拆开：`<leader>k` 的两个映射放到 `if capabilities.workspace_tools then` 下；`<leader>mo`（PdfOpen）留在 `if capabilities.extended_workflows then` 下。

### 2.9 `lua/user/core/autocmds.lua`、`lua/user/core/commands.lua`、`lua/user/health.lua`

核对 `user.core.dict` 没有被 `extended_workflows` 门控的其他入口；目前 `health.lua` 不检查词典依赖，不需要新增。PDF 相关的门控保持 `extended_workflows`。

## 3. 检查与验收

### 3.1 `scripts/checks/standard.lua`

- 能力断言：补 `cap.workspace_tools and cap.lint_on_write and cap.diagnostics_text`。
- 必有插件列表（第 21 到 38 行）加入 `"outline.nvim"`、`"crates.nvim"`；必无列表（第 40 到 65 行）删除这两项。
- 诊断断言（约第 76 行）：`diagnostic.underline and diagnostic.signs and diagnostic.virtual_text and not diagnostic.virtual_lines`。
- Snacks 断言（约第 72 到 78 行）：`snacks.scratch.enabled` 为 true，`snacks.dashboard.enabled` 仍为 false，`snacks.input.enabled` 为 true；现有循环断言 `mapping.lhs ~= " ."`（scratch 键不存在）改为断言该映射存在。
- lint 断言（约第 100 到 125 行）：`user_lint` 组里 `BufWritePost` 存在，`BufReadPost` 与 `InsertLeave` 不存在；打开 SQL buffer 后 `calls == 0` 的断言保留。把 `toolchain.executable` 的 sqruff 替身提前到 `vim.cmd.edit` 之前装上，然后在现有 `vim.cmd.Lint()` 之前增加一步：对该 SQL buffer 执行 `vim.cmd.write()`，用 `vim.wait` 等到 `calls == 1`（上限 1 秒，保存触发一次 sqruff，经过 150 ms 去抖），再执行 `:Lint` 并断言 `calls == 2`；替身在 `:Lint` 之后再恢复。
- blame 断言：打开文件后 `require("gitsigns.config").config.current_line_blame == false`。
- 末尾的 `Standard evidence` 打印语句补上 "workspace tools present; lint on write"。

### 3.2 `scripts/checks/mode.lua`

- fast 的 `evidence` 表（约第 433 行，能力名到证据插件的映射，每项同时断言该能力在 fast 被报告为禁用、extra 提供该插件、fast 不导入该插件）加入 `workspace_tools = "outline.nvim"` 和 `lint_on_write = "nvim-lint"`。`diagnostics_text` 没有对应插件，在该循环之后单独断言 `vim.tbl_contains(fast.disabled, "diagnostics_text")`。
- fast 不得保留的映射列表（约第 834 行起，搜索 `for a feature it does not load`）已含 `<Leader>k`；加入 `<Leader>.` 和 `<Leader>o`。
- extra 的 `#legacy.disabled == 0` 与 `#explicit_extra.disabled == 0` 自然成立，不需改。

### 3.3 运行顺序

```sh
./scripts/check.sh static
./scripts/check.sh standard mode
./scripts/check.sh integration lifecycle ui_runtime languages
./scripts/check.sh
```

全部通过后，记录 `standard` 组打印的 `Asset evidence: fast N, standard N, extra N`，用它更新文档里的插件数（预计 standard 从 47 变为 50：outline.nvim、outline-treesitter-provider.nvim、crates.nvim）。

### 3.4 性能确认

```sh
python3 scripts/benchmark-mode.py --output /tmp/nvim-std-boundary --target standard --sample lua \
  --file ~/Projects/transformer/transformer.py --runs 3 --startup-cache warm \
  --typing-chars 30 --saves 2 --wheel-bursts 2 --paging-events 6 --keep-going
```

对照 `docs/reference-highlight-requests.md` 里同日的 standard 数字（Lua 输入 p95 5.01、transformer.py 输入 p95 3.93、滚轮 p95 9.50 ms）。三轮 30 字符分辨不了 1 到 2 ms，只要求没有成倍退化；首次打开允许多出 outline 和 crates 两个 spec 的注册开销。输出目录必须短，原因见该文档的复跑说明。

## 4. 文档同步

- `docs/editor-modes.md`：
  - 在"功能取舍"表前加一段，写入第 1 节的定位表和五条判定规则。
  - 第 12 行诊断显示：standard 改为"下划线、标记和行尾短消息"，extra 保持"当前行展开消息"。
  - 第 14 行独立 lint：standard 改为"保存时自动运行，`<leader>cl` / `:Lint` 手动"；extra 改为"另在读取和离开插入模式时运行"。
  - 第 16 行 Git：standard 补"行内 blame 默认关，`<leader>ghB` 开"。
  - 第 19 行常用界面：Outline 和 scratch 从 extra 列移到 standard 列。
  - 第 25 行：词典从 extra 移到 standard，自动拼写和输入法保留在 extra。
  - 第 31 行插件数按 3.3 的实测更新。
  - "语言能力与手动工作流"一节里"SQL 的 Sqruff 是唯一诊断来源，因此 standard 的 SQL 诊断需要手动触发"改为"保存时自动检查"。
- `docs/deployment.md` 第 30 行插件数同步。
- `README.md`：搜索 "extra 提供"、"standard" 的功能描述段落，把 Outline、scratch、词典、保存时 lint 的归属改正；"Git 行 blame 默认启用，可用 `<leader>ghB` 切换"改为按档说明。
- `docs/fast-mode.md` 不需要改。

## 5. 第二阶段（可选，单独提交）

按五个动词把 `extended_workflows` 拆成 `run`（DAP、neotest、overseer、AI、Java/Rust 的调试与测试）、`render`（image、PDF、markview、markdown-preview、typst-preview、live-preview、VimTeX）、`automation`（`lint_auto` 更名 `lint_live`、`session_auto`、`spell_auto`、`plugin_manager_auto`、IME）、`docking`（Edgy、dashboard）。涉及 `health.lua` 第 25 和 200 行、`keymaps.lua` 第 261 行、`commands.lua` 的 PDF 命令、`autocmds.lua` 的 PDF 注册、`specs/java.lua`、`specs/ui.lua` 的 PDF 状态栏、`specs/languages.lua`、`plugins/edgy.lua`、`scripts/checks/mode.lua` 与 `standard.lua` 里对能力名的断言，以及 `docs/editor-modes.md`。只有第一阶段全部通过并提交后再做；做完同样跑整套 `./scripts/check.sh`。

## 6. 约束

- 不新增插件、不改 `lazy-lock.json`；outline.nvim、outline-treesitter-provider.nvim、crates.nvim 都已在锁文件中。不要运行 `:Lazy sync/update`。
- 不提交 `preferences.json`。
- 每个阶段一次提交，提交说明为单行 `type: subject`（例如 `refactor: move on-request inspection tools into standard`），不要加 Co-Authored-By 或 Generated-with 之类的尾注。
- Lua 用 stylua 格式化，selene 不得报错；`./scripts/check.sh static` 会检查。
- 修改检查脚本时只改与本方案有关的断言，不放宽其他断言。
- 遇到与本文不一致的现状（行号漂移、函数改名），以代码为准，按本文的意图调整，并在提交说明之外的最终汇报里指出。
