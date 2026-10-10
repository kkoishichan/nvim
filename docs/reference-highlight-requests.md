# 引用高亮请求合并与 extra 剩余开销

2026-10-10，基于 `977c564`，目标是在不削减 extra 功能的前提下降低它的交互开销。本轮落实两项改动，并记录 extra 相对 standard 剩余开销的归因；原始逐事件数据、请求计数、插件加载耗时和采样结果见[测量记录](reference-highlight-requests-results.json)。

## 改动

**引用高亮按光标停顿请求。** 锁定版本的 vim-illuminate 在每次 `CursorMoved`、`CursorMovedI`、`TextChanged` 和 `ModeChanged` 上立即发出一次 `textDocument/documentHighlight` 请求，`delay` 只推迟绘制；连续移动或连续输入时每个事件各发一次请求，客户端取消上一次，服务端仍要处理。`user.core.illuminate_refresh` 把请求改为光标停下 100 ms 后发一次，离开已高亮的词仍立即清除；光标停下时窗口已不是当前窗口的请求直接丢弃，因为插件自己的轮询也会丢掉这种回复。插件的 `delay` 从 200 降为 100，最后一次移动到高亮出现的时间仍约 200 ms。适配器校验锁定插件 `engine.lua` 的哈希，插件升级后沿用原实现；`shutdown` 恢复原函数，模块重载只保留一个持有者。新增 `illuminate_refresh` 检查组覆盖 40 次移动合并为 1 次请求、立即清除、丢弃失效窗口、重载与清理。

**lightbulb 不再改写 `updatetime`。** nvim-lightbulb 首次随 `LspAttach` 加载时会把全局 `updatetime` 设为它自己的默认值 200，覆盖配置里的 250。显式传入 `updatetime = -1` 后保持 250。探针对照：基线进程附着三个 LSP 后 `updatetime` 为 200，当前为 250。

没有改动 matchup 的搜索预算、`hi_surround_always`、stopline、诊断显示、lightbulb 的插入模式触发或任何 extra 独有功能。

## 滚轮对照

`~/Projects/transformer/transformer.py`，240 行、10,706 字节，SHA-256 与此前记录一致。基线为未修改的 `977c564` worktree，当前为工作树，`NVIM_MODE=extra`；basedpyright、ruff、typos_lsp 全部初始化，等待 8 秒；四轮 AB/BA，每轮四段双向滚动，每段 20 个真实 SGR 滚轮输入，间隔 8 ms；PTY 为 `xterm-kitty`、120 × 36。请求数为四段滚动前后 `lsp_requests` 的差值合计。

| 配置 | 中位数 ms | P95 ms | 单轮最大事件 ms | 每轮 documentHighlight | 每轮 codeAction |
| --- | ---: | ---: | --- | ---: | ---: |
| 基线 | 2.99 | 10.21 | 15.5 / 13.9 / 20.4 / 41.2 | 70 | 12 到 15 |
| 当前 | 2.94 | 9.65 | 10.1 / 14.3 / 22.7 / 16.3 | 4 | 15 到 18 |

四段滚动只剩 4 次引用请求，每段停下一次。延迟的中位数和 P95 变化在轮次波动之内，不能据此声称滚动更快；codeAction 来自 lightbulb 的 `CursorHold`，本轮未改动。滚轮路径的尾延迟已被此前的配对缓存、输入让行、颜色和滚动条适配压到 10 ms 左右，没有超过 50 ms 的事件。

## 输入对照

`scripts/benchmark-mode.py`，extra，热编译缓存，每样本三轮：等待 2 秒，输入 30 字符（间隔 25 ms），保存 2 次，滚轮 2 组，翻页 6 次。修改前从基线 worktree 运行，修改后从工作树运行，两者不是交错采样。

| 样本 | 指标 | 修改前 | 修改后 |
| --- | --- | ---: | ---: |
| Lua | 输入 p50 / p95 ms | 2.80 / 7.46 | 2.69 / 10.49 |
| Lua | 滚轮 p95 ms | 6.11 | 4.57 |
| transformer.py | 输入 p50 / p95 ms | 3.06 / 9.61 | 2.66 / 10.11 |
| transformer.py | 滚轮 p95 ms | 11.24 | 14.20 |
| transformer.py | 保存 p95 ms | 91.77 | 114.77 |
| transformer.py | 结束 RSS MiB | 663 | 650 |

三轮 30 字符的样本不足以分辨 1 到 2 ms 的变化，这些差异都在波动范围内。插入模式下每个字符一次的引用请求同样被合并，但客户端为此付出的时间本来就小，收益在语言服务进程和与补全、诊断请求的竞争上，本轮没有单独测量服务端 CPU。

同一天、同一工作树的 standard 作为参照，说明 extra 相对默认档还剩多少：

| 样本 | 指标 | standard | extra 修改后 |
| --- | --- | ---: | ---: |
| Lua | 输入 p95 ms | 5.01 | 10.49 |
| Lua | 滚轮 p95 ms | 4.99 | 4.57 |
| transformer.py | 输入 p95 ms | 3.93 | 10.11 |
| transformer.py | 滚轮 p95 ms | 9.50 | 14.20 |
| transformer.py | 保存 p95 ms | 80.64 | 114.77 |
| transformer.py | 结束 RSS MiB | 610 | 650 |
| 热缓存首次打开 Lua ms | 三轮 | 82.1 / 83.6 / 93.7 | 93.0 / 103.5 / 106.3 |

standard 没有 typos_lsp，transformer.py 只有两个客户端；extra 的输入 p95 仍约为 standard 的两倍，差额由下一节归因。

## extra 剩余开销的归因

首次打开 transformer.py 时 Lazy 记录的插件加载耗时（两次探针，单位 ms）：standard 加载 12 个插件，合计 50 到 52；extra 加载 22 个，合计 58 到 93。extra 多出的部分全部挂在 `BufReadPost` 或 `LspAttach` 上：vim-matchup 4.2 到 5.7，dropbar 2.5 到 4.3，indent-blankline 2.4 到 3.9，scrollview 2.1 到 4.0，lightbulb 1.1 到 1.9，todo-comments 0.8 到 1.0，persistence 0.7，illuminate 0.7 到 2.1，faster 0.5 到 0.9，合计约 15 到 25 ms，与两档首次打开的差值一致。两档共有的 nvim-lspconfig 一项包含作为其依赖在 `BufReadPre` 加载的 Blink，5 到 10 ms。

滚轮测量期间的 LuaJIT 采样（1 ms 间隔，仅 Lua 执行时间）：

```text
17%  [string]:0
13%  query.lua:iter
 5%  highlighter.lua:fn
 4%  query.lua:handler
```

其余条目各不足 1%。Lua 侧的时间几乎都是 Tree-sitter 高亮查询，没有单一插件热点；extra 比 standard 多出的每事件成本分散在各装饰层的 extmark 和浮窗重绘上，属于 C 侧绘制，采样器看不到。

## 未做的项目与理由

- **matchup 搜索预算。** `matchup_matchparen_timeout` 默认 300 ms，可以缩短到 100 ms 来封顶单次同步搜索。本轮样本里没有超过 50 ms 的滚轮事件，缩短预算没有可测收益，却会让部分位置不再显示配对提示，因此没有改。
- **保存时格式化。** transformer.py 保存 p95 约 92 到 115 ms（两次 ruff 调用），此前测得 TypeScript 约 237 ms（Prettier）。这是 extra 和 standard 里单次最慢的阻塞事件。配置已为 TeX 提供保存后异步格式化，扩展到其他语言会改变 `:wq` 和连续保存的语义，属于取舍而不是优化，留待决定。
- **首次打开。** 把上述 15 到 25 ms 的装饰层加载推迟到首帧之后可以让文件更早显示，总耗时不变；每个插件对已打开 buffer 的附着方式都需要单独验证，本轮未实施。

## 复跑

```sh
./scripts/check.sh illuminate_refresh
git worktree add --detach /tmp/nvim-baseline 977c564
NVIM_MODE=extra python3 scripts/benchmark-wheel-pty.py \
  --file ~/Projects/transformer/transformer.py --baseline /tmp/nvim-baseline \
  --runs 4 --bursts 4 --settle-ms 8000 \
  --require-lsp basedpyright --require-lsp ruff --require-lsp typos_lsp
python3 scripts/benchmark-mode.py --output /tmp/nvim-mode-extra --target extra \
  --sample lua --file ~/Projects/transformer/transformer.py --runs 3 --startup-cache warm \
  --typing-chars 30 --saves 2 --wheel-bursts 2 --paging-events 6 --keep-going
```

基线目录必须是 Git 检出，脚本会记录其提交；输出目录须不存在，且路径要短：`vim.loader` 用百分号编码的完整源路径作为字节码缓存文件名，输出目录加上会话子目录和 Blink 最深的模块路径一旦超过 255 字节，`write_cachefile` 就会断言失败并弹出 Press ENTER，表现为控制请求超时。本轮 standard 对照第一次就因此全部失败，换到 `/tmp` 下的短目录后正常。记录中的插件加载耗时和 `updatetime` 探针使用独立的 `XDG_CONFIG_HOME`，其中 `nvim` 链接到对应的配置树，否则探针会从默认配置目录加载工作树的 Lua 模块。
