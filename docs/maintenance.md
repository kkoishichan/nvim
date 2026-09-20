# 升级、验证与恢复

把一次可用配置视为一组版本：本仓库提交、同一提交的 `lazy-lock.json`、该锁定 Treesitter 插件的 parser 源码修订、Neovim 版本，以及实际启用的语言工具。只恢复一个 Lua 文件或插件锁不足以还原整个环境。

## 检查分层

| 层 | 入口 | 证明范围 |
| --- | --- | --- |
| 快速检查 | `./scripts/check.sh` | 静态、配置互操作、性能边界、项目、AI 替身、工具选择、终端归属、任务、生命周期、窗口、会话、主题及部署故障 |
| 单组定位 | `./scripts/check.sh --help` | 列出当前全部组；指定组仍先核对依赖，静态和部署脚本组除外 |
| 真实语言 | `./scripts/check-workflows.sh` | 真实 LSP、格式化、通过与失败测试、实际调试断点，需要矩阵中列出的 SDK 和样例依赖 |
| 真实终端 | `python3 scripts/ui-smoke.py` | 三个 PTY 尺寸的键盘、模式与实际补全菜单；保存日志，不连接真实 SSH 主机 |
| 启动比较 | `python3 scripts/benchmark.py` | 保留输入、逐次启动日志、版本信息与 JSON，默认丢弃首次并取其余中位数 |
| 模式比较 | `python3 scripts/benchmark-mode.py` | PTY 中比较完整模式、快速模式与原生 Neovim 的启动、输入、保存、滚轮和翻页延迟，以及空闲客户端、定时器、监听、子进程、内存和新增状态文件 |
| 测量安全检查 | `python3 scripts/check-benchmark-mode.py` | 验证输入文件副本隔离、保存内容有效，以及缺少输入或重绘时拒绝生成成功结果；需要 Python msgpack |

模式比较的每轮输入和保存都在独立临时副本上完成，`--file` 不会改写原文件。
`--keep-going` 在单项采样失败后继续其余样本，但最终仍返回失败状态并保留失败证据。
`--runs 2 --startup-cache both --file /path/to/code.py --fast-lsp-sample diagnostics`
可同时测冷/热编译缓存、真实代码和首次手动语言服务。生成的 Rust 样例带独立 Cargo 清单；
真实文件仅复制自身，不复制整个项目。基准禁止 npm/Cargo 联网，避免后台下载干扰结果。
指标定义、固定版本数据和尚未覆盖的远程环境见[运行模式实测](fast-mode-measurements.md)。

原集成入口 `scripts/check.lua` 仅负责顺序运行 `scripts/checks/integration/` 下的主题模块；保持同进程插件加载互操作验证。其它行为组分别运行于独立进程，避免上一组的替身或缓存污染下一组。主题检查关注实际文字可读性；原集成中大量逐项复制调色常量的断言已移除。

检查不下载缺失依赖。第一次先按 [CI 验证](ci-validation.md) 的准备步骤建立环境，随后单独执行检查。CI 缓存命中仍核对插件提交及修改状态、parser 修订与可加载性、检查工具收据、Blink 本地二进制；不能把缓存存在当成验证通过。

## 日常升级

1. 保存编辑内容，检查 `git status`，提交或另行保存个人修改，记录升级前的 `git rev-parse HEAD`。偏好、会话和工具数据不在 Git 中，需要时另备份。
2. 在独立分支或副本上修改插件锁和相关配置。插件、Neovim 与工具升级分开进行，便于定位。
3. 显式准备匹配的依赖，再运行快速检查。改动 Blink、PDF、项目或终端时必须通过相应行为组；改动语言工具还需运行对应真实工作流。
4. 核对 `:checkhealth user` 的实际工具路径、来源、版本及项目根，使用日常项目验证后提交配置和锁文件。

插件与 parser 的版本来源始终是完整的 `lazy-lock.json`。快速模式只是少装一部分资产，不是清理依据：它不提供会按当前子集执行 `clean/sync/update` 的入口，`:Lazy` 会提示管理操作在完整模式下运行。升级插件锁时请在完整模式下操作，再按需要用 `--editor-mode fast` 重新部署服务器。

`lua/user/toolchain.lua` 中的版本是期望值；Mason 包目录中的 `mason-receipt.json` 记录安装来源，工具的版本输出才反映实际执行程序。项目本地工具或系统 PATH 可以优先于 Mason，修改 pin 不会自动替换正在运行的 LSP。显式恢复工具后使用 `:ToolsRefresh`，并重启受影响的客户端或 Neovim。

## 恢复已知可用组合

有未提交修改时先保存它们。要检查旧版本，可从记录的提交创建独立 Git worktree，再在新的临时依赖环境中准备和验证；这样不会影响当前工作的配置与工具数据。

直接恢复当前检出时，在干净工作树执行 `git switch --detach <已知可用提交>`，然后 `:Lazy restore`；从该版本的配置执行 `:TSUpdate`，确认 parser 与锁定 Treesitter 插件一致。需要恢复语言工具时显式使用该版本的 `:MasonToolsInstall`，再运行受影响组和健康检查。不要只按插件管理器窗口已经关闭来判断恢复成功。

部署脚本保留的 release 和 backup 路径、失败后的配置状态以及符号链接恢复方式见 [部署说明](deployment.md)。这些备份只涵盖配置；共享插件目录、Mason 包、SDK、会话与词典需分别处理。不要在仍有 Neovim 进程使用旧目录时删除它。

## 本轮验收位置

完整六阶段记录见 [实施记录](improvement-progress.md)。本轮默认 Neovim 为 0.12.5，CI 固定官方 Tree-sitter CLI 0.26.9；本地语言样例、真实 PTY 和独立依赖环境分别记录证据。远端 CI 只有在提交到远端并实际运行后才有结果，当前本地记录不将其算作已运行。
