return {
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			local lint = require("lint")
			local function parse_verible(output, bufnr, linter_cwd)
				local diagnostics = {}
				local buffer_path = vim.fs.normalize(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"))
				local cwd = linter_cwd or vim.fn.getcwd()

				for line in vim.gsplit(output, "\n", { plain = true, trimempty = true }) do
					local file, lnum, col, end_col, message = line:match("^(.-):(%d+):(%d+)%-(%d+):%s*(.+)$")
					if not file then
						file, lnum, col, message = line:match("^(.-):(%d+):(%d+):%s*(.+)$")
					end

					if file then
						local path = file:match("^/") and file or vim.fs.joinpath(cwd, file)
						path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

						if path == buffer_path then
							local severity = message:find("syntax error", 1, true) and vim.diagnostic.severity.ERROR
								or vim.diagnostic.severity.WARN

							table.insert(diagnostics, {
								source = "verible",
								lnum = math.max(tonumber(lnum) - 1, 0),
								col = math.max(tonumber(col) - 1, 0),
								end_lnum = math.max(tonumber(lnum) - 1, 0),
								end_col = end_col and math.max(tonumber(end_col), 0) or math.max(tonumber(col), 0),
								severity = severity,
								message = message,
							})
						end
					end
				end

				return diagnostics
			end

			lint.linters.verible = {
				cmd = "verible-verilog-lint",
				args = { "--rules_config_search" },
				stdin = false,
				ignore_exitcode = true,
				parser = parse_verible,
			}

			lint.linters_by_ft = {
				cmake = { "cmakelint" },
				css = { "stylelint" },
				dockerfile = { "hadolint" },
				go = { "golangcilint" },
				lua = { "selene" },
				make = { "checkmake" },
				markdown = { "markdownlint-cli2" },
				sh = { "shellcheck" },
				sql = { "sqruff" },
				systemverilog = { "verible" },
				verilog = { "verible" },
				yaml = { "yamllint" },
				zsh = { "shellcheck" },
			}

			local function available_linters(names)
				local available = {}
				for _, name in ipairs(names or {}) do
					local linter = lint.linters[name]
					if linter then
						local cmd = linter.cmd
						if type(cmd) == "function" then
							cmd = cmd()
						end
						if cmd and vim.fn.executable(cmd) == 1 then
							table.insert(available, name)
						end
					end
				end
				return available
			end

			local function try_lint()
				if vim.b.bigfile then
					return
				end

				local names = available_linters(lint.linters_by_ft[vim.bo.filetype])
				if #names > 0 then
					lint.try_lint(names)
				end
			end

			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = vim.api.nvim_create_augroup("user_lint", { clear = true }),
				callback = try_lint,
			})

			vim.keymap.set("n", "<leader>cl", try_lint, { desc = "Lint" })
		end,
	},
}
