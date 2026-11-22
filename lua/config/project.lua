-- 项目本地工具：优先使用项目里锁定版本的工具，与命令行、CI、AI agent 保持一致
local M = {}

---在项目虚拟环境中查找可执行文件：<项目>/.venv → <项目>/venv → $VIRTUAL_ENV
---@param name string 可执行文件名
---@param source? string|integer 起始目录 / 文件路径 / buffer（默认当前 buffer）
---@return string? path 找不到时返回 nil
function M.venv_bin(name, source)
  local dirs = {}
  local root = vim.fs.root(source or 0, { ".venv", "venv" })
  if root then
    vim.list_extend(dirs, { root .. "/.venv", root .. "/venv" })
  end
  if vim.env.VIRTUAL_ENV then
    table.insert(dirs, vim.env.VIRTUAL_ENV)
  end
  for _, dir in ipairs(dirs) do
    local bin = dir .. "/bin/" .. name
    if vim.fn.executable(bin) == 1 then
      return bin
    end
  end
end

---语言服务的 cmd：优先用项目虚拟环境里的可执行文件，否则从 PATH 查找
---@param name string
---@param args string[]
function M.venv_cmd(name, args)
  return function(dispatchers, config)
    local bin = M.venv_bin(name, config.root_dir) or name
    return vim.lsp.rpc.start(vim.list_extend({ bin }, args), dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end
end

return M
