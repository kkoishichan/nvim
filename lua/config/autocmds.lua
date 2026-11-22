local function augroup(name)
  return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end
local autocmd = vim.api.nvim_create_autocmd

-- 复制时高亮
autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    vim.hl.on_yank({ timeout = 200 })
  end,
})

-- 打开文件时回到上次光标位置
autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(ev)
    local exclude = { "gitcommit", "gitrebase" }
    if vim.tbl_contains(exclude, vim.bo[ev.buf].filetype) or vim.b[ev.buf].last_loc_done then
      return
    end
    vim.b[ev.buf].last_loc_done = true
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- 终端尺寸变化时均分窗口
autocmd("VimResized", {
  group = augroup("resize_splits"),
  callback = function()
    local tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. tab)
  end,
})

-- 外部修改文件（如 AI agent 改代码）后自动重载（未修改的 buffer 直接重载）
local function checktime()
  if vim.o.buftype ~= "nofile" and vim.fn.getcmdwintype() == "" then
    vim.cmd("checktime")
  end
end
autocmd({ "FocusGained", "TermClose", "TermLeave", "BufEnter" }, {
  group = augroup("checktime"),
  callback = checktime,
})
-- 不切换焦点、只看着屏幕时也能刷新：普通模式下每秒检查一次（只比较文件时间戳，开销可忽略）
vim.uv.new_timer():start(
  1000,
  1000,
  vim.schedule_wrap(function()
    if vim.api.nvim_get_mode().mode == "n" then
      checktime()
    end
  end)
)

-- 这些辅助窗口按 q 关闭
autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = { "help", "man", "qf", "checkhealth", "lspinfo", "query", "startuptime", "grug-far", "gitsigns-blame" },
  callback = function(ev)
    vim.bo[ev.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = ev.buf, silent = true, desc = "Quit buffer" })
  end,
})

-- 文本类文件开启换行与拼写
autocmd("FileType", {
  group = augroup("wrap_spell"),
  pattern = { "text", "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

-- o/O 不自动续写注释
autocmd("FileType", {
  group = augroup("formatoptions"),
  callback = function()
    vim.opt_local.formatoptions:remove("o")
  end,
})

-- 保存时自动创建不存在的目录
autocmd("BufWritePre", {
  group = augroup("auto_mkdir"),
  callback = function(ev)
    if ev.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(ev.match) or ev.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- 保存时删除行尾空格（Markdown 的行尾双空格有意义，跳过）
autocmd("BufWritePre", {
  group = augroup("trim_whitespace"),
  callback = function(ev)
    local skip = { markdown = true, diff = true, bigfile = true, oil = true }
    if skip[vim.bo[ev.buf].filetype] or not vim.bo[ev.buf].modifiable or vim.bo[ev.buf].binary then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns silent! %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})

-- 大文件保护：超过 1.5MB 或平均行长超过 1000 的文件识别为 bigfile，关闭 treesitter、LSP 等
vim.filetype.add({
  pattern = {
    [".*"] = {
      function(path, buf)
        if not path or not buf or vim.bo[buf].filetype == "bigfile" then
          return
        end
        if path ~= vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) then
          return
        end
        local size = vim.fn.getfsize(path)
        if size <= 0 then
          return
        end
        if size > 1.5 * 1024 * 1024 then
          return "bigfile"
        end
        local lines = vim.api.nvim_buf_line_count(buf)
        return (size - lines) / lines > 1000 and "bigfile" or nil
      end,
      { priority = math.huge },
    },
  },
})
autocmd("FileType", {
  group = augroup("bigfile"),
  pattern = "bigfile",
  callback = function(ev)
    vim.b[ev.buf].bigfile = true
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.statuscolumn = ""
    vim.opt_local.conceallevel = 0
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.bo[ev.buf].syntax = vim.filetype.match({ buf = ev.buf }) or ""
      end
    end)
  end,
})

-- 自动切换工作目录到当前文件所在的 git 根目录
autocmd("BufEnter", {
  group = augroup("auto_root"),
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" or vim.api.nvim_buf_get_name(ev.buf) == "" then
      return
    end
    local root = vim.b[ev.buf].git_root
    if root == nil then
      root = vim.fs.root(ev.buf, ".git") or false
      vim.b[ev.buf].git_root = root
    end
    if root and root ~= vim.uv.cwd() then
      vim.api.nvim_set_current_dir(root)
    end
  end,
})

-- fcitx5：离开插入模式时切到英文，进入插入模式时恢复（按 buffer 记录）
if vim.fn.executable("fcitx5-remote") == 1 and (vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY) then
  local group = augroup("fcitx")
  local function deactivate(buf)
    vim.system({ "fcitx5-remote" }, { text = true }, function(out)
      local active = vim.trim(out.stdout or "") == "2"
      vim.schedule(function()
        if buf and vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].fcitx_active = active
        end
      end)
      if active then
        vim.system({ "fcitx5-remote", "-c" })
      end
    end)
  end
  autocmd("InsertLeave", {
    group = group,
    callback = function(ev)
      deactivate(ev.buf)
    end,
  })
  autocmd("InsertEnter", {
    group = group,
    callback = function(ev)
      if vim.b[ev.buf].fcitx_active then
        vim.system({ "fcitx5-remote", "-o" })
      end
    end,
  })
  autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      deactivate()
    end,
  })
  autocmd("FocusGained", {
    group = group,
    callback = function()
      if vim.api.nvim_get_mode().mode == "n" then
        deactivate()
      end
    end,
  })
end

-- 启动：不带参数时显示启动页（会话需手动恢复：<leader>qs）
autocmd("StdinReadPre", {
  group = augroup("stdin"),
  callback = function()
    vim.g.started_with_stdin = true
  end,
})
autocmd("VimEnter", {
  group = augroup("startup"),
  nested = true,
  callback = function()
    -- nvim <目录>：把工作目录切到该目录（目录本身由 oil 打开）
    if vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
      vim.api.nvim_set_current_dir(vim.fn.fnamemodify(vim.fn.argv(0), ":p"))
    end
    if vim.fn.argc() > 0 or vim.g.started_with_stdin then
      return
    end
    vim.schedule(function()
      if vim.api.nvim_buf_get_name(0) == "" and vim.bo.buftype == "" and vim.api.nvim_buf_line_count(0) <= 1 then
        vim.cmd("Dashboard")
      end
    end)
  end,
})
