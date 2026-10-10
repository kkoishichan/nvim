# 三档运行模式

2026-10-10 实现。没有环境覆盖和主机偏好时，默认使用 `standard`；`extra` 保留原完整模式的功能，`fast` 面向服务器及轻量编辑。模式决定插件和自动工作的范围，主题、透明开关、弹窗样式、大文件阈值及鼠标输入协议保持原有设置。

## 功能取舍

| 功能 | fast | standard | extra |
| --- | --- | --- | --- |
| 主题、Tree-sitter 高亮、基础编辑、leader 菜单 | 保留 | 保留 | 保留 |
| 自动补全、片段、Blink 签名 | 原生手动补全 | 保留 | 保留 |
| 主要 LSP | 手动启动 | 自动启动 | 自动启动 |
| 诊断显示 | 默认手动查看 | 下划线和标记；消息按需查看 | 原有当前行展开消息 |
| 格式化 | 手动 | 保存时格式化 | 保存时格式化 |
| 独立 lint | 不加载 | `<leader>cl` / `:Lint` 手动 | 原有自动检查，也可手动 |
| 文件浏览与搜索 | 精简 Oil / fzf，无默认预览 | Oil、Neo-tree、fzf 预览 | 保留全部 |
| Git | 原生终端操作 | Gitsigns、Lazygit、Diffview | 保留全部 |
| 折叠与代码查看 | 手动折叠 | UFO、Glance、Trouble、bqf | 保留全部 |
| 编辑工具 | mini 基础编辑 | surround、align、move、文本对象、Flash、多光标、grug-far、undotree、neogen | 保留全部 |
| 常用界面 | 原生状态栏 | bufferline、lualine、sticky context、通知 | 另有 dropbar、scrollview、Outline、Edgy、dashboard、scratch |
| 键盘滚动动画 | 关闭 | 保留 | 保留 |
| 终端 | 原生 `:terminal` | ToggleTerm | ToggleTerm、Overseer 任务编排 |
| 会话 | 不自动保存 | 手动保存和恢复 | 原有自动保存和手动恢复 |
| swap / 持久 undo | 保留 swap；undo 可选 | 保留 | 保留 |
| matchup、引用高亮、缩进线、颜色预览、TODO、lightbulb | 关闭 | 关闭 | 保留 |
| 自动拼写、输入法、词典 | 关闭 | 关闭 | 保留 |
| DAP、Neotest、AI、图片/PDF、文档渲染与浏览器预览 | 关闭 | 关闭 | 保留 |
| 自动下载缺失插件、配置变更检测 | 关闭 | 关闭 | 保留原行为 |

标准模式的白名单还包括 ts-comments、Tree-sitter 文本对象和 lazydev；不启用 faster.nvim 的事件屏蔽。扩展功能不会留下触发加载的快捷键、自动事件或后台定时器。三个模式复用配置工厂，standard 不先执行 extra 模块再过滤。

以默认 VS Code 主题计算，选中的锁定插件数为 fast **9**、standard **47**、extra **83**，包含依赖及 headless 下条件禁用但仍需准备的插件。fast 选择内置 `default` 主题时为 8 个。standard/extra 保留完整 43 个 parser，fast 默认为 13 个，可显式追加。

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

standard 保留主要语言服务和必要协作：Python 使用 basedpyright + Ruff，Vue 使用 vtsls + vue_ls。Biome 需要向上找到 `biome.json` / `biome.jsonc`；Tailwind 需要 `tailwind.config.*` 或项目 `package.json` 中的 Tailwind 依赖，覆盖无需传统配置文件的 v4 项目。仅有 `.git` 的普通 Web 项目不会启动这些附加服务。

typos-lsp 和 Emmet 不自动启用，可执行 `:ManualLspStart typos_lsp` 或 `:ManualLspStart emmet_language_server`。`:ManualLspStart [server]` / `:ManualLspStop` 在三档中都可用，`FastLspStart/Stop` 是兼容入口。手动生命周期只释放自己管理的附着，不停止自动集成拥有的客户端；也不会覆盖 Java/Rust 配置。

standard 的 Java/Rust 保留原有分析能力，Java 不加载调试/测试 bundles 或对应映射，Rust 不配置 DAP；fast 的 Rust 才使用关闭保存检查、构建脚本和过程宏的精简设置。打开语言服务仍会带来同步、索引和分析成本，standard 不承诺达到无 LSP 的 fast 速度。

standard 默认只绘制诊断下划线和标记，`<leader>cd` 查看消息，`<leader>cD` 查看位置列表，`<leader>ud` 仍能循环展开行、行尾文字和关闭消息。保存时格式化保留原有 800 ms 默认预算及开关。

独立检查仅通过 `<leader>cl` / `:Lint` 启动，第一次使用后仍不会变为自动检查。**SQL 的 Sqruff 是唯一诊断来源，因此 standard 的 SQL 诊断需要手动触发**；sql-language-server 继续提供补全等能力。Selene、Stylelint 和 golangci-lint 仍需项目配置。

standard 会话键位为 `<leader>sw` / `:SessionSave` 保存，`<leader>ss` 恢复当前工作区，`<leader>sS` 选择，`<leader>sl` 恢复最近会话。extra 另保留退出自动保存及 `<leader>sd` 停止自动保存；两档共用原有会话格式和未保存文件保护。

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

`./scripts/check.sh` 显式准备验证完整 extra 功能，并加入 standard 行为组；CI 使用 extra 准备完整依赖。仅验收 standard 安装可运行 `./scripts/check.sh standard`，只要求其选中插件。覆盖模式优先级、旧 full 兼容、持久化和取消重启、插件/映射隔离、手动 lint/会话、Java/Rust 定义保护、部署一致性及现有界面行为。

五轮交错测量及限制见[三档性能测量](editor-mode-measurements.md)。fast 的服务器细节见[快速模式文档](fast-mode.md)。性能数据反映功能取舍，不能将 PTY 内重绘耗时等同于真实 kitty 绘制、触控板驱动或 SSH 网络延迟。
