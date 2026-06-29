local M = {}

-- Left sidebar is reserved for the tree (neo-tree); oil is a buffer-style
-- directory editor and opens full-window (in-place), not in a side panel.
M.left_panel_width = 34

function M.open_oil(path)
	require("oil").open(path or vim.fn.getcwd())
end

return M
