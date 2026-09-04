local M = {}
local project = require("user.core.project")
local toolchain = require("user.toolchain")

local function exists(root, name)
	return vim.uv.fs_stat(vim.fs.joinpath(root, name)) ~= nil
end

-- Definitions capture file, cwd and owner before a picker can change context.
function M.discover(action, source)
	local context = project.context(source)
	local root, file = context.language_root, context.file
	if context.explicit and not project.contains(context.root, file) then
		root, file = context.root, nil
	end
	local definitions = {}
	local function add(label, command, args, cwd)
		definitions[#definitions + 1] = {
			name = label,
			cmd = command,
			args = args,
			cwd = cwd or root,
			metadata = { user_project_root = context.root },
			errorformat = "%f:%l:%c: %m,%f:%l: %m,%-G%.%#",
			components = {
				{ "on_output_quickfix", open_on_exit = "failure", tail = false, open_height = 8 },
				"default",
			},
		}
	end
	local function runtime(name)
		return toolchain.executable(name, { path = file or root }) or name
	end
	if exists(root, "package.json") then
		local ok, package = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(root, "package.json")), "\n"))
		end)
		if ok and type(package) == "table" and type(package.scripts) == "table" then
			local manager = type(package.packageManager) == "string" and package.packageManager:match("^(%w+)@")
			manager = manager
				or (exists(root, "pnpm-lock.yaml") and "pnpm")
				or (exists(root, "yarn.lock") and "yarn")
				or "npm"
			if not vim.tbl_contains({ "npm", "pnpm", "yarn", "bun" }, manager) then
				manager = "npm"
			end
			for _, name in ipairs(action == "run" and { "start", "dev" } or { action }) do
				if type(package.scripts[name]) == "string" then
					add(manager .. " run " .. name, runtime(manager), { "run", name })
				end
			end
		end
	end
	if exists(root, "Cargo.toml") then
		add("cargo " .. action, runtime("cargo"), { action })
	elseif exists(root, "go.mod") then
		add("go " .. action, runtime("go"), { action, action == "run" and "." or "./..." })
	elseif exists(root, "pom.xml") and action ~= "run" then
		local wrapper = vim.fs.joinpath(root, "mvnw")
		add("Maven " .. action, vim.fn.executable(wrapper) == 1 and wrapper or runtime("mvn"), {
			"--batch-mode",
			action == "build" and "package" or "test",
		})
	elseif (exists(root, "build.gradle") or exists(root, "build.gradle.kts")) and action ~= "run" then
		local wrapper = vim.fs.joinpath(root, "gradlew")
		add("Gradle " .. action, vim.fn.executable(wrapper) == 1 and wrapper or runtime("gradle"), {
			"--console=plain",
			action,
		})
	elseif exists(root, "CMakeLists.txt") and action ~= "run" then
		if action == "test" then
			add("CTest (build directory)", runtime("ctest"), { "--test-dir", "build", "--output-on-failure" })
		elseif exists(root, "build/CMakeCache.txt") then
			add("CMake build", runtime("cmake"), { "--build", "build" })
		else
			add("CMake configure (then run TaskBuild again)", runtime("cmake"), {
				"-S",
				".",
				"-B",
				"build",
				"-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
			})
		end
	elseif exists(root, "Makefile") and action ~= "run" then
		add("make " .. action, runtime("make"), action == "build" and {} or { "test" })
	end
	local ft = file and vim.filetype.match({ filename = file })
	if action == "test" and (ft == "python" or exists(root, "pyproject.toml") or exists(root, "pytest.ini")) then
		add("pytest", toolchain.python_executable(file) or "python3", { "-m", "pytest", "--tb=short", "-q" })
	elseif action == "run" and ft == "python" then
		add("Run Python file", toolchain.python_executable(file) or "python3", { file })
	elseif action == "run" and ft == "sh" then
		add("Run shell file", runtime("bash"), { file })
	elseif action == "build" and ft == "sh" then
		add("Check shell syntax", runtime("bash"), { "-n", file })
	elseif action == "build" and ft == "typst" then
		add(
			"Build Typst PDF",
			runtime("typst"),
			{ "compile", "--diagnostic-format", "short", "--root", context.root, file }
		)
	elseif action == "build" and (ft == "tex" or ft == "plaintex") then
		add(
			"Build LaTeX PDF",
			runtime("latexmk"),
			{ "-pdf", "-interaction=nonstopmode", "-halt-on-error", "-file-line-error", file },
			vim.fs.dirname(file)
		)
	end
	return definitions
end

function M.start(definition)
	if vim.fn.executable(definition.cmd) ~= 1 then
		vim.notify(
			"Missing task executable: " .. definition.cmd .. "; install it, then :ToolsRefresh",
			vim.log.levels.ERROR
		)
		return
	end
	local task = require("overseer").new_task(definition)
	task:start()
	return task
end

function M.run(action)
	local definitions = M.discover(action)
	if #definitions == 0 then
		vim.notify(
			"No " .. action .. " task found; use :OverseerRun or :OverseerShell for this project",
			vim.log.levels.INFO
		)
	elseif #definitions == 1 then
		M.start(definitions[1])
	else
		vim.ui.select(definitions, {
			prompt = "Project " .. action,
			format_item = function(item)
				return item.name .. " — " .. item.cwd
			end,
		}, function(definition)
			if definition then
				M.start(definition)
			end
		end)
	end
end

return M
