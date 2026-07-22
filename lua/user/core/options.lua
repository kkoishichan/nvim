-- Neovim 0.12 also supplies Tree-sitter markdown motions in markdown.lua.
-- Disable the older Vimscript copies so FileType replay cannot append duplicate
-- unmap commands to b:undo_ftplugin (which otherwise leaves E31 in v:errmsg).
if #vim.api.nvim_get_runtime_file("ftplugin/markdown.lua", false) > 0 then
	vim.g.no_markdown_maps = 1
end

vim.filetype.add({
	extension = {
		riscv = "riscv",
		vh = "verilog",
	},
})

local opt = vim.opt

opt.autowrite = false
opt.autoread = true
opt.breakindent = true
opt.clipboard = "unnamedplus"
opt.completeopt = { "menu", "menuone", "noselect" }
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.foldenable = true
opt.foldcolumn = "auto:1"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldmethod = "manual"
opt.foldtext = ""
opt.ignorecase = true
opt.inccommand = "split"
opt.laststatus = 3
opt.linebreak = true
opt.list = true
opt.listchars = { tab = "> ", trail = ".", nbsp = "+" }
opt.mouse = "a"
opt.number = true
opt.pumblend = 0
opt.pumheight = 12
opt.relativenumber = true
opt.scrolloff = 8
opt.shiftround = true
opt.shiftwidth = 2
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.showmode = false
opt.sidescrolloff = 8
opt.signcolumn = "yes"
-- IDE-like gutter order: action/diagnostic signs, hybrid line number, fold
-- control, then a dedicated Git change lane directly beside the source text.
opt.statuscolumn = [[%s%=%l%C%{%v:lua.require("user.core.statuscolumn").git()%}]]
opt.smartcase = true
opt.smartindent = true
opt.spelllang = { "en", "cjk" }
opt.spelloptions = "camel"
opt.splitbelow = true
opt.splitkeep = "screen"
opt.splitright = true
opt.tabstop = 2
opt.termguicolors = true
opt.timeoutlen = 400
opt.undofile = true
opt.updatetime = 250
opt.virtualedit = "block"
opt.winborder = "rounded"
opt.wrap = false

-- Do not persist copied register contents in ShaDa. Sensitive buffers also
-- disable disk-backed undo/swap and expire an unchanged system clipboard.
opt.shada = "!,'100,<0,s10,h,r/tmp/,r/private/"

opt.fillchars = {
	eob = " ",
	fold = " ",
	foldclose = "",
	foldinner = " ",
	foldopen = "",
	foldsep = " ",
}

vim.g.markdown_recommended_style = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
