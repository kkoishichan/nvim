# 语言工作流与验收入口

真实工具验证使用临时样例项目与隔离状态。普通回归和真实工作流分层运行，缺少真实组所需依赖会失败，不会跳过后宣称通过。

| 范围 | 验证与记录 | 检查入口 |
| --- | --- | --- |
| Python、JavaScript、TypeScript、Vue | [语言服务、项目规则、测试、源码与浏览器断点](workflow-python-js.md) | `./scripts/check.sh workflow_python_js` |
| C、C++、Go、Rust | [编译数据库、正反例测试、语言服务与断点](workflow-native.md) | `./scripts/check.sh workflow_native` |
| Java、TeX、Typst、PDF | [JDK、测试插件兼容性、正反例、断点与构建](workflow-java-docs.md) | `./scripts/check.sh workflow_java_docs` |
| Shell、Lua、配置文件 | ShellCheck 磁盘/source 语义、Ruff 项目规则、配置驱动检查；原集成与语言回归 | `./scripts/check.sh integration languages` |
| 构建任务、保存、汇编 | 实际 Overseer 失败位置/重跑；格式化超时、异步保存期间的新编辑；GNU/Go 汇编区分 | `./scripts/check.sh workflow_actions` |

完整入口为 `./scripts/check-workflows.sh`，具体的 Python/Node/Java 样例依赖须先按各组文档准备。检查阶段不安装依赖；编译器、语言服务和调试器使用当前解析到的真实工具，来源可用 `:checkhealth user` 确认。

普通保存格式化默认 800 ms，TeX 使用保存后异步格式化，手动 `<leader>cf` 可运行较慢任务。本轮无头测量用 `silent write` 排除消息展示等待：首次保存钩子约 5.5 ms，故意慢格式化在约 819 ms 超时返回，TeX 保存约 5.3 ms 返回；异步期间的新编辑与已保存文件均未被过时输出覆盖。此记录证明保存调度和超时边界，不代表所有真实项目的格式化耗时。

`:TaskBuild`、`:TaskRun`、`:TaskTest` 自动发现常见项目入口，并保留输出、归属和失败位置。它们使用当前包目录；显式选择了另一个无关工作区时使用所选工作区。CMake 首次配置到 `build/`，之后执行构建；复杂编译参数仍由项目自身的构建配置定义。

调试验证需要允许绑定本机端口及调试样例子进程。AI 回归只使用替身传输，绝不通过真实服务发送样例内容。真实编译和调试协议检查不能替代所有终端、操作系统、SSH 或图片协议的人工体验验收；窗口与会话验证单独记录。
