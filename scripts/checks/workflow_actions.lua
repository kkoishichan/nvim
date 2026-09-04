return function(tmp)
	local project = require("user.core.project")
	local workflows = require("user.core.workflows")
	local policy = require("user.core.format_policy")
	local base = tmp .. "/workspace with spaces"
	local other = tmp .. "/other workspace"
	local package = base .. "/packages/web"
	local function write(path, lines)
		vim.fn.mkdir(vim.fs.dirname(path), "p")
		vim.fn.writefile(lines, path)
	end
	vim.fn.mkdir(base .. "/.git", "p")
	vim.fn.mkdir(other .. "/.git", "p")
	write(package .. "/package.json", { '{"scripts":{"dev":"node dev.js","start":"node app.js"}}' })
	write(package .. "/app.js", { "console.log(42)" })
	vim.cmd("noautocmd edit " .. vim.fn.fnameescape(package .. "/app.js"))
	project.set(base)
	local input, choose = vim.ui.select, nil
	vim.ui.select = function(items, _, callback)
		choose = function()
			callback(items[1])
		end
	end
	local start, captured = workflows.start, nil
	workflows.start = function(definition)
		captured = definition
	end
	workflows.run("run")
	project.set(other)
	assert(choose, "Multiple script tasks should present a choice")
	choose()
	assert(captured.cwd == package and captured.metadata.user_project_root == base, "Deferred task changed project")
	workflows.start, vim.ui.select = start, input
	write(other .. "/Cargo.toml", { "[package]", 'name = "other"', 'version = "0.1.0"' })
	local selected = workflows.discover("build")
	assert(#selected == 1 and selected[1].cwd == other, "Explicit workspace did not override an unrelated file")

	-- Run real processes through Overseer and inspect its result/quickfix data.
	local script = base .. "/check.sh"
	local source = base .. "/broken.c"
	write(source, { "int main() {", "broken", "}" })
	write(script, { "#!/bin/sh", "printf 'broken.c:2:1: fixture failure\\n'", "exit 3" })
	local task = workflows.start({
		name = "Workflow failure fixture",
		cmd = vim.fn.exepath("sh"),
		args = { script },
		cwd = base,
		metadata = { user_project_root = base },
		errorformat = "%f:%l:%c: %m",
		components = { { "on_output_quickfix", tail = false }, "default" },
	})
	assert(
		vim.wait(5000, function()
			return task:is_complete()
		end, 20),
		"Task did not finish"
	)
	assert(task.status == "FAILURE", "Task failure was reported as success")
	local entries = vim.fn.getqflist()
	local diagnostic = vim.tbl_filter(function(item)
		return item.valid == 1
	end, entries)[1]
	assert(diagnostic and diagnostic.lnum == 2, "Build error location is missing")
	assert(vim.api.nvim_buf_get_name(diagnostic.bufnr) == source, "Quickfix used another project's directory")
	write(script, { "#!/bin/sh", "printf 'fixture passed\\n'", "exit 0" })
	require("overseer").run_action(task, "restart")
	assert(vim.wait(5000, function()
		return task:is_complete()
	end, 20) and task.status == "SUCCESS", "Task retry failed")
	local notify, warnings = vim.notify, {}
	vim.notify = function(message)
		warnings[#warnings + 1] = message
	end
	assert(not workflows.start({ cmd = base .. "/not-installed" }), "Missing task tool should not start")
	vim.notify = notify
	assert(warnings[1]:find("Missing task executable", 1, true), "Missing task tool has no explanation")

	-- An Assembly file in a Go repo is not automatically Go assembly.
	write(base .. "/go.mod", { "module fixture" })
	local assembly = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(assembly, base .. "/example.s")
	vim.api.nvim_buf_set_lines(assembly, 0, -1, false, { ".globl main", "main:", "  ret" })
	assert(not policy.go_assembly(nil, { buf = assembly }), "GNU assembly was given to the Plan 9 formatter")
	vim.api.nvim_buf_set_lines(assembly, 0, -1, false, { "TEXT ·add(SB),NOSPLIT,$0-8", "RET" })
	assert(policy.go_assembly(nil, { buf = assembly }), "Go assembly dialect was not detected")
	vim.b[assembly].user_go_asm = false
	assert(not policy.go_assembly(nil, { buf = assembly }), "Assembly override ignored")
	vim.api.nvim_buf_delete(assembly, { force = true })

	-- Exercise real save hooks, timeout cancellation and async edit protection.
	local conform = require("conform")
	local file = base .. "/save.txt"
	write(file, { "original" })
	vim.cmd("noautocmd edit " .. vim.fn.fnameescape(file))
	vim.bo.filetype = "workflow_save"
	-- Suppress headless message-display delays while measuring save hooks.
	local first_save = vim.uv.hrtime()
	vim.cmd("silent write")
	print(("First save hook setup: %.1f ms"):format((vim.uv.hrtime() - first_save) / 1e6))
	conform.formatters.workflow_slow = {
		command = vim.fn.exepath("sh"),
		args = { "-c", "sleep 1.2; printf 'formatted\\n'" },
		stdin = true,
	}
	conform.formatters_by_ft.workflow_save = { "workflow_slow" }
	local begun = vim.uv.hrtime()
	vim.cmd("silent write")
	local elapsed = (vim.uv.hrtime() - begun) / 1e6
	assert(elapsed < 1150, "Save exceeded the automatic formatting budget: " .. elapsed)
	assert(vim.fn.readfile(file)[1] == "original", "Timed out formatter modified the saved file")
	print(("Save timeout fixture: %.1f ms (800 ms budget)"):format(elapsed))
	conform.formatters_by_ft.tex = { "workflow_slow" }
	vim.cmd("noautocmd setlocal filetype=tex")
	begun = vim.uv.hrtime()
	vim.cmd("silent write")
	elapsed = (vim.uv.hrtime() - begun) / 1e6
	assert(elapsed < 300, "TeX save blocked on formatter: " .. elapsed)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "new unsaved edit" })
	vim.wait(1500, function()
		return false
	end, 50)
	assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "new unsaved edit", "Async format overwrote a newer edit")
	assert(vim.fn.readfile(file)[1] == "original", "Async format rewrote disk despite a newer edit")
	vim.bo.modified = false
	print(("TeX async save fixture: %.1f ms; newer edit preserved"):format(elapsed))
end
