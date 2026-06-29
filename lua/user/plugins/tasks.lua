local function restart_last_task()
	local overseer = require("overseer")
	local task_list = require("overseer.task_list")
	local tasks = overseer.list_tasks({
		status = {
			overseer.STATUS.SUCCESS,
			overseer.STATUS.FAILURE,
			overseer.STATUS.CANCELED,
		},
		sort = task_list.sort_finished_recently,
	})

	if vim.tbl_isempty(tasks) then
		vim.notify("No tasks found", vim.log.levels.WARN)
		return
	end

	overseer.run_action(tasks[1], "restart")
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

			vim.api.nvim_create_user_command("OverseerRestartLast", restart_last_task, {
				desc = "Restart the most recent Overseer task",
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
