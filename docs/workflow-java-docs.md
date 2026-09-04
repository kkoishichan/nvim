# Java 与文档工作流验证

验证日期：2026-09-05。检查使用真实编译器、JDTLS、测试扩展和调试适配器；没有伪造测试结果、语言服务响应或断点事件。

## 运行方式

先准备固定版本的 Maven 测试依赖，下载和编译缓存写入指定目录：

```sh
./scripts/workflows/prepare-java-docs.sh /tmp/nvim-java-workflow-deps
```

随后执行实际工作流检查；该步骤以 Maven 离线模式运行，不负责安装依赖：

```sh
NVIM_JAVA_WORKFLOW_DEPS=/tmp/nvim-java-workflow-deps \
  ./scripts/check.sh workflow_java_docs
```

需要 JDK 21 以上、Maven、Gradle、已安装的 JDTLS/java-test/java-debug-adapter，以及 `typst`、`latexmk`、`pdflatex`、`pdfinfo`、`pdftoppm`。调试和测试结果通道需要允许本机回环连接。缺少必要依赖会失败，不会静默跳过。

样例来自 `scripts/fixtures/java-docs/`，每次复制到临时目录。JDTLS 索引、Java 用户目录、Gradle 缓存、PDF、辅助文件和 Neovim 状态均隔离；Mason 二进制只读使用。检查在清理临时目录前等待 JDTLS 进程真正退出。

## 已验证结果

| 流程 | 实际证据 |
| --- | --- |
| Maven 与项目 JDK 设置 | Maven 编译主代码及两种测试框架；class 文件主版本为 61，即 Java 17。JDTLS 在 JDK 25 上启动，实际返回项目 compliance `17`。这验证运行语言服务的 JDK 与项目编译级别可以分离。 |
| Gradle | 本机 Gradle 9.7.1 离线编译 Java 样例，生成真实 class 文件。Maven/Gradle 根发现、嵌套仓库边界和符号链接索引归一有检查。 |
| Java 编辑反馈 | JDTLS 初始化完成，返回文档符号；方法调用跳到同文件正确定义；未保存的类型错误产生诊断，恢复内容后诊断清除。 |
| JUnit | 通过编辑器使用的 `jdtls.test_nearest_method` 与真实调试适配器执行两个测试；分别核验一个成功和一个断言失败。 |
| TestNG | 同样运行真实成功及失败测试；核验测试标记和失败诊断。 |
| Java 调试 | JDTLS 发现 main 配置，调试适配器启动程序；收到 `breakpoint` 停止事件并核验源代码第 5 行，继续后收到正常结束事件。 |
| Typst | `:TypstCompilePdf` 生成有效 PDF；改为两页后，已经打开的 PDF buffer 通过文件监听更新页数。前后真实 `pdftoppm` 渲染的 PNG 内容不同。 |
| Typst 构建失败 | 无效语法产生真实编译错误，quickfix 指向 `main.typ` 第 3 行。 |
| LaTeX | `:VimtexCompileSS` 调用实际 latexmk，合法文档成功；未知命令失败，`:VimtexErrors` 指向第 3 行。自动打开外部查看器在测试中关闭。 |
| 缺少可选工具 | 临时缩减 PATH 后，Typst 编译和 PDF 外部查看给出具体缺失工具提示。普通打开 Typst 和编译不再加载预览插件或下载预览依赖。 |

本机实测环境：OpenJDK 25.0.4.1、Maven 3.9.16、Gradle 9.7.1、JDTLS 1.60.0、java-test 扩展 0.46.0、Typst 0.15.1、latexmk 4.87。项目测试依赖固定为 JUnit Jupiter 5.10.2 和 TestNG 7.10.2。

这里没有把 Java 17 字节码目标等同于在 JDK 17 上运行；本次未验证不同厂商 JDK、Gradle 的 JDTLS 导入、JUnit 6 或跨平台调试。PDF 的真实转换和文件监听已经验证，实际终端图形显示、SSH 和外部浏览器显示仍需界面阶段验证。

## 修复的兼容性问题

原锁定组合 `jdtls 1.60.0` 与 `java-test 0.45.0` 本身不兼容，并非安装版本漂移。0.45.0 扩展内的主 JAR 仍名为 `com.microsoft.java.test.plugin-0.43.1.jar`，其 Manifest 要求 ASM `[9.9.0,9.10.0)`；JDTLS 提供的是 9.10.1。实际启动日志出现 `Failed to load extension bundles` 和对应 ASM 依赖无法解析，测试命令因此没有注册。

已将 java-test 锁定为 0.46.0，并定向恢复本机这一包。新版 Manifest 接受 ASM `[9.10.1,9.11.0)`；[官方发布说明](https://open-vsx.org/api/vscjava/vscode-java-test/0.46.0/file/changelog.md)也列出了随包提供 ASM 的修复。下载内容经[官方 SHA-256](https://open-vsx.org/api/vscjava/vscode-java-test/0.46.0/file/vscjava.vscode-java-test-0.46.0.sha256)核验：

```text
56c1e14dc73a30e9574c47042106fa52893bf8325b580f47c14ace07d5eef255
```

修复先在临时 bundle 目录通过真实测试，随后再次使用本机实际 Mason 安装验证。原包及 `share/java-test` 已备份到 `/tmp/nvim-java-test-backup-irfxyo9c`；这是本次本机操作的临时备份路径，长期恢复应依赖配置提交及对应 Mason 版本。

Java 测试和调试入口现在还会检查 JDTLS 实际公开的命令能力。仅有 JAR 文件但扩展加载失败时，会引导查看 `:LspLog` 的兼容错误和恢复匹配版本，避免把文件存在误判为功能可用。

## 验证边界

本检查里的通知收集只用于断言错误文字；文件、编译、语言协议、JUnit/TestNG 执行和 DAP 断点均为真实行为。`NVIM_JAVA_TEST_BUNDLES` 仅是隔离验证候选扩展的可选入口；常规检查不设置它，直接使用实际 Mason 包。

Typst 浏览器预览保持现有命令和键位，改为首次调用预览命令时加载；`:TypstCompilePdf` 始终可以独立使用。首次浏览器预览仍遵循插件自己的依赖准备行为。
