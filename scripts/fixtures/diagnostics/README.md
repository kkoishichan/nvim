# 诊断样例

每个文件都刻意留下若干 warning 和 error，用于观察语言服务和 linter 的诊断绘制、滚动和输入延迟。文件头部列出预期的诊断；行内 `diag:` 注释标出位置。静态检查（stylua、selene）排除本目录。

| 目录 | 文件 | 诊断来源 | 说明 |
| --- | --- | --- | --- |
| `python/` | `inventory.py` | basedpyright、Ruff | `pyproject.toml` 作为项目根 |
| `typescript/` | `scheduler.ts` | vtsls | `tsconfig.json` 开启 strict 与未使用检查 |
| `rust/` | `src/lib.rs` | rust-analyzer、clippy | 独立 Cargo 包，无依赖；clippy 诊断在保存后出现 |
| `go/` | `logs.go` | gopls、staticcheck | `go.mod` 作为模块根 |
| `c/` | `matrix.c` | clangd、clang-tidy | `compile_flags.txt` 打开 `-Wall -Wextra` |
| `cpp/` | `graph.cpp` | clangd、clang-tidy | 同上，C++20 |
| `lua/` | `build.lua` | lua-language-server | `.luarc.json` 作为工作区根 |
| `sh/` | `deploy.sh` | ShellCheck（nvim-lint、bashls） | standard 需 `:Lint`，extra 自动 |
| `markdown/` | `handbook.md` | marksman、markdownlint-cli2 | 含未解析链接 |
| `sql/` | `analytics.sql` | sqruff | 唯一的 SQL 诊断来源，standard 需 `:Lint` |
| `yaml/` | `ci.yaml` | yaml-language-server、yamllint | 重复键为 error |
| `json/` | `config.json` | vscode-json-language-server | 注释、尾逗号、重复键 |

文件名在整个目录内唯一，因为基准脚本用文件名（不含扩展名）标识样本。用法：直接打开文件，或作为基准输入：

```sh
NVIM_MODE=extra nvim scripts/fixtures/diagnostics/python/inventory.py
python3 scripts/benchmark-mode.py --output /tmp/nvim-diag --target extra \
  --file scripts/fixtures/diagnostics/python/inventory.py \
  --file scripts/fixtures/diagnostics/typescript/scheduler.ts
```

注意事项：

- gopls 在存在编译错误时只报告类型检查结果；修掉四处 error 后才会出现 shadow、unusedparams、staticcheck 等分析诊断。
- C/C++ 目录的 `.clang-tidy` 打开 `clang-analyzer-*` 和 `bugprone-*`。编译器警告和错误立即出现；空指针解引用、内存泄漏、释放后使用这类发现依赖 clangd 运行 clang-tidy 的时机，可能晚几秒出现，也可能被 clangd 省略。
- rust-analyzer 自身的诊断（类型不匹配、缺少 match 分支）立即出现；借用检查和 clippy 结果在 `cargo check` 完成后出现，首次需要数秒。
- Rust 的 `target/` 与 clangd 的 `.cache/` 已在各自目录的 `.gitignore` 中忽略，样例本身不依赖网络。

用这些样例跑过的一轮 extra 基准见 [docs/diagnostic-samples.md](../../../docs/diagnostic-samples.md)；`benchmark-mode.py` 会把样例同级的项目标记文件带入隔离工作区。

extra 模式下的实测诊断数（2026-10-10）：Python 60、TypeScript 16、Rust 16、Go 5、C 7、C++ 14、Lua 21、Shell 94、Markdown 45、SQL 74、YAML 26、JSON 8。
