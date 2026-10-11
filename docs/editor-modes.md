# 三档运行模式

2026-10-10 实现。没有环境覆盖和主机偏好时，默认使用 `standard`；`extra` 保留原完整模式的功能，`fast` 面向服务器及轻量编辑。模式决定插件和自动工作的范围，主题、透明开关、大文件阈值及鼠标输入协议保持原有设置。

三档按编辑工作的职责划分：

| 档 | 定位 | 做什么 | 不做什么 |
| --- | --- | --- | --- |
| fast | 编辑器 | 编辑、高亮、手动唤起语言能力 | 不自动启动任何进程 |
| standard | 工作区编辑器 | 编辑、导航、检视：在项目里移动、看文件和代码的状态、改代码 | 不执行、不渲染、不自动化、不接管布局、不常驻扫描 |
| extra | IDE | 在 standard 之上加执行、渲染、自动化、停靠布局和常驻装饰层 | 无 |

standard 与 extra 的边界用五个动词判定，功能满足任何一条就归 extra：

1. **执行**：启动或驱动进程来跑代码，包括调试、测试、任务编排和 AI 代理。
2. **渲染**：把非文本内容画进编辑器，包括图片、PDF、Markdown 与 Typst 渲染和浏览器预览。
3. **自动化**：不经用户请求就做事，包括读取或离开插入模式时的 lint、自动会话、自动拼写、插件自动安装和输入法切换。
4. **停靠**：接管窗口布局，包括 Edgy 和 dashboard。
5. **常驻**：随光标或重绘持续计算的装饰层，包括 matchup、illuminate、缩进线、颜色、TODO、lightbulb、dropbar、scrollview 和行内 blame。

“按需打开、看完即走”的检视和导航工具属于 standard：文件树、标签栏、Peek、Problems 列表、Diffview 和终端开关都保留。保存是显式请求，所以保存时的格式化和 lint 也属于 standard。

能力名按职责拆分为 `run`（DAP、Neotest、Overseer、AI，以及 Java/Rust 的调试与测试）、`render`（图片、PDF、文档和浏览器预览、VimTeX）、`automation`（自动工作流与输入法切换）、`docking`（Edgy 和 dashboard）。四项均只在 extra 开启，fast 和 standard 关闭；本次拆分只调整命名，三档行为不变。自动工作流保留 `session_auto`、`spell_auto`、`plugin_manager_auto` 等细项，读取和离开插入模式时的 lint 使用 `lint_live`，保存时的 lint 仍使用 `lint_on_write`。

## 功能取舍

| 功能 | fast | standard | extra |
| --- | --- | --- | --- |
| 主题、Tree-sitter 高亮、基础编辑、leader 菜单 | 保留 | 保留 | 保留 |
| 自动补全、片段、Blink 签名 | 原生手动补全 | 保留 | 保留 |
| 主要 LSP | 手动启动 | 自动启动 | 自动启动 |
| 诊断显示 | 手动启动的服务显示标记和下划线 | 下划线、标记和行尾短消息 | 当前行展开消息；basedpyright 与 vtsls 在项目规模门槛内分析整个工作区 |
| 格式化 | 手动 | 保存时格式化 | 保存时格式化 |
| 独立 lint | `:Lint` / `<leader>cl` 手动 | 保存时自动运行，`<leader>cl` / `:Lint` 手动 | 另在读取和离开插入模式时运行 |
| 文件浏览与搜索 | 精简 Oil / fzf，无默认预览 | Oil、Neo-tree、fzf 预览 | 保留全部 |
| Git | 原生终端操作、fzf 按需查询 | Gitsigns、Lazygit、Diffview；行内 blame 默认关，`<leader>ghB` 开 | 保留全部，行内 blame 默认开 |
| 折叠与代码查看 | 手动折叠 | UFO、Glance、Trouble、bqf | 另有 codelens 与默认开启的 inlay hints |
| 编辑工具 | mini 基础编辑、Flash、Tree-sitter 文本对象 | surround、align、move、文本对象、Flash、多光标、grug-far、undotree、neogen | 保留全部 |
| 常用界面 | 共用 lualine 样式，ASCII 标记 | bufferline、lualine、sticky context、通知、Outline、scratch | 另有 dropbar、scrollview、Edgy、dashboard |
| 键盘滚动动画 | 关闭 | 保留 | 保留 |
| 终端 | 原生 `:terminal` 开关 | ToggleTerm | ToggleTerm、Overseer 任务编排 |
| 会话 | 不自动保存 | 手动保存和恢复 | 原有自动保存和手动恢复 |
| swap / 持久 undo | 保留 swap；undo 可选 | 保留 | 保留 |
| matchup、引用高亮、缩进线、颜色预览、TODO、lightbulb | 关闭 | 关闭 | 保留 |
| 词典 | 关闭 | `<leader>k` 按需检视 | 保留 |
| 自动拼写、输入法 | 关闭 | 关闭 | 保留 |
| DAP、Neotest、AI、图片/PDF、文档渲染与浏览器预览 | 关闭 | 关闭 | 保留 |
| 自动下载缺失插件、配置变更检测 | 关闭 | 关闭 | 保留原行为 |

标准模式的白名单还包括 ts-comments、Tree-sitter 文本对象、lazydev 和 crates.nvim 的 Cargo.toml 检视与补全；不启用 faster.nvim 的事件屏蔽。扩展功能不会留下触发加载的快捷键、自动事件或后台定时器。三个模式复用配置工厂，standard 不先执行 extra 模块再过滤。

以默认 VS Code 主题计算，选中的锁定插件数为 fast **13**、standard **50**、extra **83**，包含依赖及 headless 下条件禁用但仍需准备的插件。fast 选择内置 `default` 主题时为 12 个。standard/extra 保留完整 43 个 parser，fast 默认为 13 个，可显式追加。

## 切换与兼容

- `<leader>umf` 选择 fast，`<leader>ums` 选择 standard，`<leader>ume` 选择 extra；直接执行，不打开模式选择弹窗。也可执行 `:EditorMode fast|standard|extra`。
- 选择写入 `preferences.json` 的 `runtime.mode`，随后通过原生重启应用。
- 兼容命令 `:FastModeToggle`：standard 或 extra → fast，fast → standard；`:FastMode off` 明确选择 standard，`on` 选择 fast。
- `NVIM_MODE` 优先于主机偏好，其次才是默认 standard，与 SSH 环境无关。auto 已移除，旧 `runtime.mode=auto` 按 standard 读取，不在启动时改写偏好文件；下一次显式选择模式时持久更新。`NVIM_MODE=auto` 按非法环境覆盖处理，提示后回退到主机偏好。
- 旧的 `full` 在环境变量、偏好、命令及部署参数中都是 extra 的别名。已有 `runtime.mode=full` 不会自动改写，继续获得完整功能；显式 `:EditorMode full` 保存为 extra。
- `:ModeInfo` 显示实际模式、选择来源、保存值、关闭功能、资源降级与恢复数据位置。

重启保留文件、标签页、分屏和光标；按新模式重新初始化选项和插件。未保存修改通过原生确认处理，正在运行的终端任务需另行确认，默认取消。取消时当前会话不变，模式选择仍已保存；再次执行目标 `:EditorMode` 可重试。headless 只保存并提示手动重启。普通 `<leader>R` 保留本次启动的环境覆盖，模式切换则让新进程使用刚保存的选择。

```sh
NVIM_MODE=standard nvim path/to/file.py
NVIM_MODE=extra nvim path/to/file.py
NVIM_MODE=fast nvim path/to/file.py
```

## 语言能力与手动工作流

项目级视图在三档都有，但走显式请求：`<leader>cS` 在附着了能回答 `workspace/symbol` 的服务时发起实时查询（vtsls、basedpyright、clangd 对空查询几乎不返回结果，所以不用静态列表），没有这样的服务时用 ripgrep 按文件类型的定义模式列出全项目的定义再模糊过滤，没有模式的文件类型退回普通 grep。`:ProjectCheck` / `<leader>cC` 按项目标记选择 ruff、tsc、cargo check、go vet 或 selene 之一运行一次，结果进 quickfix（有 Trouble 时打开 Trouble），多个适用时按当前文件类型选择或弹出选择；工具没装时提示，不自动安装。

extra 另把 basedpyright 和 vtsls 切到工作区分析模式，服务会为没有打开的文件报诊断，Trouble 的 workspace 视图和 lualine 的 `ws` 计数因此覆盖整个项目。门槛由 `preferences.json` 的 `runtime.workspace_diagnostics_max_files`（默认 1500）控制，源码文件数超过时留在 open-files 模式，`:checkhealth user` 的 Running language servers 一节说明每个服务的决定。standard 和 fast 不开启。两处实现细节：basedpyright 在工作区模式下由客户端收回拉取式诊断能力，因为宣告了该能力的客户端只会按请求收到诊断，而 Neovim 只按文档拉取、没有工作区级拉取，未打开的文件会永远收不到；vtsls 的项目诊断会连 TypeScript 自带的 lib 文件一起报，客户端只保留项目根内且不在 `node_modules` 下的文件，用户打开过的文件除外。

standard 保留主要语言服务和必要协作：Python 使用 basedpyright + Ruff，Vue 使用 vtsls + vue_ls。Biome 需要向上找到 `biome.json` / `biome.jsonc`；Tailwind 需要 `tailwind.config.*` 或项目 `package.json` 中的 Tailwind 依赖，覆盖无需传统配置文件的 v4 项目。仅有 `.git` 的普通 Web 项目不会启动这些附加服务。

typos-lsp 和 Emmet 不自动启用，可执行 `:ManualLspStart typos_lsp` 或 `:ManualLspStart emmet_language_server`。`:ManualLspStart [server]` / `:ManualLspStop` 在三档中都可用，`FastLspStart/Stop` 是兼容入口。手动生命周期只释放自己管理的附着，不停止自动集成拥有的客户端；也不会覆盖 Java/Rust 配置。

standard 的 Java/Rust 保留原有分析能力，Java 不加载调试/测试 bundles 或对应映射，Rust 不配置 DAP；fast 的 Rust 才使用关闭保存检查、构建脚本和过程宏的精简设置。打开语言服务仍会带来同步、索引和分析成本，standard 不承诺达到无 LSP 的 fast 速度。

standard 默认绘制诊断下划线、标记和行尾短消息，`<leader>cd` 查看完整消息，`<leader>cD` 查看位置列表，`<leader>ud` 仍能循环展开行、行尾文字和关闭消息。extra 默认展开当前行消息。保存时格式化保留原有 800 ms 默认预算及开关。

standard 的独立检查在保存时自动运行，也可通过 `<leader>cl` / `:Lint` 手动启动；读取和离开插入模式不会触发检查，extra 另在这两个时机自动运行。**SQL 的 Sqruff 是唯一诊断来源，standard 保存时自动检查**；sql-language-server 继续提供补全等能力。Selene、Stylelint 和 golangci-lint 仍需项目配置。

首次使用陌生项目的 `node_modules/.bin` 工具时，通过 Neovim 原生信任提示查看项目根的 `package.json`；确认后执行 `:ProjectTrust allow`，再重试工具。未允许时回退到 Mason/系统工具，无头运行不弹窗。信任以仓库根为范围，没有仓库时使用工作区根；`:ProjectTrust deny` 拒绝，`remove` 清除持久记录及解析缓存，`status` 仅显示本会话状态（`unasked`、`allowed`、`denied`、`bypassed`），不会触发确认。`NVIM_TRUST_PROJECTS=1` 或 `vim.g.user_trust_projects = true` 可显式旁路；检查与基准使用该环境开关。本阶段不限制项目 `.venv` 解释器。

standard 会话键位为 `<leader>sw` / `:SessionSave` 保存，`<leader>ss` 恢复当前工作区，`<leader>sS` 选择，`<leader>sl` 恢复最近会话。extra 另保留退出自动保存及 `<leader>sd` 停止自动保存；两档共用原有会话格式和未保存文件保护。

## 显式入口规则

extra 的每一个自动行为，在 standard 和 fast 里都有一个显式入口；降档只失去"自动"，不失去功能。`scripts/checks/standard.lua` 和 `mode.lua` 断言这些入口存在。

| extra 的自动行为 | standard / fast 的显式入口 |
| --- | --- |
| 读取与离开插入模式时 lint | `:Lint` / `<leader>cl`；standard 另在保存时自动 |
| 工作区诊断 | `:ProjectCheck` / `<leader>cC` |
| 退出时自动保存会话 | `:SessionSave` / `<leader>sw`（fast 用原生 `:mksession`） |
| 自动启动的语言服务 | `:ManualLspStart`（fast）；standard 本身自动 |
| codelens 常驻刷新 | `<leader>cL` 按需显示，再按一次执行 |
| inlay hints 默认开 | `<leader>uh` |
| 当前行展开诊断消息 | `<leader>cd` 浮窗，`<leader>ud` 切换样式 |
| TODO 高亮 | `<leader>ft` 全项目搜索关键字 |
| 引用高亮 | `gr` / `<leader>cpr` |
| 配对提示 | 原生 `%` |
| 自动拼写 | `:set spell` |
| 插件自动安装与变更检测 | `NVIM_MODE=extra nvim +Lazy` |

dropbar、scrollview 这类纯显示层没有孪生入口，它们本来就不代表一个动作。渲染类功能（图片、PDF、预览）是功能而非自动行为，不在规则范围内。

## 会话内安静

档位决定导入哪些插件，需要重启；已导入的常驻层此刻跑不跑是会话决定。`:Quiet` / `<leader>uq` 通过各插件自己的公开接口暂停 matchup、illuminate、缩进线、颜色预览、TODO 高亮、lightbulb、scrollview、行内 blame、codelens、inlay hints，并把当前行展开的诊断降为行尾短消息；再执行一次按原状态逐项恢复，用户此前自己关掉的层不会被动。`:ModeInfo` 的 quiet 行和 lualine 的 QUIET 标记显示状态。standard 是结构上安静（根本不加载这些层），extra 是可以安静。

## 外部修改审阅

干净 buffer 在磁盘文件变化后自动重载，重载前的内容会保留最近 20 次（每个最多 20000 行）。`:ExternalChanges` / `<leader>ge` 选择一次重载，左右分屏对比重载前后，`q` 关闭，`R` 把重载前的内容放回 buffer 作为未保存修改。有未保存修改的 buffer 不会被重载，也不会进入列表；它们用 `<leader>gD` 看磁盘差异。重载由 FileChangedShell 处理函数决定，`autoread` 保持关闭：开启时 Neovim 会在触发该事件前就重载干净 buffer，重载前的内容无从保留。

## 部署、缓存与维护

```sh
./scripts/deploy.sh --dry-run --editor-mode standard --profile python
./scripts/deploy.sh --editor-mode extra --profile full
./scripts/deploy.sh --editor-mode fast --parsers rust --profile native
```

`--editor-mode` 默认 standard。`--profile` 始终独立选择 Mason 工具：`--profile full` 仍安装全部工具，即使当前运行模式用不到其中的调试适配器。standard/extra 默认工具组为 minimal，fast 未指定工具组时不安装语言工具。详见[部署文档](deployment.md)。

standard 和 fast 普通启动不下载、不更新插件。新机器先部署或显式准备资源；缺失资源会在 `:ModeInfo` 报告，没有 Lazy/Oil 时仍可使用原生入口。会修改插件资产或锁文件的 `:Lazy` 操作统一在 `NVIM_MODE=extra nvim +Lazy` 下执行，避免将其他模式的共享插件误判为多余。

三档共用插件目录和完整锁文件。切换不卸载插件、不删除旧缓存、swap 或 undo；减少的是后续计算和新增功能缓存。Lua 编译缓存、必要 Tree-sitter 状态及恢复数据继续保留。语法高亮承诺针对原主题和 Tree-sitter 层；fast 没有自动 LSP 时也没有该服务提供的语义着色。

## 验收

`./scripts/check.sh` 显式准备验证完整 extra 功能，并加入 standard 行为组；CI 使用 extra 准备完整依赖。仅验收 standard 安装可运行 `./scripts/check.sh standard`，只要求其选中插件。覆盖模式优先级、旧 full 兼容、持久化和取消重启、插件/映射隔离、保存与手动 lint、手动会话、Java/Rust 定义保护、部署一致性及现有界面行为。

五轮交错测量及限制见[三档性能测量](editor-mode-measurements.md)。fast 的服务器细节见[快速模式文档](fast-mode.md)。性能数据反映功能取舍，不能将 PTY 内重绘耗时等同于真实 kitty 绘制、触控板驱动或 SSH 网络延迟。
