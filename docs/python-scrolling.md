# Python 实文件滚动验证

2026-09-17，以 `6825eea` 为基线，使用用户提供的 `transformer.py`：237 行、10,592 字节。文件内容未修改，校验值保存在结果中。它没有触发大文件保护；完整配置启用了 Python Tree-sitter、上下文提示、缩进线、UFO 折叠和滚动条，附着 `ruff` 与 `typos_lsp`，诊断为零。Python 未启用颜色预览，滚轮也没有加载 Neoscroll。

后续[诊断与 LSP 复测](python-lsp-scrolling.md)确认，此处缺少 basedpyright 是沙箱内服务退出造成的，不能用本页的零诊断场景排除用户原本大量 warning 的影响。新版测试在主机上要求三个语言服务全部初始化，并记录诊断数量和滚动期间的请求。

## 改动

CPU 采样中的主要工作是 Tree-sitter 高亮查询。滚动条浮窗刷新会让正文再次绘制；隔离测试中，调整 Lua 内存回收节奏也能减少慢帧。

- Lua 收集器的步进倍率设置为 100，把回收工作分成较小的步骤。自动回收继续启用，启动回收的 pause 阈值保持原值。此设置作用于整个 Neovim 进程。
- 滚动条的固定合并窗口从 16 ms 调为 40 ms，减少连续输入期间的刷新。正文仍走原生滚动；滚动条会稍晚跟随，手动刷新、拖动及折叠几何继续由原插件处理。

## 最终对比

同机 Neovim 0.12.5、120 × 36 屏幕网格、相同锁定依赖。Python 四轮按 AB/BA 交错，每轮 100 次滚动，剔除前十次；Lua 对照两轮、每轮 80 次。事件完成后留 8 ms 处理时间，P95 使用 nearest-rank 算法。

| 场景 | 原配置中位数 | 当前中位数 | 原配置 P95 | 当前 P95 |
| --- | ---: | ---: | ---: | ---: |
| `transformer.py` | 5.37 ms | 5.51 ms | 29.39 ms | 25.24 ms |
| 3,000 行 Lua 对照 | 7.30 ms | 8.33 ms | 22.76 ms | 21.62 ms |

Python 慢帧延迟降低约 14%，中位数微升 0.14 ms。Lua 对照的中位数增加约 1 ms；这次调整主要改善偶发停顿，不能解释为所有编辑场景都更快。

另做每份配置单进程连续 1,200 次 Python 滚动，剔除前 100 次：P95 从 31.56 ms 降到 23.95 ms，Neovim 进程 CPU 时间从 16.43 s 降到 13.93 s。每 100 次采样的内存未持续增长；结束并静置后的常驻内存由约 40.1 MiB 增至 43.7 MiB。这是一次持续滚动检查，不能代替长期内存测试。

启动对照使用四轮交错测量及暖缓存，剔除首轮。空启动中位数为 109.7 → 109.4 ms，小 Lua 文件为 304.2 → 303.8 ms，没有观察到明显变化。

测量包含本地 RPC 和完整 Neovim 绘制，不包含真实终端、桌面合成器、设备延迟；也不代表固定频率的触控板输入。另一次短突发探针未确认尾延迟改善，其原始记录一并保留，因此不据此宣称触控板帧率提升。

## 验证与复跑

静态检查、滚动条、颜色预览、集成、大文件性能、编辑开销、启动加载、UI 运行时及生命周期回归通过。PTY 检查验证 SGR 滚轮双向输入、非当前分屏、滚动条位置和可见颜色更新。其等待从 Neovim 实际处理输入后开始，避免繁忙终端中提前读取异步装饰状态；它是功能检查，不用于计算延迟。

```sh
python3 scripts/benchmark-scroll.py --file ~/Projects/transformer/transformer.py \
  --baseline /path/to/6825eea-checkout --runs 4 --events 100
python3 scripts/scroll-smoke.py
./scripts/check.sh static scrollview_refresh scrolling_colors integration performance editing_cost startup_loading ui_runtime lifecycle
```

`--file` 模式在原项目中读取文件，来回滚动以避免到达末尾，核对前后文件校验值，并记录语言服务、高亮状态及重绘次数。原始数据见 [python-scrolling-results.json](python-scrolling-results.json)。重启 Neovim 后加载这些设置。
