return function(tmp)
	local trust = require("user.core.trust")
	local tools = require("user.toolchain")
	local base = vim.fs.joinpath(tmp, "project")
	local path = vim.fs.joinpath(base, "node_modules", ".bin", "prettier")
	local manifest = vim.fs.joinpath(base, "package.json")
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.mkdir(vim.fs.joinpath(base, ".git"), "p")
	vim.fn.writefile({ '{ "private": true }' }, manifest)
	vim.fn.writefile({ "#!/bin/sh", "exit 0" }, path)
	assert(vim.fn.setfperm(path, "rwxr-xr-x") == 1, "Could not make the project tool executable")
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(base, "sample.js"))
	local saved = {
		bypass = vim.env.NVIM_TRUST_PROJECTS,
		global = vim.g.user_trust_projects,
		path = vim.env.PATH,
		read = vim.secure.read,
		secure_trust = vim.secure.trust,
		uis = vim.api.nvim_list_uis,
		confirm = vim.fn.confirm,
		notify = vim.notify,
		buffer = vim.api.nvim_get_current_buf(),
	}
	local ok, err = pcall(function()
		vim.api.nvim_set_current_buf(bufnr)
		vim.env.NVIM_TRUST_PROJECTS = nil
		vim.g.user_trust_projects = nil
		vim.notify = function() end
		trust.forget(base)
		tools.clear_executable_cache()
		assert(trust.status(base) == "unasked", "New project already has a session decision")

		-- Model an attached UI so the secure.read branch is actually exercised.
		vim.api.nvim_list_uis = function()
			return { {} }
		end
		local reads = 0
		vim.secure.read = function(file)
			assert(file == manifest, "Trust asked about the wrong project manifest")
			reads = reads + 1
			return nil
		end
		local denied = tools.node_resolve("prettier", bufnr)
		assert(denied.source ~= "project", "Denied project executable was selected")
		assert(denied.reason == "Project node_modules/.bin skipped: project not trusted", "Denial reason is missing")
		assert(trust.status(base) == "denied", "Denied decision was not recorded")
		tools.node_resolve("prettier", bufnr)
		assert(reads == 1, "Denied project prompted more than once per session")

		vim.secure.read = function()
			reads = reads + 1
			return "{}"
		end
		assert(tools.node_resolve("prettier", bufnr).source ~= "project", "Session denial was forgotten too soon")
		trust.forget(base)
		local allowed = tools.node_resolve("prettier", bufnr)
		assert(allowed.source == "project" and allowed.path == path, "Allowed project executable was not selected")
		assert(trust.status(base) == "allowed" and reads == 2, "Allowed decision was not recorded once")
		tools.node_resolve("prettier", bufnr)
		assert(reads == 2, "Allowed project prompted more than once per session")

		-- A real headless session must stop before secure.read/confirm, even for
		-- a manifest that could otherwise invoke Neovim's native trust prompt.
		vim.api.nvim_list_uis = saved.uis
		assert(#vim.api.nvim_list_uis() == 0, "Trust check must run without a UI")
		vim.secure.read = function()
			error("Headless trust read a manifest")
		end
		vim.fn.confirm = function()
			error("Headless trust opened a confirmation")
		end
		trust.forget(base)
		tools.clear_executable_cache()
		assert(tools.node_resolve("prettier", bufnr).source ~= "project", "Headless project tools were allowed")
		assert(trust.status(base) == "denied", "Headless denial was not cached")
		vim.env.NVIM_TRUST_PROJECTS = "1"
		assert(trust.allows(base) and trust.status(base) == "bypassed", "Environment trust bypass failed")
		assert(tools.node_resolve("prettier", bufnr).source == "project", "Bypass reused a denied executable cache")
		vim.env.NVIM_TRUST_PROJECTS = nil
		vim.g.user_trust_projects = true
		assert(trust.allows(base) and trust.status(base) == "bypassed", "Host trust bypass failed")
		vim.g.user_trust_projects = nil

		-- Exercise the real persistent database, isolated by check.sh, and the
		-- command's session/executable-cache invalidation.
		vim.api.nvim_list_uis = function()
			return { {} }
		end
		vim.secure.read = saved.read
		local actions = {}
		vim.secure.trust = function(opts)
			actions[#actions + 1] = opts.action
			assert(opts.path == manifest, "ProjectTrust changed the wrong manifest")
			return saved.secure_trust(opts)
		end
		vim.cmd("ProjectTrust allow")
		assert(trust.status(base) == "unasked", "ProjectTrust allow retained its session cache")
		assert(tools.node_resolve("prettier", bufnr).source == "project", "Persistent allow was ignored")
		vim.cmd("ProjectTrust deny")
		assert(tools.node_resolve("prettier", bufnr).source ~= "project", "Persistent deny reused an allowed cache")
		vim.secure.read = function()
			error("Status read a manifest")
		end
		vim.cmd("ProjectTrust status")
		assert(trust.status(base) == "denied", "Status altered the session decision")

		local bin = vim.fs.joinpath(tmp, "bin")
		vim.fn.mkdir(bin, "p")
		vim.env.PATH = bin .. ":" .. saved.path
		local name = "nvim-project-trust-cache-fixture"
		assert(not tools.resolve(name).path, "Cache fixture executable already exists")
		local new_tool = vim.fs.joinpath(bin, name)
		vim.fn.writefile({ "#!/bin/sh", "exit 0" }, new_tool)
		assert(vim.fn.setfperm(new_tool, "rwxr-xr-x") == 1, "Could not make the cache fixture executable")
		assert(not tools.resolve(name).path, "Missing executable was not cached before trust removal")
		vim.cmd("ProjectTrust remove")
		assert(trust.status(base) == "unasked", "ProjectTrust remove retained its session cache")
		assert(tools.resolve(name).path == new_tool, "ProjectTrust remove retained its executable cache")
		assert(vim.deep_equal(actions, { "allow", "deny", "remove" }), "ProjectTrust dispatched incorrect actions")
		local database = table.concat(vim.fn.readfile(vim.fs.joinpath(vim.fn.stdpath("state"), "trust")), "\n")
		assert(not database:find(manifest, 1, true), "ProjectTrust remove retained its persistent record")
	end)
	vim.env.NVIM_TRUST_PROJECTS, vim.g.user_trust_projects, vim.env.PATH = saved.bypass, saved.global, saved.path
	vim.secure.read, vim.secure.trust, vim.api.nvim_list_uis = saved.read, saved.secure_trust, saved.uis
	vim.fn.confirm, vim.notify = saved.confirm, saved.notify
	trust.forget(base)
	tools.clear_executable_cache()
	vim.api.nvim_set_current_buf(saved.buffer)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	assert(ok, "Project trust checks failed: " .. tostring(err))
	print(
		"Trust evidence: session decisions, native persistence, explicit bypass, headless refusal and cache invalidation passed"
	)
end
