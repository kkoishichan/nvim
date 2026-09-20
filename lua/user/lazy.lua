local mode = require("user.core.mode")
local capabilities = mode.capabilities()
local bootstrap = require("user.core.lazy_bootstrap")
local layout = require("user.core.layout")

-- A mode without plugin-manager automation never downloads anything at launch.
-- Without lazy.nvim there is still an editor: fall back to the native entry and
-- say so once, leaving the detail to :ModeInfo.
local ok, lazypath = pcall(bootstrap.ensure, { install = capabilities.plugin_manager_auto })
if not ok then
	mode.degrade("plugins", tostring(lazypath))
	require("user.core.native").setup_explorer()
	mode.announce()
	return
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	lockfile = vim.fs.joinpath(bootstrap.root(), "lazy-lock.json"),
	-- Fast mode names the modules it wants, so the remaining plugin files are
	-- never executed; full mode keeps importing the complete directory.
	spec = mode.is_fast() and require("user.specs").base() or {
		{ import = "user.plugins" },
	},
	defaults = {
		lazy = true,
		version = false,
	},
	install = {
		missing = capabilities.plugin_manager_auto and vim.env.NVIM_CHECK_ONLY ~= "1",
		colorscheme = { "vscode", "habamax" },
	},
	checker = {
		enabled = false,
	},
	rocks = {
		enabled = false,
	},
	change_detection = {
		enabled = capabilities.plugin_manager_auto,
		notify = false,
	},
	ui = {
		size = { width = layout.manager_scale, height = layout.manager_scale },
		border = layout.manager_border,
		backdrop = 60,
	},
	performance = {
		rtp = {
			disabled_plugins = {
				"matchit",
				"matchparen",
				"netrwPlugin",
				"tohtml",
				"tutor",
			},
		},
	},
})

if not capabilities.plugin_manager_auto then
	-- Nothing was installed on our behalf, so report what is absent instead of
	-- letting the first keypress fail. The explorer has a native replacement.
	local config = require("lazy.core.config")
	local missing = {}
	for name, plugin in pairs(config.plugins) do
		if not plugin._.installed then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		mode.degrade("plugins", "not installed: " .. table.concat(missing, ", "))
	end
	local oil = config.plugins["oil.nvim"]
	if not oil or not oil._.installed then
		require("user.core.native").setup_explorer()
	end

	-- Lazy's manager acts on the spec of the running session. In a mode that
	-- imports a subset, clean/sync/update would treat the rest of the shared
	-- installation as unused, so management stays an explicit full-mode run
	-- against the complete list.
	vim.api.nvim_create_user_command("Lazy", function()
		vim.notify(
			"Plugin management runs against the complete list: NVIM_MODE=full nvim +Lazy",
			vim.log.levels.WARN,
			{ title = "Editor mode" }
		)
	end, { nargs = "*", bang = true, desc = "Plugin management is a full-mode operation" })
end

mode.announce()

-- Lazy's manager is a floating application window, so the generic transient
-- popup closer deliberately ignores it. Add the conventional close key beside
-- Lazy's built-in `q` without reaching into its private view state.
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("user_lazy_escape", { clear = true }),
	pattern = "lazy",
	desc = "Close Lazy manager with Escape",
	callback = function(event)
		vim.keymap.set("n", "<Esc>", "<Cmd>close<CR>", {
			buffer = event.buf,
			desc = "Close Lazy manager",
			nowait = true,
			silent = true,
		})
	end,
})
