-- 折叠行：保留 treesitter 语法高亮，末尾显示折叠行数
local M = {}

local function ts_chunks(buf, lnum, text)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not ok or not parser then
    return { { text } }
  end
  local lang = parser:lang()
  local query = vim.treesitter.query.get(lang, "highlights")
  local tree = parser:trees()[1]
  if not query or not tree then
    return { { text } }
  end

  local hls = {}
  for id, node in query:iter_captures(tree:root(), buf, lnum, lnum + 1) do
    local name = query.captures[id]
    if name:sub(1, 1) ~= "_" and name ~= "spell" and name ~= "nospell" and name ~= "conceal" then
      local sr, sc, er, ec = node:range()
      local s = sr < lnum and 0 or sc
      local e = er > lnum and #text or ec
      for i = s + 1, math.min(e, #text) do
        hls[i] = "@" .. name .. "." .. lang
      end
    end
  end

  local chunks, cur, hl = {}, "", nil
  for i = 1, #text do
    local h = hls[i]
    if h ~= hl then
      if cur ~= "" then
        chunks[#chunks + 1] = { cur, hl }
      end
      cur, hl = "", h
    end
    cur = cur .. text:sub(i, i)
  end
  if cur ~= "" then
    chunks[#chunks + 1] = { cur, hl }
  end
  return chunks
end

function M.text()
  local buf = vim.api.nvim_get_current_buf()
  local start = vim.v.foldstart
  local line = vim.api.nvim_buf_get_lines(buf, start - 1, start, false)[1] or ""
  local chunks = ts_chunks(buf, start - 1, line)
  local tab = string.rep(" ", vim.bo[buf].tabstop)
  for _, c in ipairs(chunks) do
    c[1] = c[1]:gsub("\t", tab)
  end
  local count = vim.v.foldend - vim.v.foldstart + 1
  chunks[#chunks + 1] = { " ⋯ ", "UiFoldCount" }
  chunks[#chunks + 1] = { "󰁂 " .. count .. " lines ", "UiFoldCount" }
  return chunks
end

return M
