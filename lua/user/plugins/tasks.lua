local project = require("user.core.project")

local function task_belongs_to(task, root)
	local owner = task.metadata and task.metadata.user_project_root
	if owner then
		return project.canonical(owner) == root
	end
	return type(task.cwd) == "string" and project.contains(root, task.cwd)
end

local function restart_last_task()
	local overseer = require("overseer")
	local root = project.root()
	local tasks = overseer.list_tasks({
		status = {
			overseer.STATUS.SUCCESS,
			overseer.STATUS.FAILURE,
			overseer.STATUS.CANCELED,
		},
		filter = function(task)
			return task_belongs_to(task, root)
		end,
		sort = function(left, right)
			local left_end, right_end = left.time_end or 0, right.time_end or 0
			if left_end ~= right_end then
				return left_end > right_end
			end
			local left_start, right_start = left.time_start or 0, right.time_start or 0
			if left_start ~= right_start then
				return left_start > right_start
			end
			return left.id > right.id
		end,
	})

	if vim.tbl_isempty(tasks) then
		vim.notify("No completed tasks in " .. vim.fn.fnamemodify(root, ":~"), vim.log.levels.WARN)
		return
	end

	overseer.run_action(tasks[1], "restart")
end

local function run_workspace_task(command)
	local overseer = require("overseer")
	local root = project.root()
	local name, tags = nil, {}
	for _, argument in ipairs(command.fargs) do
		if overseer.TAG:contains(argument) then
			table.insert(tags, argument)
		elseif name then
			vim.notify("Provide one task template name, or task tags", vim.log.levels.WARN)
			return
		else
			name = argument
		end
	end
	if name and #tags > 0 then
		vim.notify("Choose a task template name or task tags", vim.log.levels.WARN)
		return
	end
	overseer.run_task({
		name = name,
		tags = tags,
		search_params = { dir = root, filetype = vim.bo.filetype },
		on_build = function(definition)
			-- A template can deliberately run inside a package or build directory.
			-- Resolve relative paths before another prompt or tab change alters cwd.
			local cwd = definition.cwd
			if cwd and cwd ~= "" then
				if not cwd:match("^[/\\]") and not cwd:match("^%a:[/\\]") and cwd ~= "~" and cwd:sub(1, 2) ~= "~/" then
					cwd = vim.fs.joinpath(root, cwd)
				end
				definition.cwd = project.canonical(cwd)
			else
				definition.cwd = root
			end
			definition.metadata = vim.tbl_extend("force", definition.metadata or {}, { user_project_root = root })
		end,
	}, function(_, err)
		if err then
			vim.notify(err, vim.log.levels.ERROR, { title = "Task" })
		end
	end)
end

local function run_workspace_shell(command)
	local root = project.root()
	local function run(cmd)
		if not cmd or not cmd:find("%S") then
			return
		end
		local task = require("overseer").new_task({
			cmd = cmd,
			cwd = root,
			metadata = { user_project_root = root },
		})
		if not command.bang then
			task:start()
		end
	end
	if command.args ~= "" then
		run(command.args)
	else
		vim.ui.input({ prompt = "Task command", completion = "shellcmdline" }, run)
	end
end

return {
	{
		"stevearc/overseer.nvim",
		cmd = {
			"OverseerRun",
			"OverseerToggle",
			"OverseerOpen",
			"OverseerClose",
			"OverseerTaskAction",
			"OverseerShell",
			"OverseerRestartLast",
		},
		opts = {},
		config = function(_, opts)
			require("overseer").setup(opts)
			vim.api.nvim_create_user_command("OverseerRun", run_workspace_task, {
				nargs = "*",
				desc = "Run a task in the current workspace",
			})
			vim.api.nvim_create_user_command("OverseerShell", run_workspace_shell, {
				nargs = "*",
				bang = true,
				complete = "shellcmdline",
				desc = "Run a shell task in the current workspace; ! creates it without starting",
			})

			vim.api.nvim_create_user_command("OverseerRestartLast", restart_last_task, {
				desc = "Restart the most recent completed task in the current workspace",
			})
		end,
		keys = {
			{ "<leader>jr", "<cmd>OverseerRun<cr>", desc = "Run task" },
			{ "<leader>jt", "<cmd>OverseerToggle<cr>", desc = "Toggle task list" },
			{ "<leader>jo", "<cmd>OverseerOpen<cr>", desc = "Open task list" },
			{ "<leader>jc", "<cmd>OverseerClose<cr>", desc = "Close task list" },
			{ "<leader>ja", "<cmd>OverseerTaskAction<cr>", desc = "Task action" },
			{ "<leader>jR", "<cmd>OverseerRestartLast<cr>", desc = "Restart last task" },
			{ "<leader>js", "<cmd>OverseerShell<cr>", desc = "Shell task" },
		},
	},
}
