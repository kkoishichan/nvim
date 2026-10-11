-- The plugin set a fast session installs and imports. Full mode imports every
-- module under `user.plugins`; fast mode names the shared factories it wants,
-- so no other plugin module is executed at all. The set is chosen up front, not
-- produced by running everything and then filtering by plugin name.

local M = {}

-- Order matters only for the theme, which must be able to claim its startup
-- priority before anything else draws.
local factories = {
	{ "user.specs.theme", { single = true } },
	{ "user.specs.statusline" },
	{ "user.specs.treesitter" },
	{ "user.specs.editing" },
	{ "user.specs.flash" },
	{ "user.specs.which_key" },
	{ "user.specs.explorer" },
	{ "user.specs.picker" },
	{ "user.specs.format" },
	{ "user.specs.lsp" },
	{ "user.specs.lint" },
}

---The complete fast-mode spec, dependencies included by way of each plugin's
---own `dependencies` field.
function M.base()
	local spec = {}
	for _, factory in ipairs(factories) do
		vim.list_extend(spec, require(factory[1])(factory[2]))
	end
	return spec
end

---The same selector serves runtime, asset preparation and deployment. Standard
---never imports the extra plugin modules, including their lazy key/event hooks.
function M.for_mode(name)
	name = require("user.core.mode").canonical(name)
	if name == "fast" then
		return M.base()
	elseif name == "extra" then
		return { { import = "user.plugins" } }
	end
	assert(name == "standard", "Unknown editor mode: " .. tostring(name))
	local spec = {}
	for _, factory in ipairs({ "ui", "editor", "navigation", "auto_lsp", "languages", "java", "lint" }) do
		vim.list_extend(spec, require("user.specs." .. factory)())
	end
	for _, module in ipairs({
		"completion",
		"folding",
		"formatting",
		"git",
		"multicursor",
		"neogen",
		"picker",
		"terminal",
		"tools",
		"treesitter",
	}) do
		vim.list_extend(spec, require("user.plugins." .. module))
	end
	return spec
end

---Top-level plugin names in the fast set. Deployment and lock checks use this
---to decide what to prepare; each plugin's dependencies are resolved from the
---same spec, so the two can never disagree.
function M.base_names()
	local names = {}
	for _, plugin in ipairs(M.base()) do
		table.insert(names, plugin.name or vim.fs.basename(plugin[1]))
		for _, dependency in ipairs(plugin.dependencies or {}) do
			local name = type(dependency) == "string" and dependency or dependency[1]
			table.insert(names, vim.fs.basename(name))
		end
	end
	table.sort(names)
	return names
end

return M
