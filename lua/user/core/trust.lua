local M = {}
local decisions = {}

local function bypassed()
	return vim.env.NVIM_TRUST_PROJECTS == "1" or vim.g.user_trust_projects == true
end

local function key(root)
	return assert(require("user.core.project").canonical(root), "Project trust requires a root")
end

---Ask once per session before using a project's Node executables.
function M.allows(root)
	if bypassed() then
		return true
	end
	root = key(root)
	if decisions[root] ~= nil then
		return decisions[root]
	end
	decisions[root] = #vim.api.nvim_list_uis() > 0 and vim.secure.read(vim.fs.joinpath(root, "package.json")) ~= nil
	return decisions[root]
end

function M.forget(root)
	decisions[key(root)] = nil
end

---Session state only: never read a file or prompt from a status display.
function M.status(root)
	if bypassed() then
		return "bypassed"
	end
	local decision = decisions[key(root)]
	return decision == nil and "unasked" or (decision and "allowed" or "denied")
end

return M
