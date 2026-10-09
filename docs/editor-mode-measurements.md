# 三档模式性能测量

2026-10-10，本机 Neovim 0.12.5、120×36 PTY，模拟 kitty 的终端询问和鼠标协议。每个样本五轮比较 fast、standard、extra、原生 Neovim，共 120 个有效编辑会话。运行顺序交替，Rust/Markdown 的 standard 与 extra 另行交错复核。原始逐事件延迟、客户端、内存及磁盘记录见[测量 JSON](editor-mode-measurements.json)。

standard 在保留主要编辑功能后降低了多数代码样本的输入和滚轮成本：热缓存首次打开 Lua 为 **86.70 ms**（extra **111.94 ms**）；transformer.py 输入 p95 为 **4.62 ms**（extra **14.09 ms**），滚轮 p95 为 **9.23 ms**（extra **14.54 ms**）。该文件新增缓存约 **1.82 MiB**（extra **2.53 MiB**），主要语言服务仍使合计 RSS 达到约 **611 MiB**。完整结果保留未变快的项目；这些数据支持日常功能取舍，不代表每个操作都会更快。

## 方法与边界

- 基于 `4ef7415` 的工作树；基准脚本哈希、锁文件哈希和 dirty 状态保留在 JSON，包含最终手动 LSP 保护和项目隔离修复。审计发现临时输入法测试条件影响了少数 Rust/Markdown extra 样本，因此这两组的 standard/extra 共 20 个会话全部以最终配置重新交错采样；复核前后验证 104 份运行源码哈希不变。补测来源和原批次备份记录在 JSON。
- 每系列先丢弃一次启动；冷/热仅指 Lua 编译缓存，热缓存复用配置与缓存路径，不清空系统页缓存。`first_open` 为首次打开生成的 Lua 样本，启动耗时不代表语言服务已完成初始化。回归结束后单独采样，未与回归进程并行。
- 每会话等待 2 秒，输入 30 字符（间隔 25 ms），保存 2 次，滚轮 2 组最多各 20 事件（间隔 8 ms），半页翻动最多 6 次（间隔 80 ms）；短文件按长度缩减。
- 延迟从输入解码算到首次反映变化的重绘结束，不包含解码前排队、真实 kitty 绘制、触控板驱动、网络延迟或整段动画时长。standard/extra 保留键盘动画。输入、滚轮、保存和翻页 p95 合并五轮事件计算；首次输入取中位数。
- 文件、偏好、状态和缓存均隔离；每份副本有独立 Git 项目边界，防止服务扫描父级临时目录。真实 transformer.py 只复制文件自身，不复制项目依赖，因此诊断和实际项目可能不同；采样后验证原文件哈希未变。Rust 有独立、无外部依赖的 Cargo 清单，npm/Cargo 离线。
- 初次批次发现父级临时目录的 Git 边界干扰语言服务，整批废弃。这里的 120 个会话全部来自修复项目隔离后的重新采样。
- 原生对照使用同一 Neovim 的 `-u NONE` 和原生语法。所有会话禁用 swap / ShaDa，磁盘统计不包含这两类恢复数据。内存是 Neovim、TUI 与子进程合计 RSS 的快照，未去重共享页，也不是峰值。
- 五轮只代表本机样本；语言服务异步启动、索引和诊断发布会波动。保留实际客户端与诊断数量，不承诺每一项都满足 fast < standard < extra。

## 启动

| 场景 | fast ms | standard ms | extra ms | 原生 ms |
| --- | ---: | ---: | ---: | ---: |
| cold / empty | 33.13 | 42.93 | 50.43 | 4.75 |
| cold / first_open | 43.04 | 116.74 | 151.22 | 5.04 |
| warm / empty | 27.45 | 35.52 | 37.94 | 4.62 |
| warm / first_open | 39.80 | 86.70 | 111.94 | 4.33 |

## 连续输入 p95

| 样本 | fast ms | standard ms | extra ms | 原生 ms |
| --- | ---: | ---: | ---: | ---: |
| lua | 3.92 | 5.35 | 9.78 | 1.15 |
| typescript | 1.98 | 6.38 | 13.53 | 0.99 |
| rust | 1.98 | 4.68 | 10.45 | 1.25 |
| markdown | 11.26 | 12.02 | 13.48 | 0.88 |
| diagnostics | 2.22 | 4.68 | 7.91 | 0.95 |
| transformer | 1.90 | 4.62 | 14.09 | 1.04 |

## 滚轮 p95

| 样本 | fast ms | standard ms | extra ms | 原生 ms |
| --- | ---: | ---: | ---: | ---: |
| lua | 1.40 | 4.53 | 6.86 | 0.84 |
| typescript | 2.67 | 5.05 | 9.18 | 1.24 |
| rust | 2.77 | 4.55 | 7.66 | 1.08 |
| markdown | 6.02 | 7.00 | 4.29 | 1.27 |
| diagnostics | 1.35 | 2.50 | 8.62 | 0.86 |
| transformer | 10.28 | 9.23 | 14.54 | 1.79 |

## 首次输入、保存与翻页

每格为首次输入中位数 / 保存 p95 / 翻页 p95，单位 ms。standard/extra 的保存包含格式化；fast/原生没有自动格式化。

| 样本 | fast | standard | extra | 原生 |
| --- | ---: | ---: | ---: | ---: |
| lua | 21.05 / 0.32 / 7.44 | 13.42 / 23.55 / 10.86 | 21.24 / 38.03 / 16.37 | 0.65 / 0.25 / 1.99 |
| typescript | 23.94 / 0.35 / 8.84 | 24.21 / 236.66 / 12.00 | 70.39 / 277.81 / 17.27 | 0.51 / 0.55 / 2.81 |
| rust | 25.50 / 1.04 / 15.29 | 20.05 / 29.93 / 30.69 | 40.23 / 47.28 / 38.09 | 0.69 / 0.32 / 2.85 |
| markdown | 22.23 / 0.31 / 2.93 | 28.16 / 126.87 / 13.46 | 37.64 / 142.49 / 17.12 | 0.64 / 0.30 / 2.46 |
| diagnostics | 18.03 / 0.31 / 6.43 | 23.19 / 171.37 / 10.83 | 32.34 / 120.31 / 11.78 | 0.63 / 0.38 / 1.60 |
| transformer | 21.98 / 0.21 / 16.77 | 22.73 / 43.64 / 23.27 | 36.68 / 105.25 / 18.98 | 0.89 / 0.28 / 3.34 |

## 内存与新增缓存

每格为编辑结束后的合计 RSS 中位数 MiB / 独立空缓存目录新增 KiB。这里不包含已安装插件、Mason 和 parser；切换模式不会删除旧安装或已有缓存。完整的空闲 RSS、文件数和状态增量在 JSON 中。

| 样本 | fast | standard | extra | 原生 |
| --- | ---: | ---: | ---: | ---: |
| lua | 35.7 / 645 | 268.6 / 1877 | 292.5 / 2656 | 23.4 / 0 |
| typescript | 37.0 / 645 | 781.2 / 1848 | 944.4 / 2659 | 23.6 / 0 |
| rust | 36.2 / 645 | 705.7 / 1943 | 753.7 / 2666 | 23.5 / 0 |
| markdown | 38.9 / 697 | 159.5 / 1874 | 182.3 / 3409 | 24.3 / 0 |
| diagnostics | 34.3 / 649 | 598.6 / 1865 | 630.0 / 2589 | 23.5 / 0 |
| transformer | 37.0 / 649 | 611.5 / 1865 | 651.3 / 2589 | 23.3 / 0 |

## 实际服务与诊断

| 样本 | standard 客户端 | extra 客户端 | standard / extra 诊断数范围 |
| --- | --- | --- | --- |
| lua | lua_ls | lua_ls,typos_lsp | 0–0 / 0–0 |
| typescript | vtsls | tailwindcss,typos_lsp,vtsls | 0–0 / 0–0 |
| rust | rust-analyzer | rust-analyzer,typos_lsp | 0–0 / 0–0 |
| markdown | marksman | marksman | 0–0 / 41–41 |
| diagnostics | basedpyright,ruff | basedpyright,ruff,typos_lsp | 164–164 / 164–164 |
| transformer | basedpyright,ruff | basedpyright,ruff,typos_lsp | 323–323 / 323–323 |

fast 所有会话均无自动语言客户端、无文件监听，保留 which-key 的模式检测定时器。standard/extra 保留主要语言服务，成本仍主要由项目分析和相应界面决定。TypeScript 的 extra 可自动启用 Tailwind，standard 在没有项目配置时未启用。

standard 不自动执行独立 lint；Markdown 中两档虽然都有 marksman，实际诊断数量仍不同，不能作为等量诊断负载比较。Python 两组的诊断数量一致。

## 复现

```sh
python3 scripts/benchmark-mode.py \
  --output /tmp/nvim-three-mode-recheck --runs 5 \
  --sample lua --sample typescript --sample rust --sample markdown --sample diagnostics \
  --file ~/Projects/transformer/transformer.py --startup-cache both \
  --typing-chars 30 --saves 2 --wheel-bursts 2 --paging-events 6 --keep-going
```

输出目录须不存在；测量需要已准备的插件、parser、工具、Python msgpack 和可用 PTY。原始 phase 文件保留在 JSON 记录的 `evidence_directory`；补测会话按其 `session_evidence_directory` 查找。
