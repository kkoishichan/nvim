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
| 插件 | `lazy-lock.json` 的 83 个完整 Git SHA，包括当前平台条件禁用的插件 |
| Parser | 锁定的 nvim-treesitter 插件内的源码 revision；43 个显式语言，加 3 个查询依赖，安装过程报告 46 项 |
| 检查工具 | StyLua `v2.5.2`、Selene `0.31.0`、Ruff `0.15.14`、ShellCheck `v0.11.0`，统一取 `user.toolchain` 的版本 |
| 补全二进制 | 锁定 Blink 发布版本对应的原生 Rust 库，核验版本指向的 Git SHA、发布校验文件和实际可加载性 |

锁定的 Tree-sitter 要求 CLI 至少 0.26.1。准备脚本检查该下限，CI 则固定到与本机验证相同的 0.26.9。使用独立的 CLI 可执行文件，不把 npm 包名当成已满足该前置条件。

基础系统还需 `git`、`curl`、`tar`、C 编译器、Python 3、`fzf`、`rg`、`fd`。CI 明确准备这些宿主依赖。这里准备的是核心检查所需的四个工具，不是所有语言服务器、SDK、调试器或插件的可选预览服务。真实语言工作流有各自的准备脚本和锁文件，见其他 workflow 验证文档。

## 本地使用

首次准备允许下载和编译，目标必须是绝对路径：

```sh
./scripts/prepare-checks.sh /tmp/nvim-check-env
source /tmp/nvim-check-env/environment.sh
./scripts/check.sh
```

准备入口设置独立的 config/data/cache/state，并固定 `NVIM_APPNAME=nvim`。生成的环境文件将该环境 Mason 的工具目录放在 PATH 前面。检查入口在第一次行为检查前核验依赖，并给每个组隔离缓存、状态、日志和配置目录；组内不读取机器的 `preferences.json`。单独运行静态检查不要求完整插件安装。

复用可信的本机下载缓存：

```sh
./scripts/prepare-checks.sh /tmp/nvim-check-env \
  --cache-data "$HOME/.local/share/nvim"
```

`--cache-data` 只复用 Git 源码对象、匹配版本的四个工具和匹配提交的 Blink 原生库，不复制旧 parser 二进制；parser 从锁定源码新编译。工具复制到独立目录并重建内部相对链接，不会回写原缓存。

已准备好的目标可以离线复核：

```sh
./scripts/prepare-checks.sh /tmp/nvim-check-env --offline
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

CI 缓存键包含宿主平台、架构、Neovim 和 CLI 版本、插件锁、parser 清单、工具目录以及准备/核验代码。缓存命中后仍完整核验，不能替代通过证据。插件的未跟踪构建产物允许存在，但已跟踪源码改动会导致失败。

随后实际下载了 CI 指定的两个官方 Linux 压缩包，SHA256 均与表中一致，按 CI 目录布局解压后版本命令均退出 0。再使用该官方 Neovim 0.12.5 与独立依赖环境运行最终默认 **18 组**，全部通过。资源记录为 `/tmp/nvim-ci-assets-on507o/results.json`，完整检查日志为同目录 `check.log`。这进一步覆盖了本机发行版 Neovim 与官方发布构建的差异，仍不等同于在 GitHub 的 Ubuntu runner 上执行。
