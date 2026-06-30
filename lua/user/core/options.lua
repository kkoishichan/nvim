vim.filetype.add({
	extension = {
		asm = "riscv",
		riscv = "riscv",
		s = "riscv",
		S = "riscv",
		v = "verilog",
		vh = "verilog",
	},
})

vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")

local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
local path_sep = vim.fn.has("win32") == 1 and ";" or ":"
local path = vim.env.PATH or ""
local in_path = false

for _, entry in ipairs(vim.split(path, path_sep, { plain = true, trimempty = true })) do
	if entry == mason_bin then
		in_path = true
		break
	end
end

if not in_path then
	vim.env.PATH = mason_bin .. path_sep .. path
end

local opt = vim.opt

opt.autowrite = true
opt.autoread = true
opt.breakindent = true
opt.clipboard = "unnamedplus"
opt.completeopt = { "menu", "menuone", "noselect" }
opt.confirm = true
opt.cursorline = true
opt.expandtab = true
opt.foldenable = true
opt.foldcolumn = "1"
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
opt.showtabline = 2
opt.sidescrolloff = 8
opt.signcolumn = "yes"
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
opt.wrap = false

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
