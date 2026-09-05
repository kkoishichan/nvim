# 部署、配置组与恢复

默认部署选择 `minimal`，固定使用 Neovim `v0.12.5` 和 tree-sitter CLI `0.26.9`。配置默认取 `main`；需要重现同一次部署时，传入明确的提交 SHA。脚本会输出实际提交，并把仓库、请求引用、提交、Neovim 版本和配置组写入保留的 release 目录下 `deployment.txt`。

```bash
./scripts/deploy.sh --dry-run --ref main --profile python --profile web
./scripts/deploy.sh --ref <commit-sha> --nvim-version v0.12.5 --profile python --profile web
./scripts/deploy.sh --ref <commit-sha> --mason
```

`--dry-run` 只读取平台信息并输出计划，不创建目录、文件或链接，不启动 Neovim，也不安装或下载任何东西。可以在未配置依赖的新机器上先查看计划。实际部署会检查 fzf 至少为 `0.36.0`；系统包版本过旧时明确失败，不将不能工作的搜索配置视作完成。

| 参数 | 行为 |
| --- | --- |
| `--ref REF` | 克隆后单独 fetch 并验证分支、tag 或提交，使用 detached checkout；默认 `main`。 |
| `--nvim-version vX.Y.Z` | 精确匹配版本，最低为 0.12；找不到时从该官方 release 安装到 `~/.local/opt`，不使用 `latest`。 |
| `--profile NAME` | 选择需要恢复的 Mason 工具及相应系统依赖；可重复，工具去重。 |
| `--mason` | 等同 `--profile full`，恢复全部锁定工具。 |
| `--repo URL` / `--ssh` | 更换配置仓库地址或使用预设 SSH 地址。 |
| `--config-dir PATH` | 更换配置目标，默认 `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`；支持空格。 |
| `--no-deps` | 跳过系统包管理器安装；仍检查基本依赖，仍确保精确 Neovim / tree-sitter 版本。 |
| `--no-sync` | 明确推迟插件、parser、Blink 和 Mason 准备；只部署配置，输出中会标记 deferred。 |
| `--with-extras` | 额外安装 lazygit、SQLite、ImageMagick 和 Poppler。 |
| `--dict` | 下载可选 ECDICT 数据库，约 300 MB 压缩包、1.2 GB 解压文件。 |

所有配置组均包含 `minimal`。组只决定这次显式恢复哪些工具，不禁用其他语言配置，也不会卸载已有工具。正常启动与打开文件不会触发 Mason 安装；编辑器中的 `:MasonToolsInstall` 仍表示完整目录恢复。

| 配置组 | Mason 范围 | 额外系统依赖范围 |
| --- | --- | --- |
| `minimal` | Lua language server、StyLua、Selene、Ruff、ShellCheck、shfmt | 基础编译与下载工具、Git、fzf、ripgrep、fd；不要求其他语言 SDK。 |
| `python` | basedpyright、Ruff、debugpy | Node/npm（basedpyright）和 Python/pip；Debian 系包含 Python venv。 |
| `web` | JS/TS/Vue/CSS/HTML/JSON/YAML/Docker/SQL 服务器、Biome、Prettier、Stylelint、JS debug adapter | Node/npm。 |
| `java` | JDTLS、Java debug adapter、Java test bundles | JDK 21+；项目 JDK、Maven、Gradle及 wrapper 由项目选择。 |
| `native` | C/C++、Go、Rust、CMake、汇编、Verilog/TOML 支持及相应格式化、调试工具 | Go、Rust/Cargo、Python/pip、CMake、Ninja；基础 C 编译器已包含。 |
| `docs` | Markdown、Typst、LaTeX 服务器、排版和拼写工具 | Node/npm、Perl、Typst、基础 TeX/latexmk、Poppler、ImageMagick；macOS 使用 BasicTeX。 |
| `full` | `lua/user/toolchain.lua` 中全部固定版本，包括未归入某个语言组的工具 | 上述配置组依赖的合并。 |

所有正常部署都会从锁定的 Tree-sitter 插件目录构建配置中明确启用的 parser，并准备、验证锁定 Blink 补全所需资产。它们不随 Mason 配置组减少。tree-sitter CLI 使用官方 `0.26.9` 平台二进制，不要求为了安装 CLI 再安装 Rust。Neovim 和 tree-sitter 的发行资产来源分别为 [Neovim v0.12.5](https://github.com/neovim/neovim/releases/tag/v0.12.5) 与 [tree-sitter v0.26.9](https://github.com/tree-sitter/tree-sitter/releases/tag/v0.26.9)。改变 Neovim 版本会同时传给准备步骤；其他版本不因默认准备版本硬编码而被拒绝，实际兼容性仍由检查结果决定。

## 切换与失败恢复

部署不会在现有配置上运行 `git pull`。它先在目标父目录创建唯一 `.nvim-release.*` 目录，克隆配置、验证引用，再以独立的 `XDG_CONFIG_HOME/nvim` 链接运行该版本的初始化。这样 Lazy 重设 runtimepath 后，配置与 `after` 目录仍来自 staging，锁文件也来自同一提交。

插件准备会涵盖 headless 下被条件禁用的插件。锁定 checkout 由准备步骤完成，随后通过 Lazy 的公开 build 操作安装 Markdown 预览等显式构建资产，并生成帮助标签；不会再次执行会 fetch 和写锁的 Lazy restore/update。结果同时检查启动错误、Lazy 构建任务和实际 Git HEAD，随后检查 parser revision、可加载性和 Blink 资产；锁文件必须保留原字节。任何这一阶段的失败都不会移动原配置。插件和 Mason 使用正常的共享数据目录；配置恢复不表示回滚这些共享工具和插件文件。

校验成功后，原配置移入唯一 `nvim.backup.<时间>.<随机值>/config`，目标路径通过独占创建的符号链接指向 `.nvim-release.*/config`。不会删除旧 backup 或 release。连续部署形成多个可独立访问的版本；正常的编辑、Git 操作和 Neovim 启动仍可使用原配置路径。

切换前会检测目标是否在准备期间被替换。切换时使用不覆盖已有目标的文件系统操作；如果其他程序在这期间创建了目标目录，部署报告失败并保留它。目标仍为空时，恢复操作会独占创建指向 `backup/config` 的链接；目标已存在时仅报告备份位置，绝不覆盖新目录。

可以先直接试用保留的版本，无需替换当前入口：

```bash
NVIM_APPNAME=nvim XDG_CONFIG_HOME="/path/to/.nvim-release.ABC123/xdg-config" nvim
```

手动恢复前关闭正在使用配置的 Neovim，核对输出中的 backup 路径，并为当前配置另选一个**尚不存在**的保留路径。例如：

```bash
# 两个路径都替换成部署输出中已核对的绝对路径。
# 先检查 current-kept 不存在，不要复用旧保留目录。
test ! -e "/path/to/current-kept" && test ! -L "/path/to/current-kept" || exit 1
mv "/path/to/nvim" "/path/to/current-kept"
ln -s "/path/to/nvim.backup.TIMESTAMP.RANDOM/config" "/path/to/nvim"
```

现有 `preferences.json` 会在验证前复制到 staging，成功升级后保留工具、窗口和格式预算等个人偏好；不会复制任意 Lua 配置。原目录、旧符号链接、未提交的本地配置修改均保留在 backup 中。不要删除仍被当前入口或备份链接引用的 `.nvim-release.*` 目录。改变配置前已有的个人插件/Mason 数据不会被复制进备份；恢复旧配置后，如其工具锁不同，需显式恢复对应锁定工具。

| 退出码 | 结果与后续处理 |
| --- | --- |
| `0` | 已完成请求；使用 `--no-sync` 时是明确推迟安装的配置部署。 |
| `2` | 参数错误，未开始部署。 |
| `10` | 基础依赖或固定运行时失败；通常配置未变。若仅请求的可选系统包失败，配置可能已生效，输出会明确标记。 |
| `20` | 克隆、引用、检查目录或切换失败；原配置仍在原处或已报告的 backup 中。 |
| `21` | 插件/parser/Blink 准备、恢复或锁验证失败；未切换配置。 |
| `30` | 配置已生效，但所选 Mason 工具未全部恢复到固定版本；保留备份，修复网络或依赖后以相同参数重试。 |
| `40` | 配置已生效，可选词典失败。 |

错误分支不会打印 “Deployment complete”。如下载或包管理器失败，查看该步骤日志；不要仅凭已有配置路径判断完整安装成功。JDTLS 的 launcher JDK 与项目运行 JDK 是两种选择，Java 21+ 的部署依赖不意味着强制项目升级。

## 验证范围

```bash
./scripts/check-deploy.sh
./scripts/check.sh static
```

部署检查使用独立 `/tmp` 目录、替身包管理器/Git/外部安装过程和真实 Lua 配置选择逻辑，覆盖五个平台的无副作用计划、含空格路径、clone/ref/prepare/restore/verify 失败、原配置恢复、并发新目录保护、Mason 部分失败、推迟安装及退出码。真实 Lua helper 检查验证安装回调失败和 Lazy 构建失败会让进程失败，而不是只检查文字输出。

Arch、Debian/Ubuntu、Fedora、openSUSE 和 macOS 的包名分支均经过计划测试；没有在这五种系统上逐一实际执行包管理器安装。发行版版本、仓库启用情况、TeX 组件与项目专用 SDK 的可用性仍需目标机确认。某个选定配置组的系统包不存在时，脚本明确失败，可手动准备该平台依赖后使用 `--no-deps`，不会静默报告该功能可用。

本轮另在全新的 Linux x86_64 `/tmp` 配置/数据目录运行了真实 staging 链条：从本地缓存克隆 83 个锁定插件，真实构建并验证 43 个显式 parser（包含 46 个依赖解析器）、准备 Blink、安装 Markdown 预览预编译二进制，最后实际安装 minimal 的 6 个锁定 Mason 包。配置根和 `after` 路径使用 staging 的独立 XDG 配置空间；安装过程没有修改个人全局配置或 Mason 目录。这项验证与五个平台的 shell 替身计划测试分别记录，不把替身结果视为五平台已实装。
