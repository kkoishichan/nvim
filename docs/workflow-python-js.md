# Python / JavaScript / TypeScript / Vue 实际工作流验证

2026-09-05 在完整 Neovim 配置、隔离的 `/tmp` 项目上通过。检查使用真实语言服务、格式化器、测试运行器和调试协议，不用模拟工具替代端到端结果。默认快速检查不运行这一组。

## 已验证行为

| 工作流 | 实际验收 |
| --- | --- |
| Python LSP | BasedPyright 返回 `answer()` 的正确源码定义，并诊断未保存的 `int = "wrong"` 类型错误。 |
| JS / TS LSP | vtsls 返回 JS、TS 的正确源码定义；分别诊断未保存的 JS 语法错误、TS 类型错误。 |
| Vue LSP | `vue_ls` 和 vtsls 同时附着，报告 `<script setup lang="ts">` 内的类型错误。 |
| Python 保存 | 真正执行保存，经 Conform / Ruff 读取 `pyproject.toml` 的单引号和 60 列配置并折行。 |
| TypeScript 保存 | 真正执行保存，经 Conform / Prettier 读取项目单引号、无分号和 60 列配置。 |
| pytest | Neotest 运行两个测试；正常模式 2 个成功，故意失败模式 1 个成功、1 个失败。测试内验证 `sys.prefix` 为文件所在项目的 `.venv`，即使 `VIRTUAL_ENV` 指向另一个有效环境。 |
| Jest / Vitest | 分别运行两个测试，验证正常模式全成功和故意失败模式有失败；按 Python → Jest → Vitest → Jest 的顺序切换，断言实际 adapter 归属和最终结果。 |
| Python DAP | debugpy 命中 `main.py` 的源码断点，在停止帧中求值 `sys.prefix`，确认使用项目 `.venv`。debugpy 宿主仍来自独立工具环境。 |
| Node DAP | `pwa-node` 命中 JavaScript 源码断点，在停止帧求值 `value = 42`。 |
| TypeScript sourcemap | 先用项目 TypeScript 编译出 JS / map，然后启动生成的 JS；断点命中原始 `.ts` 文件的正确行并求值 42。 |
| 浏览器 attach | 新建 Chromium 无头进程和临时用户目录，打开本地 fixture；`pwa-chrome` 连接其随机回环端口，命中 `browser.js` 断点并求值 42；完成后关闭进程和整棵 DAP 会话树。 |

Neotest 通过公开 consumer API 观察最终结果，避免把流式结果误当成进程已经结束。调试检查关闭无头进程内的 DAP UI 自动弹窗，保留真实 adapter / 会话 / 断点协议。

## 本轮实际修复

- neotest-python 默认解释器顺序与统一工具策略不一致。现在显式调用工具解析层，让项目 `.venv` 优先于外部 `VIRTUAL_ENV`。
- Neotest 首次启动的解析子进程只记录当时已加载的 adapter。随后延迟加载 Jest 会报 `module 'neotest-jest' not found`。现在首次发现测试时用上游公开的 `subprocess.add_paths_to_rtp` 同步新 adapter，保持按语言延迟加载。
- `nvim-dap-vscode-js` 期待旧版 `vsDebugServer`，与 Mason 的 `dapDebugServer` 协议失配，真实调试报 `adapter.port is required`。现在由 nvim-dap 原生 server adapter 直接连接 js-debug，支持标准子会话请求；移除了旧桥接插件和对应锁条目。
- 已复现短生命周期 TypeScript 程序在源码映射加载前执行结束。默认 JS 调试配置增加 `pauseForSourceMap = true`；项目自定义 `launch.json` 调试编译产物时也应保留这个选项。

## 准备和复跑

基础环境需有 Neovim、Node、npm、Python、venv / pip、Chromium，以及当前配置声明的 BasedPyright、Ruff、vtsls、Vue language server、Prettier、debugpy、js-debug-adapter。缺失依赖会明确失败，不会静默跳过。

依赖准备与检查分离。首次使用一个专门的临时目录；默认只用现有依赖和离线缓存，允许下载时显式加 `--allow-network`：

```sh
scripts/workflows/prepare-python-js.sh /tmp/nvim-python-js-deps --allow-network
NVIM_WORKFLOW_PYTHON_JS_DEPS=/tmp/nvim-python-js-deps ./scripts/check.sh workflow_python_js
```

准备脚本使用已提交的 `package-lock.json` 和 Python 固定版本列表；Python 环境允许复用匹配版本的系统包。后续可省略联网选项离线重建。指定已有 npm 缓存时设置 `NVIM_WORKFLOW_NPM_CACHE`。检查只复制 fixture / Python 环境，并链接已准备的 Node 依赖；不会安装包。

本次实际准备目录为 `/tmp/nvim-python-js-deps.ozequs`。锁文件离线重建成功，最终验证命令全部通过：

```sh
NVIM_WORKFLOW_PYTHON_JS_DEPS=/tmp/nvim-python-js-deps.ozequs \
  ./scripts/check.sh workflow_python_js languages toolchain integration
```

受限 PID / 网络沙箱中 BasedPyright 曾在初始化前退出；同一配置在宿主环境正常完成。真实 DAP 和 Chromium 需要本机回环端口。这里的通过结果来自已经授权的宿主运行，所有源码、浏览器资料和测试输出仍位于临时目录。

## 版本与覆盖边界

本次运行：Neovim 0.12.5、Python 3.14.7、pytest 9.1.0、Node 24.15.0、Jest 30.2.0、Vitest 4.1.8、TypeScript 6.0.3、Vue 3.5.13；BasedPyright 1.39.8、vtsls 0.3.0、Vue language server 3.3.1、Ruff 0.15.15、Prettier 3.8.3、debugpy 1.8.21、js-debug 1.117.0、Chromium 152.0.7977.82。

TypeScript 验证的是本地编译文件和 source map；浏览器验证的是独立本地页面的 attach。尚未把具体应用的 Vite / Webpack 路径重写、容器远程调试、React JSX 转译或项目特有 launch 参数视为已验收。它们需随具体项目补充 `launch.json`；现有 TS / Vue 默认入口仍按项目场景提供 attach。
