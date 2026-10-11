-- What the tab bar lists and when it shows. Tabs are workspaces here (one
-- project root per tab page), so the bar answers "which files of this
-- workspace are open": buffers that belong to another tab's workspace are
-- left out, buffers that belong to no workspace stay with the tab that has
-- them, and one file alone needs no bar.
local M = {}

local function project()
	return require("user.core.project")
end

---Whether a listed buffer belongs to the current tab's workspace.
---@param bufnr integer
---@return boolean
function M.belongs(bufnr)
	local root = project().root()
	local bound = vim.b[bufnr].user_project_root
	if bound then
		return project().canonical(bound) == project().canonical(root)
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" or project().contains(root, name) then
		return true
	end
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local other = vim.t[tab].user_project_root
		if other and project().contains(other, name) then
			return false
		end
	end
	return true
end

---Listed buffers of the current workspace.
---@return integer
function M.count()
	local count = 0
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		if M.belongs(info.bufnr) then
			count = count + 1
		end
	end
	return count
end

---The workspace name, with the tab position when there are several tabs.
---@return string
function M.label()
	local label = vim.fs.basename(project().root())
	local tabs = vim.api.nvim_list_tabpages()
	if #tabs > 1 then
		label = ("%s %d/%d"):format(label, vim.api.nvim_tabpage_get_number(0), #tabs)
	end
	return label
end

---Show the bar only when this workspace has more than one listed buffer.
function M.apply()
	local status = M.count() > 1 and 2 or 0
	if vim.o.showtabline ~= status then
		vim.o.showtabline = status
	end
	vim.cmd.redrawtabline()
end

---Keep the bar's visibility and content in step with buffers and workspaces.
---:Cd / :ProjectPick change the workspace without touching any buffer.
function M.setup()
	vim.api.nvim_create_autocmd(
		{ "BufAdd", "BufDelete", "BufWipeout", "BufFilePost", "OptionSet", "TabEnter", "DirChanged" },
		{
			group = vim.api.nvim_create_augroup("user_tabbar", { clear = true }),
			callback = function(event)
				if event.event == "OptionSet" and event.match ~= "buflisted" then
					return
				end
				vim.schedule(M.apply)
			end,
		}
	)
	M.apply()
end

return M
