return {
	{
		"yaadata/codex.nvim",
		url = "https://codeberg.org/yaadata/codex.nvim.git",
		version = "1.0.0",
		cmd = {
			"Codex",
			"CodexFocus",
			"CodexClose",
			"CodexClearInput",
			"CodexSendSelection",
			"CodexSendFile",
			"CodexMentionFile",
			"CodexMentionDirectory",
			"CodexResume",
		},
		opts = {
			launch = {
				auto_start = false,
			},
			terminal = {
				provider = "native",
				auto_close = true,
				provider_opts = {
					native = {
						window = "vsplit",
						vsplit = {
							side = "right",
							size_pct = 40,
						},
					},
				},
			},
		},
		config = function(_, opts)
			-- codex.nvim 1.0.0 still validates its setup table with the removed
			-- `vim.validate({ ... })` form. Keep the compatibility scope strictly
			-- around setup so the rest of Neovim always sees the modern API.
			local modern_validate = vim.validate
			local type_alias = { b = "boolean", f = "function", n = "number", s = "string", t = "table" }
			vim.validate = function(name, value, validator, optional, message)
				if type(name) ~= "table" then
					return modern_validate(name, value, validator, optional, message)
				end
				for field, spec in pairs(name) do
					local expected = type(spec[2]) == "string" and (type_alias[spec[2]] or spec[2]) or spec[2]
					modern_validate(field, spec[1], expected, spec[3], spec[4])
				end
			end

			local ok, err = xpcall(function()
				require("codex").setup(opts)
			end, debug.traceback)
			vim.validate = modern_validate
			if not ok then
				error(err)
			end
		end,
	},
}
