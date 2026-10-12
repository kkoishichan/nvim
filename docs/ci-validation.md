# CI 与隔离依赖验证

阶段 6 将依赖准备和配置检查分为两个入口。检查不会补装插件或工具；依赖缺失、版本不符或损坏时先失败，并提示运行准备入口。GitHub Actions 工作流已经写入仓库，尚未推送触发，因此以下结果均为本机验证，不代表远端 CI 已通过。

## 固定版本与准备范围

CI 使用 Ubuntu 24.04、Neovim 0.12.5、tree-sitter CLI 0.26.9。下载后分别检查官方发布资源的 SHA256；Actions 本身也固定到已核验的提交，而不是浮动标签。

| 项目 | 固定值 / 验证来源 |
| --- | --- |
| Neovim | `v0.12.5`，Linux x86_64 压缩包 SHA256：`bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875`；[官方发布资源](https://github.com/neovim/neovim/releases/expanded_assets/v0.12.5) |
| tree-sitter CLI | `v0.26.9`，Linux x64 压缩包 SHA256：`9ce82137caa65864e7ca8b869fd391cef88c9bd2a01c4371b9c4dd26c2585efb`；[官方发布资源](https://github.com/tree-sitter/tree-sitter/releases/expanded_assets/v0.26.9) |
| checkout | `11bd71901bbe5b1630ceea73d27597364c9af683`，对应 v4.2.2；[官方提交](https://github.com/actions/checkout/commit/11bd71901bbe5b1630ceea73d27597364c9af683) |
| cache | `5a3ec84eff668545956fd18022155c47e93e2684`，对应 v4.2.3；[官方提交](https://github.com/actions/cache/commit/5a3ec84eff668545956fd18022155c47e93e2684) |
| 插件 | `lazy-lock.json` 的 82 个完整 Git SHA，包括当前平台条件禁用的插件 |
| Parser | 锁定的 nvim-treesitter 插件内的源码 revision；43 个显式语言，加 3 个查询依赖，安装过程报告 46 项 |
| 检查工具 | StyLua `v2.5.2`、Selene `0.31.0`、Ruff `0.15.14`、ShellCheck `v0.11.0`，统一取 `user.toolchain` 的版本 |
| 补全二进制 | 锁定 Blink 发布版本对应的原生 Rust 库，核验版本指向的 Git SHA、发布校验文件和实际可加载性 |

锁定的 Tree-sitter 要求 CLI 至少 0.26.1。准备脚本检查该下限，CI 则固定到与本机验证相同的 0.26.9。使用独立的 CLI 可执行文件，不把 npm 包名当成已满足该前置条件。

基础系统还需 `git`、`curl`、`tar`、C 编译器、Python 3、`fzf`、`rg`、`fd`。CI 明确准备这些宿主依赖。这里准备的是核心检查所需的四个工具，不是所有语言服务器、SDK、调试器或插件的可选预览服务。真实语言工作流有各自的准备脚本和锁文件，见其他 workflow 验证文档。

## 本地使用

首次准备允许下载和编译，目标必须是绝对路径：

```sh
NVIM_MODE=extra ./scripts/prepare-checks.sh /tmp/nvim-check-env
source /tmp/nvim-check-env/environment.sh
./scripts/check.sh
```

准备入口设置独立的 config/data/cache/state，并固定 `NVIM_APPNAME=nvim`。生成的环境文件将该环境 Mason 的工具目录放在 PATH 前面。检查入口在第一次行为检查前核验依赖，并给每个组隔离缓存、状态、日志和配置目录；组内不读取机器的 `preferences.json`。单独运行静态检查不要求完整插件安装。

复用可信的本机下载缓存：

```sh
NVIM_MODE=extra ./scripts/prepare-checks.sh /tmp/nvim-check-env \
  --cache-data "$HOME/.local/share/nvim"
```

`--cache-data` 只复用 Git 源码对象、匹配版本的四个工具和匹配提交的 Blink 原生库，不复制旧 parser 二进制；parser 从锁定源码新编译。工具复制到独立目录并重建内部相对链接，不会回写原缓存。

已准备好的目标可以离线复核：

```sh
NVIM_MODE=extra ./scripts/prepare-checks.sh /tmp/nvim-check-env --offline
source /tmp/nvim-check-env/environment.sh
./scripts/check.sh
```

`--offline` 需要目标中已有匹配 parser；它不是把任意旧 parser 缓存迁入新环境的快捷方式。Git 子进程只允许本地文件协议；缓存缺少对象时失败，不能因 partial clone 的惰性取回而隐式访问远端。

检查可单独复核状态：

```sh
source /tmp/nvim-check-env/environment.sh
nvim --headless -u NONE -i NONE -l scripts/verify-lock.lua
```

`verify-lock.lua` 检查配置与锁文件双向对应、插件 HEAD、已跟踪文件是否被修改、目标 parser 二进制存在及可加载、parser revision、四个工具的安装回执与可执行路径、Blink 资产。它显式从目标环境的 parser 路径加载，不能用 Neovim 自带 parser 的回退来掩盖缺失文件。缺少 Lazy 时会先给准备提示，不继续报一串模块加载错误。

部署复用相同 Lua 准备和验证入口。`NVIM_PREPARE_NVIM_VERSION` 可由部署的显式版本参数提供，默认仍为 0.12.5。`NVIM_PREPARE_PARSERS/TOOLS/ASSETS=0` 与相应的 `NVIM_VERIFY_*` 开关供调用者选择准备层；CI 不关闭任何层。配置和 bootstrap 的 lockfile 来自当前配置源码目录，临时 staging 启动不会误读旧配置目录的锁文件。

## 已完成的本机验证

验证日期：2026-09-05。系统实际版本为 Neovim 0.12.5、tree-sitter CLI 0.26.9。

1. 从空的 `/tmp/nvim-check-clean/data` 开始。83 个插件从只读本机 Git 缓存独立克隆，再检出每个锁定提交；43 个显式 parser 及 3 个查询依赖从下载的锁定源码重新构建。四个工具和 Blink 复用匹配缓存，随后完整依赖核验成功。此项证明独立 data 环境可运行，未声称插件源码全部通过远端重新下载。
2. 最终在该环境运行默认 `./scripts/check.sh`，全部 18 组通过：静态检查、16 个行为组（integration、performance、ai、languages、projects、project_actions、toolchain、terminals、workflow_actions、signature、lifecycle、pdf_lifecycle、windows、layout_session、ui_themes、offline_assets）以及 deployment。独立行为组使用完整配置启动；保存超时、失败任务等 fixture 的预期报错不代表检查失败。
3. 对同一已准备环境运行 `--offline`，依赖准备与核验再次通过。`offline_assets` 阻止外部下载调用，确认实际选中并执行了原生 Rust 匹配器；没有将 Blink 切换到 Lua 实现，也没有改写发布版本文件。
4. 在临时依赖目录逐项制造故障并恢复：条件禁用的 image.nvim 缺失、插件 HEAD 错误、插件已跟踪源码被改动、目标 Lua parser 缺失、parser revision 错误、Ruff 回执版本错误、Blink 校验文件错误。每一项均返回非零并给出对应诊断；恢复后全量核验通过。目标 Lua parser 缺失测试确认不会被 Neovim 自带 parser 掩盖。
5. 在额外临时目录验证 Lazy bootstrap：从指定 staging 锁文件取 SHA；无效锁定 SHA 在离线模式明确失败并清理临时 clone；`NVIM_CHECK_ONLY=1` 且缺少 Lazy 时不创建安装目录，只提示先准备。

6. 另建 `/tmp/nvim-check-download`，只复用插件 Git 源码；四个工具从空 Mason 目录真实安装，Blink 发布二进制真实下载。准备和后续插件/工具/资产核验均成功，四个实际 `--version` 输出分别为 2.5.2、0.31.0、0.15.14、0.11.0。该环境未重复编译 parser，故单独核验时显式关闭 parser 层；完整 parser 证据来自第一环境。

2026-09-20 新增第 19 组 `mode`，覆盖模式选择优先级、能力隔离、按需语言服务、原生入口、只读状态与配置目录、精简资产选择和离线准备。该组在本机通过，不属于上面 2026-09-05 那次记录；上文的「18 组」保持当时的实际结果。

CI 缓存键包含宿主平台、架构、Neovim 和 CLI 版本、插件锁、parser 清单、工具目录以及准备/核验代码。缓存命中后仍完整核验，不能替代通过证据。插件的未跟踪构建产物允许存在，但已跟踪源码改动会导致失败。

随后实际下载了 CI 指定的两个官方 Linux 压缩包，SHA256 均与表中一致，按 CI 目录布局解压后版本命令均退出 0。再使用该官方 Neovim 0.12.5 与独立依赖环境运行最终默认 **18 组**，全部通过。资源记录为 `/tmp/nvim-ci-assets-on507o/results.json`，完整检查日志为同目录 `check.log`。这进一步覆盖了本机发行版 Neovim 与官方发布构建的差异，仍不等同于在 GitHub 的 Ubuntu runner 上执行。

## 2026-10-10 三档模式回归

新增 standard 行为组：验证插件与快捷键隔离、手动 lint/会话、辅助 LSP、Java/Rust 配置保护及部署集合一致。检查入口显式运行 extra 功能组和 standard 组；CI 在 extra 模式下准备完整插件，以免默认 standard 的子集缺少回归所需功能。检查工具清单补充 Lua language server 和 typos-lsp，用于真实手动 LSP 生命周期；上文的四项清单和历史组数保留原记录。新结果只代表本机验收，未推送或声称远端 CI 已运行。

本机默认 **31 组**回归全部通过；最终手动 LSP 保护与检查依赖调整后，`static integration standard mode deployment` 再次通过。基准脚本的三项 Python 检查通过，覆盖样本副本隔离、独立 Git 项目边界和缺少重绘时拒绝成功结果。五轮交错测量另行执行，数据及其边界见[三档性能测量](editor-mode-measurements.md)。

交付前再次运行 `static standard deployment` 和基准脚本三项检查，均通过。最终测量包含 120 个有效会话、每档每样本五轮；Rust/Markdown 的 standard/extra 以最终配置另行补测，前后 104 份运行源码哈希一致，其他样本保留原记录。

## 2026-10-12 无输入法宿主回归

[CI 运行 38186330263](https://github.com/kkoishichan/nvim/actions/runs/38186330263) 在 `mode` 组失败：测试把 extra 模式允许输入法自动切换，误认为所有宿主都会启用 `fcitx.nvim`。该插件原本就只在 `fcitx5-remote` 或 `fcitx-remote` 可用时启用；Ubuntu runner 不提供这些命令。

模式检查改用独立 PATH 和可执行 fixture，分别验证两个受支持命令及命令缺失时的行为，并验证 fast / standard 即使有输入法命令也不启用自动切换。运行时配置保持不变。

本机 `static mode` 通过；另外下载并核对 CI 固定的官方 Neovim 0.12.5 压缩包，在不含 fcitx 命令的 PATH 下运行默认 `./scripts/check.sh`，全部 **38 组**通过。插件、parser 和检查工具复用本机已核验的锁定依赖；这项本机结果不代替 Ubuntu runner 的远端结果。
