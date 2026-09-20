-- nvim-lspconfig as an explicit language-capability extension. In a mode
-- without automatic language servers it is installed but never loaded at
-- startup: :FastLspStart puts it on the runtimepath, which is all
-- vim.lsp.config needs to resolve a server definition by name.
return function()
	return {
		{
			"neovim/nvim-lspconfig",
			lazy = true,
		},
	}
end
