# 全面提升实施记录

执行分支：`codex/comprehensive-improvements`。基线：`bbf8a69`。
路线和原始审计见 `improvement-roadmap.md`；每阶段验证后独立提交。

| 阶段 | 状态 | 验证 |
| --- | --- | --- |
| 1. 性能边界与工作流修复 | 完成 | 静态、原集成、performance、ai、languages 组通过 |
| 2. 项目与工具上下文 | 完成 | 全部 9 组检查通过；真实 health 烟雾通过 |
| 3. 语言完整工作流 | 待实施 | — |
| 4. 模块与资源生命周期 | 待实施 | — |
| 5. 窗口与会话交互 | 待实施 | — |
| 6. 部署、CI 与维护 | 待实施 | — |

## 阶段一

- F01/F02：读取前的有界成本检查与编辑范围增量检查；保留 filetype 和撤销；共享颜色、补全、格式化、lint、折叠、Treesitter 准入。LSP 根发现与初始化均检查目标 buffer，已附加服务只脱离目标文件。隐藏文件恢复时补回窗口折叠设置。
- F03：五个平台补齐 fzf，并验证最低版本。
- F04/F05：Codex 使用当前精确选区；Claude 使用当前文件/行范围引用。Claude 中断通过公开终端接口发送单次 Escape，不关闭 IDE 服务。依据：[Claude Code 官方快捷键](https://code.claude.com/docs/en/interactive-mode)。测试使用替身传输，没有真实外发。
- F06–F09：Jest/Vitest 按项目识别并提供 `:TestAdapter jest|vitest|auto`；JDTLS 明确使用已验证 JDK；ShellCheck 清除未保存文件旧磁盘诊断并保留 source 语义；Ruff 遵循项目规则。
- 独立检查入口：`./scripts/check.sh [--group] static|integration|performance|ai|languages`，不指定时运行全部。

复测方法与路线图一致，每场景四次，取后三次中位数：空启动 51.5 ms；两行 Lua 152.1 ms；30,012 字节单行 JSON **156.4 ms**（原 6282.8 ms）。这是本机无头启动结果，真实终端延迟留在后续阶段验证。

行为回归包含稀疏长行、粘贴与恢复、隐藏文件折叠恢复、共享 LSP 两文档、延迟 initialize 前变成长行且不发送 didOpen、AI 首次/连续/反向/块/Unicode 选择、JS A→B→A 与 monorepo、Java 21/17 交叉、ShellCheck 编辑/保存/source、Ruff 88/120 项目规则。

## 阶段二

- 共享工作区、语言项目、仓库与实际 cwd；显式选择只影响当前 tab。嵌套仓库不继承外层语言环境，worktree、符号链接和 `..` 保持真实路径含义。
- 搜索与任务使用共享工作区；任务保留模板包级目录，重跑仅限当前工作区；延迟输入捕获操作发起时的项目。
- 普通终端、Codex 和 OpenCode 按项目管理进程。OpenCode 使用独立回环端口，校验实际服务目录，并在异步握手中防止串项目。Claude 保留原生单终端集成，绑定首个项目，阻止从其他项目误发。
- 工具解析返回路径、来源和原因；Node 项目工具优先，Python 目标解释器与 debugpy 宿主独立，Java 选择可追溯。缓存包含环境、根目录和偏好，支持安装事件与 `:ToolsRefresh`。
- `:checkhealth user` 显示来源、版本、缺项及当前 LSP；`preferences.json` 提供经过类型校验的机器偏好。

验证覆盖项目 A/B、多 tab、嵌套仓库、Mason 安装/卸载、PATH 和偏好变化、失效 LSP 命令、终端异常退出、异步换项目取消与精确目标通道。全套 static、integration、performance、ai、languages、projects、project_actions、toolchain、terminals 通过；真实健康检查通过。AI 外发全程使用替身。
