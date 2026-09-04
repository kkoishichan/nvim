return {
	{
		"nickjvandyke/opencode.nvim",
		version = "*",
		config = function()
			local config = require("opencode.config")
			-- Each request resolves our exact managed URL. Retry here with its
			-- original root, rather than letting global discovery switch projects.
			config.opts.server.connect = false
			config.opts.server.start = false
			config.opts.server.url = function(callback)
				local project = require("user.core.project")
				local root = project.root()
				local url = require("user.core.ai").opencode_url()
				if not url then
					callback(nil)
					return
				end
				local deadline = vim.uv.hrtime() + 5e9
				local function attempt()
					if project.root() ~= root then
						callback(nil)
						return
					end
					require("opencode.server")
						.new(url)
						:next(function(server)
							-- This temporary connection only validates health and cwd; the
							-- plugin creates the actual request server after URL resolution.
							if server.heartbeat_timer and not server.heartbeat_timer:is_closing() then
								server.heartbeat_timer:close()
							end
							if project.root() ~= root then
								callback(nil)
							elseif project.canonical(server.cwd) ~= root then
								vim.notify("OpenCode server directory does not match " .. root, vim.log.levels.ERROR)
								callback(nil)
							else
								callback(url)
							end
						end)
						:catch(function(err)
							if project.root() ~= root then
								callback(nil)
							elseif vim.uv.hrtime() < deadline then
								vim.defer_fn(attempt, 200)
							else
								vim.notify(
									"OpenCode did not become ready in " .. root .. ": " .. tostring(err),
									vim.log.levels.ERROR
								)
								callback(nil)
							end
						end)
				end
				attempt()
			end
		end,
	},
}
