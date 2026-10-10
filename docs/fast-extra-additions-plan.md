# fast 与 extra 的补充：实施方案

交付对象：代码代理（Codex）。前置：`docs/standard-boundary-plan.md` 第一阶段已提交（`89e6744`），三档定位与五条判定规则以 `docs/editor-modes.md` 为准。本文分三个阶段，每阶段独立提交，按顺序执行；每阶段末尾列出必须通过的检查。

定位回顾：fast 是零后台进程的编辑器，standard 是工作区编辑器，extra 是 IDE。本文给 fast 补"不启动进程也能有的编辑能力"，给 extra 补标准 IDE 功能和一道项目信任门槛。

## 阶段 A：fast

全部按键或命令触发，不新增任何自动启动的进程、定时器或监听。fast 的插件从 9 个变为 12 个。

### A1 Tree-sitter 文本对象进入共享层

- 把 `lua/user/plugins/treesitter.lua` 里 `nvim-treesitter-textobjects` 的 spec 整体移到 `lua/user/specs/treesitter.lua` 的工厂返回值中（保持 `branch = "main"`、`keys` 懒加载和现有 `config`），`plugins/treesitter.lua` 改为只 `return require("user.specs.treesitter")()`。
- `lua/user/specs/editing.lua`：`setup_modules(not fast)` 改为 `setup_modules(true)`，并删除第 24 到 26 行解释 fast 没有这些查询的注释；`c`、`f`、`o` 三个 Tree-sitter 文本对象在三档都可用。

### A2 Flash 进入共享层

- 把 `lua/user/specs/navigation.lua` 里 `folke/flash.nvim` 的 spec 抽成新工厂 `lua/user/specs/flash.lua`（返回单元素列表，键位与现在完全一致），`navigation.lua` 改为 `vim.list_extend(plugins, require("user.specs.flash")())`。
- `lua/user/specs/init.lua` 的 `factories` 列表在 `user.specs.editing` 之后加入 `{ "user.specs.flash" }`。

### A3 手动 `:Lint` 进入 fast

- `lua/user/core/mode.lua`：`resolve()` 里增加 fast 白名单，与 `standard` 表同样写法，内容只有 `lint = true`；`values[capability]` 的计算改为 `name == "extra" or (name == "standard" and standard[capability] == true) or (name == "fast" and fast[capability] == true)`。`lint` 的注释已是 "standalone linter available on request"，不改。
- `lua/user/specs/init.lua` 的 `factories` 末尾加入 `{ "user.specs.lint" }`。该工厂在 `lint_auto` 和 `lint_on_write` 都为 false 时只注册 `cmd = "Lint"` 和 `<leader>cl`，正好是 fast 需要的。
- `lua/user/specs/lint.lua` 的 `manual_lint`：当 `configured_linters` 返回空列表时，用 `vim.notify` 说明当前文件类型没有可用的 linter（区分"未配置"和"可执行文件缺失"两种原因，后者提示 `:MasonToolsInstall` 或系统安装），不要静默返回。只在手动入口提示，自动路径保持静默。

### A4 手动启动语言服务后的补全与诊断

`lua/user/core/fast_lsp.lua` 第 139 到 146 行是受管附着的登记点。在同一处，对新登记的 `(client, bufnr)`：

- 诊断：取 `vim.lsp.diagnostic.get_namespace(client.id)`，对该命名空间调用 `vim.diagnostic.config({ underline = true, signs = { text = { E/W/I/H } } }, namespace)`，文字与 `lua/user/core/diagnostics.lua` 里的一致。只影响用户自己启动的服务，`capabilities.diagnostics_live` 不变。`:ManualLspStop` 释放客户端时不需要撤销，命名空间随客户端消失。
- 补全：`omnifunc` 由 Neovim 在附着时自动设置，`<C-x><C-o>` 已可用，不要再设。新增主机偏好 `runtime.manual_lsp_autocomplete`（`lua/user/core/preferences.lua` 的 `defaults.runtime` 加 `manual_lsp_autocomplete = false`），为 true 且客户端支持 `textDocument/completion` 时调用 `vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })`。
- 以上两点都要在 `not require("user.core.mode").capabilities().completion` 时才执行，避免在 standard/extra 里与 Blink 重复。

### A5 fzf 的 Git 入口在三档可用

`lua/user/specs/picker.lua` 末尾按 `capabilities.git` 过滤 `<leader>g` 键位的逻辑删除。`<leader>gs` 和 `<leader>gc` 只在按键时运行一次 `git`，符合 fast 的定位；fzf-lua 在非仓库目录会自行报错。

### A6 原生终端开关

`lua/user/core/keymaps.lua`：当 `not capabilities.terminal_manager` 时，映射 `<leader>tt`、`<C-/>` 和 `<C-_>` 到一个原生开关：当前标签页里若有本开关打开的终端窗口则关闭它（只关窗口，保留 buffer 与进程）；否则 `botright 12split`，有存活的终端 buffer 就显示它，没有则 `terminal`。实现放在 `lua/user/core/native.lua` 新增的 `toggle_terminal()`，用 `vim.b[buf].user_native_terminal = true` 标记自己的 buffer。`<Esc><Esc>` 离开终端模式已有。

### A7 原生状态栏显示服务与诊断

`lua/user/core/statusline_basic.lua`：`value()` 在位置之前增加一段 `%{%v:lua.vim._user_statusline_status()%}`，函数返回当前 buffer 附着的客户端名（逗号分隔）加上 `vim.diagnostic.count(0)` 的 E/W 计数，没有客户端时返回空串。保持一次 Lua 调用，不缓存，不加定时器。

### A8 检查、文档与计数

- `scripts/checks/mode.lua`：
  - fast 期望导入的插件列表（搜索 `The fast plugin set is missing`）加入 `nvim-treesitter-textobjects`、`flash.nvim`、`nvim-lint`。
  - `evidence` 表删除 `lint = "nvim-lint"` 这一项；在其后单独断言 `not vim.tbl_contains(fast.disabled, "lint")`。
  - 第 10 节的映射列表保持不变；另断言 fast 存在 `<Leader>tt`、`<Leader>cl`、`<Leader>gs` 和 `s`（Flash）映射。
  - 空闲句柄断言（搜索 `handles running while idle`）必须继续通过：新插件都按键加载。
  - 新增一个 fast 场景：`:ManualLspStart lua_ls` 附着后，该客户端命名空间的 `vim.diagnostic.config(nil, ns).underline == true`，而全局 `vim.diagnostic.config().underline == false`；现有的手动服务场景（搜索 `manual_lsp_smoke` 或 `FastLspStart`）可以复用。
- `scripts/checks/standard.lua`：A1 和 A2 把两个插件移入共享工厂后，确认必有列表里的插件仍全部存在；无需新增断言。
- 文档：`docs/fast-mode.md` 第 123 行的基础安装列表加入三个插件并把"共 9 个插件"改为 12（`default` 主题时 11）；`docs/editor-modes.md` 第 50 行的 fast 计数同步，"功能取舍"表里 fast 列的"独立 lint"改为"`:Lint` 手动"，"编辑工具"加 Flash 和 Tree-sitter 文本对象，"终端"改为"原生 `:terminal` 开关"，"诊断显示"改为"手动启动的服务显示标记和下划线"；`docs/deployment.md` 第 30 行计数同步；`README.md` 运行模式段落同步。
- 用 `./scripts/check.sh mode` 打印的 `fast imports N plugins` 回填上述数字。

阶段 A 检查：

```sh
./scripts/check.sh static mode standard integration lifecycle startup_loading offline_assets deployment
```

性能确认：`python3 scripts/benchmark-mode.py --output /tmp/nvim-fast-add --target fast --sample lua --runs 3 --startup-cache warm --typing-chars 30 --saves 2 --wheel-bursts 2 --paging-events 6`，空闲客户端、定时器、监听必须仍为 0，首次打开允许多出三个 spec 的注册时间。

## 阶段 B：extra 的 IDE 功能

### B1 codelens

- `lua/user/core/mode.lua` 新增能力 `"codelens", -- inline LSP code lenses, refreshed as the buffer changes`，只有 extra 拥有。
- `lua/user/specs/auto_lsp.lua` 的 `LspAttach` 回调：当 `capabilities.codelens` 且 `client_supports(client, "textDocument/codeLens", bufnr)` 且 `require("user.core.buffer_policy").allow(bufnr)` 时调用 `vim.lsp.codelens.enable(true, { bufnr = bufnr })`（本机 Neovim 0.12.5 提供该函数，不要再写自动命令刷新）。新增映射 `<leader>cL` 执行 `vim.lsp.codelens.run`，并在 `which_key.lua` 的分组里不需要新组。
- `lua/user/core/buffer_policy.lua` 的 `apply()`：文档变为高成本时，对该 buffer 调用 `vim.lsp.codelens.enable(false, { bufnr = bufnr })`；`restore()` 不需要重新打开，LspAttach 重放会处理。

### B2 inlay hints 默认开启

- 新增能力 `"inlay_hints_auto", -- inlay hints on attach`，只有 extra 拥有。
- `auto_lsp.lua` 的 `LspAttach`：当该能力为真且客户端支持 `textDocument/inlayHint` 时 `vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })`；现有 `<leader>uh` 切换保留。`buffer_policy.apply()` 同样关闭该 buffer 的 inlay hints。

### B3 Edgy 停靠测试面板

`lua/user/plugins/edgy.lua`：`left` 在 Outline 之后加入 `{ title = "Tests", ft = "neotest-summary", size = { height = 0.3 } }`，`bottom` 在 Task Output 之后加入 `{ title = "Test Output", ft = "neotest-output-panel", size = { height = dock_size("bottom") } }`。`lua/user/core/panels.lua` 与 `window_roles.lua` 已认识这两个文件类型，不改。`lua/user/core/autocmds.lua` 的 `panel_filetypes` 加入这两项。

### B4 检查与文档

- `scripts/checks/standard.lua`："Standard enabled extra capabilities" 的断言加入 `not cap.codelens and not cap.inlay_hints_auto`。
- `scripts/checks/mode.lua` 的 `evidence` 表不需要新项（两个能力没有专属插件）；在 `diagnostics_text` 的单独断言旁补 `codelens` 和 `inlay_hints_auto` 在 fast 被报告为禁用。
- `scripts/checks/windows.lua` 或 `layout_session.lua` 里若有枚举 Edgy 停靠项的断言，加入两个测试面板；没有则不加。
- `docs/editor-modes.md` 的表：extra 列的"折叠与代码查看"加 codelens 与 inlay hints 默认开；README 的 extra 描述同步。

阶段 B 检查：

```sh
./scripts/check.sh static standard mode integration windows layout_session signature
```

## 阶段 C：项目信任门槛

目的：standard 和 extra 会自动执行项目目录里的 `node_modules/.bin` 可执行文件（保存时的 prettier、biome、stylelint、markdownlint-cli2，打开时的 tailwindcss 和 biome 语言服务）。对首次打开的陌生仓库，这应当先得到用户一次确认。范围只限 `node_modules/.bin`；项目 `.venv` 的解释器用于分析和调试目标，不在本阶段处理。

### C1 `lua/user/core/trust.lua`

- `M.allows(root)`：返回该项目根是否允许运行项目内可执行文件。顺序：`vim.env.NVIM_TRUST_PROJECTS == "1"` 或 `vim.g.user_trust_projects == true` 时返回 true；本会话缓存命中时返回缓存；`#vim.api.nvim_list_uis() == 0` 时返回 false 且不提示（无头环境永远不弹窗）；否则对 `root .. "/package.json"` 调用 `vim.secure.read`，返回非 nil 视为允许。结果按 root 缓存到会话结束。
- `M.forget(root)` 清掉会话缓存；`M.status(root)` 返回 `"bypassed" | "allowed" | "denied" | "unasked"`，只依据旁路开关和本会话缓存，不触发提示（`vim.secure.trust` 只有 allow、deny、remove 三个动作，没有查询接口；要查持久状态就读 `vim.fn.stdpath("state") .. "/trust"` 里是否有该路径的记录）。
- 用户命令 `:ProjectTrust allow|deny|remove|status`，分别调用 `vim.secure.trust` 的 `allow`、`deny`、`remove`，路径为当前项目根的 `package.json`，之后 `M.forget(root)` 并 `require("user.toolchain").clear_executable_cache()`。

### C2 接入点

`lua/user/toolchain.lua` 的 `node_resolve`：在返回 `project` 来源的结果之前，调用 `require("user.core.trust").allows(ctx.repository or ctx.root or directory)`；不允许时跳过该目录，继续走 Mason/系统解析，并把 `reason` 写成 `"Project node_modules/.bin skipped: project not trusted"`。缓存键 `cache_key("node", ...)` 必须包含信任状态，否则 `:ProjectTrust allow` 之后仍命中旧结果。

### C3 可观测与检查

- `lua/user/health.lua` 的 "Project context" 段加入一行：当前项目的信任状态。
- `scripts/check.sh` 第 9 行的 `export` 加入 `NVIM_TRUST_PROJECTS=1`；`scripts/benchmark-mode.py` 和 `scripts/benchmark-wheel-pty.py` 的进程环境同样加入，让现有依赖"项目工具优先"的检查与基准不受影响。
- 新增检查组 `trust`（注册到 `scripts/check.sh` 三处列表和 `scripts/run-check.lua`）：临时目录里建一个带 `package.json` 和 `node_modules/.bin/prettier` 的项目；不设置旁路且替换 `vim.secure.read` 为返回 nil 时，`node_resolve("prettier")` 不得返回 `project` 来源；替换为返回字符串时必须返回 `project`；`#vim.api.nvim_list_uis() == 0` 的真实无头环境下不设置旁路也不得调用 `vim.fn.confirm`（替换为 `error`）；`:ProjectTrust remove` 后缓存被清除。该组运行时要显式清掉 `NVIM_TRUST_PROJECTS`，因为 `check.sh` 全局导出了它。
- `docs/editor-modes.md` 的"语言能力与手动工作流"一节和 `README.md` 的依赖说明加一段：陌生项目首次使用项目内工具时的确认流程与 `:ProjectTrust`。

阶段 C 检查：

```sh
./scripts/check.sh static trust toolchain projects languages integration
```

## 约束

- 不新增锁文件条目：三个进入 fast 的插件都已在 `lazy-lock.json`。不要运行 `:Lazy sync/update`。
- 工作树里可能有与本文无关的未提交改动；只 `git add` 本文涉及的文件，不要把无关改动带进提交。
- 每阶段一次提交，单行 `type: subject`，不加 Co-Authored-By 或 Generated-with 尾注。建议：`feat: extend the fast editor with on-request tools`、`feat: add codelens, inlay hints and test panels to extra`、`feat: ask before running project node tools`。
- Lua 经 stylua 格式化，selene 的 `assert` 必须带消息；`./scripts/check.sh static` 覆盖。
- 基准输出目录用 `/tmp` 下的短路径。
- 现状与本文不一致时以代码为准，按意图调整，并在最终汇报里列出偏差。
