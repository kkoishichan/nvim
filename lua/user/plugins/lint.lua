return {
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			local lint = require("lint")
			local uv = vim.uv or vim.loop

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
				yaml = { "yamllint" },
				-- Verible diagnostics come from verible-verilog-ls. Running its CLI
				-- here as well only duplicates messages and analysis work.
				-- No zsh: shellcheck only supports sh/bash/dash/ksh.
			}

			local function buffer_dir(bufnr)
				local name = vim.api.nvim_buf_get_name(bufnr)
				if name == "" then
					return nil
				end
				return vim.fs.dirname(vim.fs.normalize(name))
			end

			local function find_upward(bufnr, markers)
				local dir = buffer_dir(bufnr)
				while dir do
					for _, marker in ipairs(markers) do
						if uv.fs_stat(vim.fs.joinpath(dir, marker)) then
							return dir
						end
					end

					local parent = vim.fs.dirname(dir)
					if not parent or parent == dir then
						break
					end
					dir = parent
				end
				return nil
			end

			local stylelint_markers = {
				".stylelintrc",
				".stylelintrc.cjs",
				".stylelintrc.js",
				".stylelintrc.json",
				".stylelintrc.mjs",
				".stylelintrc.yaml",
				".stylelintrc.yml",
				"stylelint.config.cjs",
				"stylelint.config.cts",
				"stylelint.config.js",
				"stylelint.config.mjs",
				"stylelint.config.mts",
				"stylelint.config.ts",
			}

			local function stylelint_root(bufnr)
				local root = find_upward(bufnr, stylelint_markers)
				if root then
					return root
				end

				-- Stylelint also accepts a `stylelint` key in package.json.
				local dir = buffer_dir(bufnr)
				while dir do
					local package_json = vim.fs.joinpath(dir, "package.json")
					if uv.fs_stat(package_json) then
						local ok_read, lines = pcall(vim.fn.readfile, package_json)
						local ok_json, package = false, nil
						if ok_read then
							ok_json, package = pcall(vim.json.decode, table.concat(lines, "\n"))
						end
						if ok_json and type(package) == "table" and package.stylelint ~= nil then
							return dir
						end
					end

					local parent = vim.fs.dirname(dir)
					if not parent or parent == dir then
						break
					end
					dir = parent
				end
				return nil
			end

			-- Project-aware linters should not guess a ruleset. Besides avoiding
			-- false diagnostics, the root is passed as cwd so each tool finds the
			-- same configuration that enabled it.
			local project_roots = {
				golangcilint = function(bufnr)
					return find_upward(bufnr, {
						".golangci.json",
						".golangci.toml",
						".golangci.yaml",
						".golangci.yml",
					})
				end,
				selene = function(bufnr)
					return find_upward(bufnr, { "selene.toml" })
				end,
				stylelint = stylelint_root,
			}

			local function resolve_linter(name)
				local linter = lint.linters[name]
				if type(linter) == "function" then
					local ok, resolved = pcall(linter)
					if not ok then
						return nil
					end
					linter = resolved
				end
				return linter
			end

			local function executable_available(name, linter, root)
				-- nvim-lint's Stylelint definition prefers a project-local binary.
				if name == "stylelint" and root then
					local local_cmd = vim.fs.joinpath(root, "node_modules", ".bin", "stylelint")
					if vim.fn.executable(local_cmd) == 1 then
						return true
					end
				end

				local cmd = linter and linter.cmd
				if type(cmd) == "function" then
					local ok, resolved = pcall(cmd)
					if not ok then
						return false
					end
					cmd = resolved
				end
				return type(cmd) == "string" and vim.fn.executable(cmd) == 1
			end

			local function configured_linters(bufnr)
				local names = {}
				local roots = {}
				for _, name in ipairs(lint.linters_by_ft[vim.bo[bufnr].filetype] or {}) do
					local root_for = project_roots[name]
					local root = root_for and root_for(bufnr) or nil
					local configured = not root_for or root ~= nil
					local linter = configured and resolve_linter(name) or nil

					if configured and linter and executable_available(name, linter, root) then
						table.insert(names, name)
						roots[name] = root
					else
						-- A removed/disabled project configuration must not leave its old
						-- diagnostics behind in an already-open buffer.
						vim.diagnostic.reset(lint.get_namespace(name), bufnr)
					end
				end
				return names, roots
			end

			local function is_empty_buffer(bufnr)
				local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
				return #lines == 0 or (#lines == 1 and lines[1] == "")
			end

			local function run_lint(bufnr, stdin_only)
				if
					not vim.api.nvim_buf_is_valid(bufnr)
					or not vim.api.nvim_buf_is_loaded(bufnr)
					or vim.b[bufnr].bigfile
				then
					return
				end

				vim.api.nvim_buf_call(bufnr, function()
					local names, roots = configured_linters(bufnr)
					if #names == 0 then
						return
					end

					if is_empty_buffer(bufnr) then
						for _, name in ipairs(names) do
							vim.diagnostic.reset(lint.get_namespace(name), bufnr)
						end
						return
					end
					local started_tick = vim.api.nvim_buf_get_changedtick(bufnr)

					lint.try_lint(names, {
						-- InsertLeave checks only in-memory text. Disk-only linters run
						-- after reading/saving and are also withheld from modified buffers.
						filter = function(linter)
							if stdin_only then
								return linter.stdin == true
							end
							return linter.stdin == true or not vim.bo[bufnr].modified
						end,
						wrap_linter = function(linter)
							-- A process can finish after the user has edited again. Drop
							-- those stale results instead of publishing diagnostics against
							-- a different in-memory revision.
							if type(linter.parser) == "function" then
								local parser = linter.parser
								linter.parser = function(...)
									if
										not vim.api.nvim_buf_is_valid(bufnr)
										or vim.api.nvim_buf_get_changedtick(bufnr) ~= started_tick
									then
										return {}
									end
									return parser(...)
								end
							end

							local root = roots[linter.name]
							if root then
								linter.cwd = root
								-- The upstream Stylelint command resolver checks
								-- ./node_modules relative to Neovim's cwd before the child
								-- process receives `linter.cwd`. Pin the known project-local
								-- executable here so projects work from any editor cwd.
								if linter.name == "stylelint" then
									local local_cmd = vim.fs.joinpath(root, "node_modules", ".bin", "stylelint")
									if vim.fn.executable(local_cmd) == 1 then
										linter.cmd = local_cmd
									end
								end
							end
							return linter
						end,
					})
				end)
			end

			-- Generation tokens provide a small per-buffer debounce without keeping
			-- libuv handles alive. Full and stdin-only runs are debounced separately.
			local pending = {}
			local function schedule_lint(bufnr, stdin_only, delay)
				local kind = stdin_only and "stdin" or "full"
				pending[bufnr] = pending[bufnr] or { generation = {}, scheduled = {} }
				local state = pending[bufnr]
				if stdin_only and state.scheduled.full then
					-- The pending full pass includes stdin linters already.
					return
				elseif not stdin_only then
					-- A newer full pass supersedes a pending stdin-only pass.
					state.generation.stdin = (state.generation.stdin or 0) + 1
					state.scheduled.stdin = false
				end
				state.generation[kind] = (state.generation[kind] or 0) + 1
				state.scheduled[kind] = true
				local generation = state.generation[kind]

				vim.defer_fn(function()
					local current = pending[bufnr]
					if current and current.generation[kind] == generation then
						current.scheduled[kind] = false
						run_lint(bufnr, stdin_only)
					end
				end, delay)
			end

			local group = vim.api.nvim_create_augroup("user_lint", { clear = true })
			vim.api.nvim_create_autocmd("BufReadPost", {
				group = group,
				callback = function(event)
					schedule_lint(event.buf, false, 250)
				end,
			})
			vim.api.nvim_create_autocmd("BufEnter", {
				group = group,
				callback = function(event)
					schedule_lint(event.buf, true, 250)
				end,
			})
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = group,
				callback = function(event)
					schedule_lint(event.buf, false, 100)
				end,
			})
			vim.api.nvim_create_autocmd("InsertLeave", {
				group = group,
				callback = function(event)
					schedule_lint(event.buf, true, 150)
				end,
			})
			vim.api.nvim_create_autocmd("BufWipeout", {
				group = group,
				callback = function(event)
					pending[event.buf] = nil
				end,
			})

			vim.keymap.set("n", "<leader>cl", function()
				run_lint(vim.api.nvim_get_current_buf(), false)
			end, { desc = "Lint" })

			-- The event that lazy-loaded nvim-lint may already have fired. The
			-- debounce coalesces this with a replayed BufReadPost when applicable.
			schedule_lint(vim.api.nvim_get_current_buf(), false, 250)
		end,
	},
}
