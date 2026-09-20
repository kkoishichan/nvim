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

local mode = require("user.core.mode")
local capabilities = mode.capabilities()
local opt = vim.opt

opt.autowrite = false
opt.autoread = true
opt.breakindent = true
-- Automatic unnamedplus synchronisation probes the desktop clipboard (or talks
-- to the remote end) on every yank. Fast mode keeps the ordinary registers and
-- leaves system copy to an explicit action.
opt.clipboard = capabilities.system_clipboard and "unnamedplus" or ""
opt.completeopt = { "menu", "menuone", "noselect" }
opt.confirm = true
opt.cursorline = capabilities.cursorline
opt.expandtab = true
opt.foldenable = true
-- Without a fold provider there is nothing to compute ranges, so the column
-- would only ever show manual folds the user created.
opt.foldcolumn = capabilities.folding_provider and "auto:1" or "0"
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
-- `blank` makes :mksession serialize visible plugin panels (neo-tree, outline,
-- etc.) as `enew | file <panel name>`. On restore those names become ordinary
-- file buffers because the plugin-specific buffer metadata is not persisted.
-- Keep real listed buffers, but leave transient/panel windows out of sessions.
opt.sessionoptions:remove("blank")
opt.shiftround = true
opt.shiftwidth = 2
opt.shortmess:append({ W = true, I = true, c = true, C = true })
opt.showmode = false
opt.sidescrolloff = 8
-- A permanently reserved sign column only pays for itself while something
-- publishes signs on every buffer.
opt.signcolumn = capabilities.git and "yes" or "auto"
if capabilities.git then
	-- IDE-like gutter order: action/diagnostic signs, hybrid line number, fold
	-- control, then a dedicated Git change lane directly beside the source text.
	require("user.core.statuscolumn")
	opt.statuscolumn = [[%s%=%l%C%{%v:lua.vim._user_statuscolumn_git()%}]]
end
if not capabilities.statusline_plugin then
	-- Native statusline: mode, file, modified flag and position, plus the mode
	-- badge so a fast session is obvious without running :ModeInfo.
	opt.statusline = require("user.core.statusline_basic").value(mode.is_fast() and "FAST" or nil)
end
opt.smartcase = true
opt.smartindent = true
opt.spelllang = { "en", "cjk" }
opt.spelloptions = "camel"
opt.splitbelow = true
opt.splitkeep = "screen"
opt.splitright = true
opt.tabstop = 2
-- Full mode assumes the desktop terminal it is configured for. A slim session
-- may be anywhere, so leave Neovim's own terminal detection to decide: a
-- connection without 24-bit colour degrades instead of drawing wrong colours.
if not mode.is_fast() then
	opt.termguicolors = true
end
opt.timeoutlen = 400
opt.undofile = capabilities.undofile
opt.updatetime = 250
opt.virtualedit = "block"
-- Default for application-sized or third-party panels. Small transient floats
-- are restyled window-locally by user.core.float_style.
opt.winborder = "rounded"
opt.wrap = false

-- Do not persist copied register contents in ShaDa. Sensitive buffers also
-- disable disk-backed undo/swap and expire an unchanged system clipboard.
opt.shada = "!,'100,<0,s10,h,r/tmp/,r/private/"

-- Swap, undo and ShaDa are recovery data, not caches. A host that points the
-- state directory at local disk gets all three there; a state directory that
-- cannot be used safely turns them off rather than failing on every write.
local storage = mode.storage()
if not storage.writable then
	opt.undofile = false
	opt.swapfile = false
	opt.shadafile = "NONE"
elseif storage.relocated then
	for _, directory in ipairs({ "undo", "swap", "view", "backup", "shada" }) do
		pcall(vim.fn.mkdir, vim.fs.joinpath(storage.path, directory), "p", tonumber("700", 8))
	end
	opt.undodir = vim.fs.joinpath(storage.path, "undo")
	opt.directory = vim.fs.joinpath(storage.path, "swap") .. "//"
	opt.viewdir = vim.fs.joinpath(storage.path, "view")
	opt.backupdir = vim.fs.joinpath(storage.path, "backup") .. "//"
	opt.shadafile = vim.fs.joinpath(storage.path, "shada", "main.shada")
end

opt.fillchars = {
	eob = " ",
	fold = " ",
	foldclose = capabilities.icons and "" or ">",
	foldinner = " ",
	foldopen = capabilities.icons and "" or "v",
	foldsep = " ",
}

vim.g.markdown_recommended_style = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
