return function(tmp)
	do
		local toolchain = require("user.toolchain")
		local seen = {}
		for _, package in ipairs(toolchain.packages) do
			assert(type(package[1]) == "string" and package[1] ~= "", "invalid Mason package name")
			assert(type(package.version) == "string" and package.version ~= "", "missing tool pin: " .. package[1])
			assert(not seen[package[1]], "duplicate tool pin: " .. package[1])
			seen[package[1]] = true
			assert(toolchain.version(package[1]) == package.version, "tool pin lookup is inconsistent: " .. package[1])
		end

		seen = {}
		for _, server in ipairs(toolchain.lsp_servers) do
			assert(type(server) == "string" and server ~= "", "invalid LSP server name")
			assert(not seen[server], "duplicate LSP server: " .. server)
			seen[server] = true
		end

		local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
		local latexindent_candidates = vim.fn.has("win32") == 1
				and { "latexindent.cmd", "latexindent.exe", "latexindent.bat", "latexindent" }
			or { "latexindent" }
		local mason_latexindent
		for _, candidate in ipairs(latexindent_candidates) do
			local executable = vim.fs.joinpath(mason_bin, candidate)
			if vim.fn.executable(executable) == 1 then
				mason_latexindent = executable
				break
			end
		end
		if mason_latexindent then
			assert(
				toolchain.executable("latexindent", { prefer_mason = true }) == mason_latexindent,
				"latexindent did not prefer Mason's self-contained executable"
			)
			local result = vim.system({ mason_latexindent, "--version" }, { text = true }):wait(5000)
			assert(result.code == 0, "Mason's latexindent executable is not runnable: " .. (result.stderr or ""))

			require("lazy").load({ plugins = { "conform.nvim" } })
			local buffer = vim.api.nvim_create_buf(false, false)
			vim.api.nvim_buf_set_name(buffer, vim.fs.joinpath(tmp, "latexindent-audit.tex"))
			vim.bo[buffer].filetype = "tex"
			local format_err, formatted = require("conform").format_lines({ "latexindent" }, {
				"\\begin{itemize}",
				"\\item outer",
				"\\begin{itemize}",
				"\\item inner",
				"\\end{itemize}",
				"\\end{itemize}",
			}, { bufnr = buffer, timeout_ms = 10000, quiet = true })
			assert(not format_err and formatted, "latexindent formatting failed: " .. tostring(format_err))
			assert(
				vim.uv.fs_stat(vim.fs.joinpath(vim.fn.stdpath("cache"), "latexindent", "indent.log")),
				"latexindent log was not redirected to Neovim's cache"
			)
			vim.api.nvim_buf_delete(buffer, { force = true })
		end
	end
end
