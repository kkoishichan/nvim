local M = {}

function M.setup()
	local group = vim.api.nvim_create_augroup("user_oil_registration", { clear = true })
	-- Preserve Oil's default explorer ownership before its implementation loads.
	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1
	if package.loaded.oil then
		return
	end

	local function open_directory(bufnr)
		if package.loaded.oil then
			vim.api.nvim_del_augroup_by_id(group)
			return
		end
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end
		local name = vim.api.nvim_buf_get_name(bufnr)
		local scheme = name:match("^(oil[%w-]*)://")
		local oil_uri = scheme == "oil" or scheme == "oil-ssh" or scheme == "oil-trash" or scheme == "oil-s3"
		if not oil_uri then
			if name == "" or name:match("^%w[%w+.-]*://") or vim.bo[bufnr].buftype ~= "" then
				return
			end
			local stat = vim.uv.fs_stat(name)
			if not stat or stat.type ~= "directory" then
				return
			end
		end
		vim.api.nvim_del_augroup_by_id(group)
		require("lazy").load({ plugins = { "oil.nvim" } })
		-- BufAdd runs before leaving the original file, so Oil can record its
		-- view and alternate buffer. Replay only Oil's directory hijacker: opening
		-- the directory ourselves would incorrectly display a hidden :badd buffer.
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_exec_autocmds("BufAdd", { group = "Oil", buffer = bufnr, modeline = false })
		end
	end

	-- Legacy sessions recreate unlisted Oil buffers with :enew followed by
	-- :file, rather than reading the URI. BufFilePost loads Oil in time for its
	-- native SessionLoadPost handler to initialize those buffers.
	vim.api.nvim_create_autocmd({ "BufAdd", "BufFilePost" }, {
		group = group,
		nested = true,
		desc = "Load Oil before entering the first directory buffer",
		callback = function(event)
			open_directory(event.buf)
		end,
	})
	-- Argument and session buffers can exist before plugin init registers BufAdd.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		open_directory(bufnr)
		if package.loaded.oil then
			break
		end
	end
end

return M
