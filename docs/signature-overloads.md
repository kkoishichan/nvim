# 签名重载

2026-10-11，基于 `1f884a2`，Neovim 0.12.6，blink.cmp 1.10.2（`78336bc`）。签名提示的参数高亮"时好时坏"、重载"识别不出来"，这里记录测出来的原因和采取的做法。

## 服务器给的参数索引是准的

用一个带两个重载的 `area` 和一个普通 `plain` 函数，在 12 个光标位置向四个服务器直接发 `textDocument/signatureHelp`（括号后、各个实参内、`plain(1, area(2, |), 3.0)` 的嵌套内外、未写完的 `plain(1, |` 和 `area(2.0, |`）。四个服务器在所有位置的 activeParameter 都正确；唯一的空结果是 clangd 在光标停在 `3.0` 字面量中间时。之前的自定义实现用 treesitter 本地重算参数，是在解决一个不存在的问题。

## 重载在实参确定前没有服务器能判断

| 服务器 | 选重载 | 客户端在 `activeSignatureHelp` 里回传的选择 |
|---|---|---|
| vtsls | 实参足以区分后选中（`area(2.0, true)` → 第 2 个），未写完时为第 1 个 | 尊重，重触发时保持 |
| basedpyright | 只在关键字实参匹配时切换（`precise=` → 第 2 个），否则第 1 个 | 忽略 |
| clangd | 永远第 1 个，列出全部 | 忽略 |
| lua_ls | 不给 activeSignature，只给每个签名各自的 activeParameter | 忽略 |

所以"输入时自动识别重载"没有协议层解法。编辑器要做的是把高亮画在正确的签名上，并给用户一个切换键。

## Blink 1.10.2 的渲染错误

`signature/window.lua` 把所有重载的标签逐行堆进窗口，但高亮范围用 Neovim 的 `convert_signature_help_to_markdown_lines` 按"只有当前签名"算出，然后固定画在第 0 行。activeSignature 为 0 时正确；服务器一旦选中第二个重载，第二个签名的参数偏移就被画在第一个签名上。用合成的双重载响应复现：

```
window lines:
  0: int area(int width, int height)
  1: double area(double radius, bool precise)
highlight: line=0 cols=27-31 text="ght)"      -- 本该高亮第 1 行的 precise
```

偏移超出第一行长度时抛 `Invalid 'end_col': out of range`，这次更新丢失，浮窗停留在上一次内容。上游 main（2026-10-11）仍是同样写法。Blink 没有任何重载位置指示，也没有切换键。

## 做法：`user.core.signature_overloads`

沿用仓库的适配器机制（源码哈希锁定、失效降级、`:ModeInfo` 和健康检查列出）。适配层在 Blink 的签名处理函数初始化后替换 `window.open_with_signature_help`：

- 只渲染选中的签名，参数高亮按它自己的偏移计算；有多个重载时在标签末尾加 `(n/m)`，用 `BlinkCmpSignatureHelpOverload` 着色。
- 插入模式 `<C-s>` 循环重载（Blink keymap 项，不可用时回退原按键）。手动选择按调用上下文记录，同一调用的重触发保持该选择；服务器自己的选择或重载数量变化时以服务器为准；新的调用从服务器的选择开始。
- 手动选择通过 `trigger.set_active_signature_help` 写回重触发上下文的 `activeSignatureHelp`，vtsls 会在服务器端保持。
- 请求、触发字符、定位、滚动、文档显示全部仍由 Blink 负责。`signature/window.lua` 与 `signature/init.lua` 的哈希变化时适配层不安装，Blink 原生渲染生效。

## 验证

```sh
./scripts/check.sh signature_overloads signature
```

`signature_overloads` 用假 LSP 服务器走真实的 Blink 路径：第二个重载单独显示并高亮 `bool precise`（偏移超出首行长度的那种响应不再报错）、`(2/2)` 标记、`<C-s>` 循环与回传、同一调用的重触发保留手动选择、服务器改变选择时以服务器为准、新调用重置、单签名不加标记、空响应关闭浮窗、`shutdown` 恢复原函数后可重装。`signature` 组保留 Blink 公开接口的回归，重载用例改为断言只显示选中项并可切换到另一项。
