-- Neovim 0.12's Lua markdown ftplugin replaces the old normal-mode heading
-- motions, but not their visual-mode counterparts. The legacy Vimscript maps
-- are disabled globally to avoid duplicate undo entries during FileType replay,
-- so restore visual selection-to-heading using the public search API.
if vim.g.no_markdown_maps ~= 1 then
	return
end

local function select_to_heading(count)
	vim.cmd("normal! gv")
	local flags = count < 0 and "bW" or "W"
	local pattern = [[\%(^#\{1,6\}\s\+\S\|^\S.*\n^[=-]\+\s*$\)]]
	for _ = 1, math.abs(count) do
		vim.fn.search(pattern, flags)
	end
end

vim.keymap.set("x", "]]", function()
	select_to_heading(1)
end, { buffer = true, desc = "Select to next heading" })

vim.keymap.set("x", "[[", function()
	select_to_heading(-1)
end, { buffer = true, desc = "Select to previous heading" })

vim.b.undo_ftplugin = (vim.b.undo_ftplugin or "")
	.. "\n lua pcall(vim.keymap.del, 'x', ']]', { buffer = true });"
	.. " pcall(vim.keymap.del, 'x', '[[', { buffer = true })"
