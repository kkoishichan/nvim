return function(base)
	local document = base .. "/documents"
	local function wait_for(predicate, message)
		assert(vim.wait(30000, predicate, 25), message)
	end
	local function command(args, expected)
		local result = vim.system(args, { cwd = document, text = true }):wait(30000)
		assert(
			expected == "failure" and result.code ~= 0 and result.code ~= 124
				or expected ~= "failure" and result.code == 0,
			table.concat(args, " ") .. "\n" .. (result.stdout or "") .. (result.stderr or "")
		)
		return (result.stdout or "") .. (result.stderr or "")
	end
	for _, tool in ipairs({ "typst", "latexmk", "pdflatex", "pdfinfo", "pdftoppm" }) do
		assert(vim.fn.executable(tool) == 1, "Document workflow requires " .. tool)
	end
	local notify, messages = vim.notify, {}
	vim.notify = function(message, level, options)
		table.insert(messages, tostring(message))
		return notify(message, level, options)
	end
	local function saw(text)
		for _, message in ipairs(messages) do
			if message:find(text, 1, true) then
				return true
			end
		end
		return false
	end
	require("user.core.project").set(document)
	vim.cmd.edit(document .. "/main.typ")
	local typst_buffer = vim.api.nvim_get_current_buf()
	assert(not package.loaded["typst-preview"], "Opening a Typst file loaded the network-dependent preview")
	vim.cmd.TypstCompilePdf()
	wait_for(function()
		return saw("Wrote")
	end, "The Typst editor command did not finish")
	assert(command({ "pdfinfo", document .. "/main.pdf" }):match("Pages:%s+1"), "Typst did not produce a one-page PDF")
	command({
		"pdftoppm",
		"-f",
		"1",
		"-singlefile",
		"-scale-to",
		"320",
		"-png",
		document .. "/main.pdf",
		document .. "/before",
	})
	local before = vim.fn.sha256(table.concat(vim.fn.readfile(document .. "/before.png", "b"), "\n"))
	vim.cmd.edit(document .. "/main.pdf")
	local pdf_buffer = vim.api.nvim_get_current_buf()
	wait_for(function()
		return vim.b[pdf_buffer].pdf_preview_pages == 1
	end, "PDF buffer did not read the actual page count")
	vim.api.nvim_set_current_buf(typst_buffer)
	vim.api.nvim_buf_set_lines(typst_buffer, 0, -1, false, {
		"#set page(width: 12cm, height: 8cm)",
		"= Updated first page",
		"The content changed.",
		"#pagebreak()",
		"= Second page",
	})
	messages = {}
	vim.cmd.TypstCompilePdf()
	wait_for(function()
		return saw("Wrote") and vim.b[pdf_buffer].pdf_preview_pages == 2
	end, "PDF watcher did not detect the rebuilt document")
	command({
		"pdftoppm",
		"-f",
		"1",
		"-singlefile",
		"-scale-to",
		"320",
		"-png",
		document .. "/main.pdf",
		document .. "/after",
	})
	local after = vim.fn.sha256(table.concat(vim.fn.readfile(document .. "/after.png", "b"), "\n"))
	assert(before ~= after, "Rebuilding the document did not change the rendered page")
	assert(vim.b[pdf_buffer].pdf_preview_file == document .. "/main.pdf", "PDF preview changed its source")
	print("Document workflow: Typst editor build, real PDF raster, watcher refresh passed")
	vim.api.nvim_set_current_buf(typst_buffer)
	vim.api.nvim_buf_set_lines(typst_buffer, 0, -1, false, { "= Invalid document", "", "#let broken = (" })
	messages = {}
	vim.cmd.TypstCompilePdf()
	wait_for(function()
		return saw("Build failed")
	end, "Typst failure was not reported")
	local quickfix = vim.fn.getqflist({ items = 1, title = 1 })
	assert(quickfix.title == "Typst PDF" and #quickfix.items > 0, "Typst failure did not populate quickfix")
	assert(
		vim.iter(quickfix.items):any(function(item)
			return item.text:find("error", 1, true) ~= nil
				and item.lnum == 3
				and vim.api.nvim_buf_get_name(item.bufnr) == document .. "/main.typ"
		end),
		"Typst quickfix did not identify the actual compiler error at line 3"
	)
	vim.cmd.cclose()
	local path = vim.env.PATH
	vim.fn.mkdir(base .. "/empty-bin", "p")
	vim.env.PATH = base .. "/empty-bin"
	vim.api.nvim_set_current_buf(typst_buffer)
	messages = {}
	pcall(vim.cmd.TypstCompilePdf)
	assert(saw("Missing executable: typst"), "Missing Typst did not produce a useful error")
	pcall(vim.cmd.PdfOpen, { args = { document .. "/main.pdf" } })
	assert(saw("Missing a system PDF opener"), "Missing PDF viewer did not produce a useful error")
	vim.env.PATH = path
	print("Document workflow: Typst error output and missing-tool handling passed")
	vim.api.nvim_buf_delete(pdf_buffer, { force = true })
	-- The compiler is real; only automatic external viewer launch is disabled.
	vim.g.vimtex_view_automatic = 0
	vim.cmd.edit(document .. "/main.tex")
	local tex_buffer = vim.api.nvim_get_current_buf()
	local compiled
	local group = vim.api.nvim_create_augroup("java_documents_workflow", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "VimtexEventCompileSuccess", "VimtexEventCompileFailed" },
		callback = function(event)
			compiled = event.match
		end,
	})
	vim.cmd.VimtexCompileSS()
	wait_for(function()
		return compiled ~= nil
	end, "VimTeX single-shot compile did not finish")
	assert(compiled == "VimtexEventCompileSuccess", "VimTeX did not compile the valid document")
	assert(command({ "pdfinfo", document .. "/main.pdf" }):match("Pages:%s+1"), "LaTeX did not produce a PDF")
	vim.api.nvim_buf_set_lines(tex_buffer, 2, 3, false, { "\\undefinedWorkflowCommand" })
	vim.cmd.write()
	compiled = nil
	vim.cmd.VimtexCompileSS()
	wait_for(function()
		return compiled ~= nil
	end, "VimTeX invalid-document compile did not finish")
	assert(compiled == "VimtexEventCompileFailed", "VimTeX did not report the invalid LaTeX command")
	vim.cmd.VimtexErrors()
	local tex_errors = vim.fn.getqflist()
	assert(
		vim.iter(tex_errors):any(function(item)
			return item.valid == 1 and item.lnum == 3
		end),
		"LaTeX error did not identify its source line"
	)
	vim.cmd.cclose()
	vim.cmd.VimtexStop()
	vim.api.nvim_del_augroup_by_id(group)
	vim.notify = notify
	print("Document workflow: actual VimTeX success/failure and error location passed")
end
