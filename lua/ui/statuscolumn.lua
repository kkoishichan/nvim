-- 状态列：git 标记 │ 诊断等标记 │ 行号 │ 折叠图标
-- 只为可见行绘制，且每行只查询这一行的标记，开销与文件大小无关
-- （LSP 语义高亮会在 buffer 里留下成千上万个标记，statuscol 等插件每次重绘都扫描整个 buffer，
--   C++ 等语义高亮多的文件快速滚动时会卡）
local M = {}

local api, fn = vim.api, vim.fn

-- 每个窗口的选项在一次重绘里只读取一次，重绘结束后清空
local wins = {} ---@type table<integer, {buf:integer, nu:boolean, rnu:boolean, signs:boolean, fold:boolean}>
local clear_pending = false
local function win_info(win)
  local info = wins[win]
  if info then
    return info
  end
  if not clear_pending then
    clear_pending = true
    vim.schedule(function()
      wins, clear_pending = {}, false
    end)
  end
  local wo = vim.wo[win]
  info = {
    buf = api.nvim_win_get_buf(win),
    nu = wo.number,
    rnu = wo.relativenumber,
    signs = wo.signcolumn ~= "no",
    fold = wo.foldcolumn ~= "0",
  }
  wins[win] = info
  return info
end

local icons = {} ---@type table<string, string> 标记文本 → 带高亮、补齐宽度的片段
local function icon(text, hl, width)
  local key = text .. "\0" .. (hl or "") .. "\0" .. width
  local ret = icons[key]
  if not ret then
    text = fn.strcharpart(vim.trim(text), 0, width)
    text = text .. string.rep(" ", width - api.nvim_strwidth(text))
    ret = hl and ("%#" .. hl .. "#" .. text .. "%*") or text
    icons[key] = ret
  end
  return ret
end

---1 格 git 标记 + 2 格其他标记（诊断等，取优先级最高的）
local function signs(buf, row)
  local marks = api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true, type = "sign" })
  local git, other
  for _, m in ipairs(marks) do
    local d = m[4] ---@type table
    if d.sign_text then
      if (d.sign_hl_group or ""):find("^GitSigns") then
        if not git or (d.priority or 0) > (git.priority or 0) then
          git = d
        end
      elseif not other or (d.priority or 0) > (other.priority or 0) then
        other = d
      end
    end
  end
  return (git and icon(git.sign_text, git.sign_hl_group, 1) or " ")
    .. (other and icon(other.sign_text, other.sign_hl_group, 2) or "  ")
end

local fcs ---@type {foldopen:string, foldclose:string}
---只在折叠起点画图标（展开 / 已折叠），不显示嵌套层级数字
local function fold(lnum)
  if fn.foldlevel(lnum) > fn.foldlevel(lnum - 1) then
    fcs = fcs or vim.opt.fillchars:get()
    local closed = fn.foldclosed(lnum) ~= -1
    return icon(closed and (fcs.foldclose or "+") or (fcs.foldopen or "-"), "FoldColumn", 1)
  end
  return " "
end

function M.get()
  -- 绘制状态列时，当前窗口就是正在绘制的窗口
  local win = vim.g.statusline_winid or api.nvim_get_current_win()
  local info = win_info(win)
  local lnum, virt = vim.v.lnum, vim.v.virtnum
  local ret = ""
  if info.signs then
    ret = virt == 0 and signs(info.buf, lnum - 1) or "   "
  end
  if info.nu or info.rnu then
    local num = ""
    if virt == 0 then
      local rel = vim.v.relnum
      num = (info.rnu and (rel ~= 0 or not info.nu)) and rel or lnum
    end
    ret = ret .. "%=" .. num .. " "
  end
  if info.fold then
    ret = ret .. "%@v:lua.require'ui.statuscolumn'.click_fold@" .. (virt == 0 and fold(lnum) or " ") .. "%T"
  end
  return ret
end

---点击折叠图标：开合该行的折叠
function M.click_fold()
  local pos = fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return
  end
  api.nvim_win_call(pos.winid, function()
    if fn.foldlevel(pos.line) > 0 then
      vim.cmd(pos.line .. (fn.foldclosed(pos.line) == -1 and "foldclose" or "foldopen"))
    end
  end)
end

M.expr = "%!v:lua.require'ui.statuscolumn'.get()"

function M.setup()
  vim.o.statuscolumn = M.expr
  vim.api.nvim_create_autocmd("OptionSet", {
    group = vim.api.nvim_create_augroup("user_statuscolumn", { clear = true }),
    pattern = "fillchars",
    callback = function()
      fcs, icons = nil, {}
    end,
  })
end

return M
