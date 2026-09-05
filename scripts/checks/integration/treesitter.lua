return function()
	do
		local config = require("user.core.treesitter")
		local available = {}
		for _, parser in ipairs(require("nvim-treesitter").get_available()) do
			available[parser] = true
		end

		local configured = {}
		for _, parser in ipairs(config.parsers) do
			assert(not configured[parser], "duplicate Tree-sitter parser: " .. parser)
			assert(available[parser], "unknown Tree-sitter parser: " .. parser)
			assert(vim.treesitter.language.add(parser), "Tree-sitter parser is not installed or loadable: " .. parser)
			configured[parser] = true
		end

		local filetypes = {}
		for _, filetype in ipairs(config.filetypes) do
			assert(not filetypes[filetype], "duplicate Tree-sitter filetype: " .. filetype)
			filetypes[filetype] = true
			local parser = vim.treesitter.language.get_lang(filetype)
			assert(
				configured[parser],
				("Tree-sitter filetype %s maps to unconfigured parser %s"):format(filetype, parser)
			)
		end
	end
end
