# Neovim 配置

功能强大的编辑器，而非大型 IDE。Neovim 0.12 · lazy.nvim · 59 个插件，全部按需加载。
启动时间：打开文件约 35ms，不带参数约 25ms。设计细节见 [PLAN.md](PLAN.md)。

## 主题与透明

- `<leader>uC` 或 `:Theme`：主题选择器，移动时实时预览，回车确认（自动保存）
- `<leader>ut` 或 `:Transparent`：切换透明背景（自动保存）
- `:Theme <名称>`：直接切换，支持 Tab 补全
- 状态保存在 `~/.local/state/nvim/ui.json`
- 透明效果需要终端配合：在 kitty 配置里设置 `background_opacity 0.85`
- 结构：`lua/ui/palette.lua` 取色 → `highlights.lua` 生成统一界面 → `transparent.lua` 透明处理

## 文件与目录

- **neo-tree**：侧边栏，看项目结构和 git 状态（`<leader>e`）
- **oil**：所有目录 buffer —— `nvim 目录`（同时切换工作目录）、`:e 目录`、在目录路径上 `gf`、按 `-`

## 快捷键速查（leader = 空格，localleader = `\`）

### 常用
| 按键 | 功能 |
|---|---|
| `<leader><space>` | 找文件 |
| `<leader>/` | 全局搜索 |
| `<leader>,` | 切换 buffer |
| `<leader>e` | 文件树侧边栏（neo-tree；在里面按 `O` 用 oil 打开选中的目录） |
| `-` | oil：打开当前文件所在目录，像编辑文本一样管理文件（改名/移动/删除/新建后 `:w` 或 `<C-s>` 应用；`-` 上一级 · `<CR>` 打开 · `<C-v>`/`<C-x>` 分屏打开 · `P` 预览 · `q` 关闭） |
| `<leader>;` | 面包屑导航 |
| `<leader>?` | 当前 buffer 的快捷键 |
| `<C-s>` | 保存 |
| `<C-/>` | 浮动终端 |
| `<S-h>` / `<S-l>` | 上一个 / 下一个 buffer |
| `<C-hjkl>` | 切换窗口 |
| `<A-方向键>` | 调整窗口大小 |
| `<A-j>` / `<A-k>` | 上下移动行 |

### 跳转与预览
| 按键 | 功能 |
|---|---|
| `s` / `S` | flash 跳转 / 按语法节点选中 |
| `gd` `grr` `gI` `gy` `gD` | 定义 / 引用 / 实现 / 类型定义 / 声明 |
| `gpd` `gpr` `gpi` `gpy` | glance 预览（不离开当前位置） |
| `K` | 悬浮文档 |
| `]f` `]c` `]a` | 下一个函数 / 类 / 参数（大写跳到结尾，`[` 反向） |
| `]h` `]d` `]e` `]w` `]t` | 下一个 git 改动 / 诊断 / 错误 / 警告 / TODO |
| `[x` | 跳到 sticky context 所在行 |
| `]]` / `[[` | 下一个 / 上一个同名引用（光标下符号的高亮处） |
| `{` / `}` | 上一个 / 下一个符号（aerial） |
| `<C-o>` / `<C-i>` | 跳转历史 |

### 编辑
| 按键 | 功能 |
|---|---|
| `gsa` `gsd` `gsr` | 添加 / 删除 / 替换包围符 |
| `gc` / `gcc` | 注释 |
| `vaf` `vic` `ci,` 等 | 文本对象：f 函数、c 类、a 参数、o 代码块、t 标签、u 函数调用、g 整个文件 |
| `<C-n>` / `<C-p>` | 多光标：选中下一个 / 上一个相同的词 |
| `<C-↑>` / `<C-↓>` | 多光标：在上 / 下一行加光标 |
| `<leader>mA` | 多光标：选中所有相同的词 |
| `<C-LeftMouse>` | 多光标：鼠标点击加光标 |
| `<Esc>` | 退出多光标 |
| `<leader>sr` | 全局搜索替换（grug-far） |
| `<leader>su` | 撤销树 |

### 代码（LSP）
| 按键 | 功能 |
|---|---|
| `<leader>ca` / `<leader>cA` | 代码操作 / 源码操作 |
| `<leader>cr` | 重命名 |
| `<leader>cf` | 格式化 |
| `<leader>cd` | 当前行诊断 |
| `<leader>cs` | 符号大纲 |
| `<leader>cl` | LSP 信息 |
| `<leader>ss` / `<leader>sS` | 文件内符号 / 工作区符号 |
| `<leader>zi` | 折叠 import 区块 |

### 搜索（`<leader>s`）
`sb` 当前文件的行 · `sw` 光标下的词 · `sd`/`sD` 当前文件/整个项目的诊断 · `sh` 帮助 · `sk` 快捷键 ·
`sc`/`sC` 命令历史/命令 · `sm` 标记 · `sj` 跳转列表 · `s"` 寄存器 · `st` TODO · `sR` 恢复上次搜索

### 文件（`<leader>f`）
`ff` 文件 · `fr`/`fR` 最近文件（全部/当前目录）· `fc` 配置文件 · `fg` git 文件 · `fn` 新建文件 ·
`fy`/`fY` 复制相对/绝对路径

### Git（`<leader>g`）
| 按键 | 功能 |
|---|---|
| `gg` | lazygit |
| `gs` `gl` `gf` `gb` `gB` | 状态 / 提交记录 / 文件历史 / 搜索 blame / 分支（fzf） |
| `gL`（可视模式） | 选中行的历史 |
| `gd` / `gD` / `gH` | diffview：工作区改动 / 与 main 比较 / 文件历史 |
| `ge` | git 状态文件树 |
| `gy` / `go` | 复制当前行（或选区）的远程仓库链接 / 在浏览器打开 |
| `ghs` `ghr` `ghp` | 暂存 / 撤销 / 预览改动块 |
| `ghb` `ghB` | 单行 blame 详情 / 整文件 blame |
| `<leader>uB` | 开关行内 blame |

diffview 里：`<Tab>` 切换文件，`]c` 下一个改动块，`]x` 下一个冲突，`<leader>co`/`ct`/`ca` 保留我的/对方的/两边，`q` 关闭。

### 诊断（`<leader>x`）
`xx`/`xX` 诊断面板（全部/当前文件）· `xs` 符号 · `xL` LSP · `xq`/`xl` quickfix/location list · `xt` TODO

### 界面开关（`<leader>u`）
`uC` 主题 · `ut` 透明 · `uf`/`uF` 自动格式化（全局/当前 buffer）· `uh` 类型提示 · `uv` 诊断显示方式（气泡 ↔ 行下虚拟行）·
`ud` 诊断 · `uw` 自动换行 · `ul`/`uL` 行号/相对行号 · `us` 拼写检查 · `uc` conceal · `ug` 缩进线 ·
`ux` sticky context · `uS` 平滑滚动 · `uB` 行内 blame · `ui` 查看光标处的高亮组

### buffer / 会话 / 窗口
`<leader>bd`/`bD` 关闭（强制关闭）· `bo` 关闭其他 · `bp` 固定 · `bP` 关闭所有未固定的 · `bl`/`br` 关闭左侧/右侧 · `[B`/`]B` 移动标签位置 ·
`<leader>qs`/`ql`/`qS` 恢复会话/恢复上次会话/选择会话 · `qd` 本次不保存会话 · `qq` 全部退出 ·
`<leader>-`/`|` 横向/竖向分屏 · `wd` 关闭窗口

### 语言相关
- **Markdown**：`\p` 在浏览器里预览（同步滚动，HTML 文件也可用）· `\r` 开关编辑器内渲染
- **Typst**：`\p` 浏览器实时预览（光标同步）· `\c` 导出 PDF · `\v` 用 zathura 查看 PDF（没导出过会先导出）
- **LaTeX**（vimtex）：`\ll` 开始/停止编译 · `\lv` 在 zathura 中正向跳转 · `\lc` 清理中间文件 · `\lt` 目录 · `cse` 修改环境名 · `ie`/`i$` 选中环境/公式
- **Cargo.toml**：crates.nvim 显示依赖的最新版本

## 维护

- `:Lazy`：插件管理（`<leader>l`）
- `:Mason`：语言服务和格式化工具（后备；项目本地和系统里有的优先）
- `:checkhealth vim.lsp`：LSP 状态
- `:ConformInfo`：格式化工具状态
- 新增语言：在 `lua/plugins/lsp.lua` 的 `mason_servers`（由 mason 安装）或 `system_servers`（用系统 / 项目里的）里加服务名；需要格式化的话在 `lua/plugins/format.lua` 里加
