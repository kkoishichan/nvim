# C / C++ / Go / Rust 工作流验证

验证日期：2026-09-05。检查使用完整 Neovim 配置、当前锁定插件与本机已安装工具；每轮把样例复制到独立临时目录，退出时清理。没有安装依赖或请求外部 AI 服务。

| 语言 | 构建与测试证据 | 编辑与调试证据 |
| --- | --- | --- |
| C、C++ | CMake Debug 构建，`compile_commands.json` 包含两个编译单元；CTest 成功及故意失败；每种语言注入编译错误后构建失败，恢复后构建成功 | clangd 将调用跳转到正确源文件和定义行，报告新增错误；codelldb 分别命中两个程序的指定断点，核对实际栈帧文件和行号 |
| Go | `go test` 成功及故意失败；生成带调试信息的二进制；实际 Neotest 适配器报告成功及失败 | gopls 定义跳转及类型错误诊断；Delve 命中指定断点并核对栈帧 |
| Rust | 离线 Cargo test 成功及故意失败；Clippy 无警告成功，注入恒等运算后按预期失败；实际 Rust Neotest 适配器报告成功及失败 | rust-analyzer 定义跳转及类型错误诊断；codelldb 命中指定断点并核对栈帧 |

在配置目录运行 `./scripts/check.sh workflow_native`，或运行 `./scripts/check-workflows.sh` 验证全部真实语言工作流。缺少编译器、语言服务器或适配器会使检查失败，不会跳过后报成功。普通 `./scripts/check.sh` 不运行这些较重的检查。

本轮环境包括 GCC 16.2.1、Go 1.27.0、Rust/Cargo 1.95.0、gopls 0.22.0、Delve 1.27.0 与 rust-analyzer 0.3.2904。codelldb 使用当前 Mason 安装版本；检查调用配置中登记的实际适配器。

样例没有第三方 Go 模块或 Rust crate，Go 模块下载和 Cargo 网络访问均禁用，Go 缓存单独隔离。临时 Go 项目设置 `GOFLAGS=-buildvcs=false`，防止宿主仓库信息影响样例构建。Rust 检查等待实际定义请求可用；服务器完成初始化不代表 Cargo 工作区已载入。

调试器需要绑定本机端口并调试本轮创建的子进程。在禁止这些能力的沙盒中，调试检查会明确失败；本轮在允许本地调试的执行环境通过。codelldb 检查配置使用 `target.disable-aslr false`，避免受限宿主禁止修改地址随机化策略；这是样例运行设置，不修改日常调试配置。无头检查暂时关闭 DAP UI 自动弹窗，仅验证真实调试协议、断点事件与栈帧，不替代交互界面的视觉验收。

样例位于 `scripts/fixtures/native/`，驱动位于 `scripts/checks/workflow_native.lua` 和 `scripts/workflows/native.lua`。本轮确认现有 Rust 配置可完成这些操作，因此未为通过样例而改变 `plugins/lang.lua`。
