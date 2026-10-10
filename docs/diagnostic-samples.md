# 诊断样例的 extra 基准

2026-10-10，工作树基于 `977c564` 加上本轮未提交的改动，Neovim 0.12.5，120 × 36 PTY，`NVIM_MODE=extra`。输入为 `scripts/fixtures/diagnostics/` 下的 12 个故意带 warning 和 error 的样例，外加基准自带的生成 Lua 样本作对照；每样本三轮，热编译缓存，每轮等待 2 秒后输入 30 字符（间隔 25 ms）、保存 2 次、滚轮 2 组、翻页 6 次。39 个会话全部有效，原始逐事件记录见[测量 JSON](diagnostic-samples-results.json)。

`benchmark-mode.py` 本轮起会把 `--file` 样例同级的项目标记文件（`tsconfig.json`、`package.json`、`pyproject.toml`、`go.mod`、`Cargo.toml`、`compile_flags.txt`、`.clang-tidy`、`.luarc.json`）复制进隔离工作区，并保留样例相对标记文件的路径，因此 TypeScript 的 strict 选项、Rust 的 Cargo 分析和 C/C++ 的编译参数在测量中生效。依赖、其他源码和构建产物仍不复制。

## 结果

每格为三轮中位数，单位 ms；RSS 为编辑结束后 Neovim 与子进程合计，MiB；诊断为会话结束时的条数。

| 样例 | 诊断 | 客户端 | 首次输入 | 输入 p50 / p95 | 滚轮 p95 | 翻页 p95 | 保存 p50 / p95 | RSS |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 生成 Lua（对照） | 0 | lua_ls, typos | 20.1 | 2.88 / 7.74 | 4.43 | 17.30 | 21.7 / 23.0 | 281 |
| inventory.py | 60 | basedpyright, ruff, typos | 44.5 | 2.51 / 7.59 | 15.16 | 18.64 | 66.8 / 87.5 | 664 |
| scheduler.ts | 16 | vtsls, tailwindcss, typos | 57.6 | 4.05 / 17.13 | 6.47 | 14.41 | 225.1 / 229.3 | 877 |
| lib.rs | 16 | rust-analyzer, typos | 55.0 | 3.92 / 12.82 | 8.71 | 11.12 | 40.2 / 42.4 | 762 |
| logs.go | 5 | gopls, typos | 60.8 | 3.75 / 13.18 | 8.73 | 20.77 | 76.3 / 84.3 | 561 |
| matrix.c | 7 | clangd, typos | 62.5 | 3.64 / 13.38 | 6.64 | 17.23 | 34.8 / 36.0 | 183 |
| graph.cpp | 14 | clangd, typos | 82.7 | 3.24 / 10.52 | 5.79 | 13.12 | 40.3 / 44.2 | 489 |
| build.lua | 14 | lua_ls, typos | 44.7 | 3.93 / 9.03 | 7.45 | 10.83 | 24.8 / 30.4 | 379 |
| deploy.sh | 47 | bashls, typos | 52.1 | 5.01 / 16.82 | 4.73 | 24.68 | 19.6 / 23.0 | 231 |
| handbook.md | 45 | marksman | 49.0 | 5.08 / 11.95 | 6.00 | 37.49 | 122.0 / 130.1 | 183 |
| analytics.sql | 74 | sqlls, typos | 35.6 | 4.03 / 11.04 | 6.63 | 24.13 | 126.7 / 130.6 | 222 |
| ci.yaml | 26 | yamlls, typos | 52.7 | 4.65 / 10.82 | 9.61 | 23.42 | 87.3 / 89.4 | 228 |
| config.json | 8 | jsonls, typos | 31.6 | 2.84 / 6.49 | 4.50 | 4.00 | 95.7 / 98.2 | 160 |

空启动热缓存三轮 34.4 到 36.5 ms，首次打开生成 Lua 109.4 到 126.2 ms。

## 观察

- **超过 50 ms 的事件全部来自保存时格式化。** 输入、滚轮、翻页三类共 0 次；保存阶段 TypeScript（Prettier）每次 225 ms，Markdown、SQL、YAML、JSON 90 到 130 ms，Go（goimports 加 gofumpt）76 ms，Python（两次 ruff）67 ms，Rust 偶尔超过 50 ms；C/C++、Lua、Shell 的格式化在 50 ms 内。这些是同步阻塞，是本轮唯一能被用户感知为"卡一下"的地方。
- **输入 p95 最高的是 TypeScript 17 ms 和 Shell 17 ms。** TypeScript 在 extra 下自动附着 tailwindcss，三个客户端同时接收 didChange；bash-language-server 每次变更都重新运行 ShellCheck。Go、C、Rust 在 13 ms 左右，对照 Lua 为 7.7 ms。
- **翻页 p95 最高的是 Markdown 37 ms**，markview 渲染加 Tree-sitter 注入；Shell、SQL、YAML 在 23 到 25 ms。翻页包含键盘动画的首帧。
- **滚轮 p95 最高的是 Python 15 ms**，60 条诊断的下划线和标记随视口重绘；其余样例 4.5 到 9.6 ms。
- **内存由语言服务决定。** vtsls 加 tailwindcss 877 MiB，rust-analyzer 762 MiB，basedpyright 加 ruff 664 MiB，gopls 561 MiB；没有重型服务的样例 150 到 230 MiB。
- 首次输入 45 到 83 ms，包含 Blink 首次加载和首次补全请求，C++ 最高。

## 边界

三轮 30 字符不足以分辨 1 到 2 ms 的差异；诊断条数在会话结束时采样，rust-analyzer 的 cargo check 和 clangd 的 clang-tidy 结果可能在输入阶段才到达。Shell 样例在基准里只有 bashls 一个来源，直接打开时 nvim-lint 也会跑 ShellCheck，条数翻倍。测量不含终端绘制、触控板和网络。

## 复跑

```sh
F=scripts/fixtures/diagnostics
python3 scripts/benchmark-mode.py --output /tmp/nvim-diag --target extra --sample lua \
  --file $F/python/inventory.py --file $F/typescript/scheduler.ts --file $F/rust/src/lib.rs \
  --file $F/go/logs.go --file $F/c/matrix.c --file $F/cpp/graph.cpp --file $F/lua/build.lua \
  --file $F/sh/deploy.sh --file $F/markdown/handbook.md --file $F/sql/analytics.sql \
  --file $F/yaml/ci.yaml --file $F/json/config.json \
  --runs 3 --startup-cache warm --typing-chars 30 --saves 2 --wheel-bursts 2 --paging-events 6 --keep-going
```

输出目录须不存在且路径要短，原因见[引用高亮请求合并](reference-highlight-requests.md)的复跑说明。样例文件名在目录内唯一，基准用不含扩展名的文件名标识样本。
