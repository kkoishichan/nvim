# AGENTS.md

给 AI 编码代理（Codex、Claude Code 等）的仓库说明。`CLAUDE.md` 只导入本文件，两边共用这一份规则。
面向人的说明在 `README.md` 和 `docs/`，这里只写代理需要遵守、又不容易从代码里看出来的东西。

## 仓库概况

- 个人 Neovim 配置，要求 Neovim 0.12+，只使用公开 API。入口：`init.lua` → `user.core.*` → `user.lazy`。
- **这个检出就是正在使用的 `~/.config/nvim`。** 在这里改文件会直接影响用户正在运行的 Neovim
  （extra 模式下 Lazy 的 change detection 会重载插件 spec）。半成品不要长时间留在工作树里。
- 用户可见文档（README、docs）用中文；代码注释、提交信息用英文。
- 当前行为以 `README.md` 和 `docs/editor-modes.md` 为准。`docs/*-plan.md` 是交付给代理的实施方案或已归档的计划，
  执行其中某个方案时按它的步骤和验收来，但不要把它当成现状说明。

## 多代理并行

Claude Code 和 Codex 可能同时在这个仓库里工作。默认假设另一个代理此刻也在改文件。

1. **开工前**运行 `git status` 和 `git diff --stat`。不是你本次会话写下的改动，一律当作另一个代理或用户正在进行的工作：
   不回退、不重新格式化、不暂存、不提交。
2. **共享工作树里禁止**会波及别人改动的命令：`git stash`、`git reset --hard`、`git clean`、`git switch` / `git checkout <branch>`、
   `git rebase`、`git commit -a`、`git add -A` / `git add .`，以及对自己没改过的文件执行 `git checkout -- <path>` / `git restore`。
3. **只暂存自己的路径**：`git add <path>...`。同一文件里混有别人的改动时用 `git add -p` 只选自己的 hunk；分不清归属就停下来问用户。
4. **编辑前重新读取目标文件**（对方可能刚改过），做精确的小范围替换，不要整文件重写。
5. **只格式化自己改过的文件**：`stylua <files>`。对整棵树只用 `stylua --check`。
6. **热点文件**冲突概率高，改动保持最小，提交前再看一遍 diff：
   `README.md`、`docs/improvement-progress.md`、`scripts/check.sh` 与 `scripts/run-check.lua` 的组列表、
   `lua/user/core/mode.lua` 的能力表、`lua/user/specs/init.lua`、`lua/user/core/keymaps.lua`、`lazy-lock.json`。
7. **共享机器状态同一时间只能由一个代理操作，并且先征得用户同意**：插件升级（`:Lazy update|sync|restore`）、
   修改 `lazy-lock.json`、Mason 安装（`:MasonToolsInstall` 等）、`scripts/deploy.sh`。
   它们改的是两个代理共用的 `~/.local/share/nvim`（插件、parser、Mason 工具），会让对方的检查失败或测到错误的版本。
8. 检查失败如果来自你 diff 之外的改动，报告给用户，不要顺手去修。
9. **较大或耗时较长的任务用独立 worktree**，不碰共享工作树，也不会触发正在运行的 Neovim 重载：

   ```sh
   git worktree add ../nvim-<agent>-<topic> -b <agent>/<topic>   # 例如 codex/bufferline、claude/lint-ui
   ```

   `scripts/check.sh` 从脚本自身位置定位仓库根，在 worktree 里运行检查的就是 worktree 的代码；插件仍来自共享数据目录，
   只要不改锁文件就没有问题。完成后由用户决定是否合并，合并后删除 worktree。
10. 做完就提交（见下节），缩短两个代理在同一批未提交改动上叠加工作的时间。

## 提交

- **完成工作后必须提交**，方便回退。每个逻辑独立的改动单独提交，不要把几件事攒成一个大提交；
  一个任务分几个阶段时，每个阶段通过检查后各提交一次。有组因缺依赖没跑时照常提交，并在回复中说明；
  检查失败时先修复，修不好就停下来问用户，不提交失败的状态。
- 提交前运行 `git diff --cached --stat`，确认暂存区里只有自己的改动：另一个代理暂存的文件也会被普通 `git commit` 一并带走。
- 单行 `type: subject`，英文，subject 小写开头、祈使语气，没有正文。type 用 `feat`、`fix`、`refactor`、`test`、`docs`、`build`。
- **不加任何代理署名**：不加 `Co-Authored-By`，不加 “Generated with …”，不以代理身份作为 author / committer，使用仓库已配置的 git 用户。
- 代码、检查和文档放在同一个提交里：行为变化同时更新 `scripts/checks/` 中的回归和 README / docs 中的说明。
- 不提交本机状态：`nvim.log`、`preferences.json`（均已在 `.gitignore` 中）。

## 架构约定

- **三档模式** fast / standard / extra：`require("user.core.mode").capabilities()` 返回只读能力表，读取不存在的能力名会报错。
  功能在注册之前就按能力决定是否启用，不要先初始化再隐藏。
- **新能力默认只在 extra 开启。** 要进入 standard，需要按 `docs/editor-modes.md` 的五条规则判定：
  凡是执行、渲染、自动化、停靠、常驻装饰中任意一类，都归 extra。standard 的能力是 `mode.lua` 里的显式白名单。
- **插件 spec**：`lua/user/plugins/*.lua` 每个文件一组。extra 导入整个目录，所以新文件默认只进 extra；
  standard 在 `lua/user/specs/init.lua` 中显式列出模块；fast 只使用 `lua/user/specs/` 里的工厂。
- **版本来源**：插件只看 `lazy-lock.json`，Mason 工具只看 `lua/user/toolchain.lua`。插件管理只在 extra 下进行（`NVIM_MODE=extra nvim +Lazy`）。
  适配层（如 `user.core.signature_overloads`）用哈希锁定插件源码，插件升级后会退回原实现，需在 `:ModeInfo` 的 adapters 行确认。

## 代码约定

- Lua 用 tab 缩进，遵循 StyLua 默认风格和 Selene（`selene.toml`、`neovim.yml`）。注释用英文，说明原因和边界，而不是复述代码。
- 只使用 Neovim 公开 API，不 monkey-patch 核心函数。静态检查会拦截 `vim.validate =`、`open_floating_preview =`、`vim.treesitter._`、`vim.highlight`。
- **颜色**：`lua/` 下只有 `lua/user/core/palette.lua` 可以出现色值字面量，其余地方都用 palette 的语义色。
  跟随主题的高亮通过 `require("user.core.highlights").on_colorscheme(name, callback)` 注册。
- **通知**：每个 `vim.notify` 都要带 `{ title = ... }`。
- **浮窗**：边框使用全局 `winborder`，插件不读取该选项时用 `require("user.core.layout").float_border()`；应用浮窗尺寸用 `layout.float_scale`。
- 图标统一来自 `user.core.icons`。autocmd 使用具名 augroup（`clear = true`）并写 `desc`。

## 验证

- 修改后运行 `./scripts/check.sh`（全部快速组）。迭代时只跑相关组：`./scripts/check.sh --group static --group <group>`，`--help` 可列出所有组。
- `static` 组不需要插件环境。其他组只核验依赖、不负责安装；缺依赖时按 `docs/ci-validation.md` 准备隔离环境：

  ```sh
  NVIM_MODE=extra ./scripts/prepare-checks.sh /absolute/env
  source /absolute/env/environment.sh
  ```

- 每个组在独立进程和临时 XDG config/cache/state 中运行，两个代理可以同时跑检查。
- **新增行为组**：新建 `scripts/checks/<group>.lua`，返回 `function(tmp)`；同时在 `scripts/check.sh`
  （usage、`add_group` 的 case、默认组列表）和 `scripts/run-check.lua` 的白名单中登记。
  插件互操作类断言放在 `scripts/checks/integration/`，由 `scripts/check.lua` 顺序运行。
- 真实语言工作流（`./scripts/check-workflows.sh`）、PTY 冒烟（`python3 scripts/ui-smoke.py`）和各个 benchmark 脚本
  耗时长、依赖 SDK，只在改到相应部分或用户要求时运行。
- **如实报告**：说明实际跑了哪些组、哪些因缺依赖没跑。`docs/*-results.json` 和测量文档中的数字由脚本生成，不要手改；
  没有实际运行过的验证，不要写成已通过。
