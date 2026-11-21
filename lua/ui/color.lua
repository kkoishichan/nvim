-- 颜色工具：读取高亮、混合颜色
local M = {}

local function rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

---按 alpha 比例把 fg 混入 bg（alpha = fg 的权重）
---@param fg string
---@param bg string
---@param alpha number
function M.blend(fg, bg, alpha)
  local r1, g1, b1 = rgb(fg)
  local r2, g2, b2 = rgb(bg)
  local function ch(a, b)
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end
  return string.format("#%02x%02x%02x", ch(r1, r2), ch(g1, g2), ch(b1, b2))
end

function M.luminance(hex)
  local r, g, b = rgb(hex)
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255
end

---读取高亮组的某个颜色属性（解析 link），返回 "#rrggbb" 或 nil
function M.hl(name, attr)
  local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and h[attr] then
    return string.format("#%06x", h[attr])
  end
end

---按顺序尝试多个高亮组，返回第一个存在的颜色
function M.first(attr, ...)
  for _, name in ipairs({ ... }) do
    local c = M.hl(name, attr)
    if c then
      return c
    end
  end
end

return M
