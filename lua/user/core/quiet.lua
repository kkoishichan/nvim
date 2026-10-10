-- A session-wide pause for the always-on layers extra adds. The structural
-- difference between standard and extra is which plugins are imported, and a
-- restart decides that; whether the imported decoration layers run right now
-- is a session decision. Every layer is paused through its own public entry
-- and restored to exactly the state it had, so toggling twice is a no-op and
-- a layer the user had already switched off stays off.
local M = {}
local state

local function loaded(name)
	return package.loaded[name]
end

local function loaded_buffers()
	local result = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			result[#result + 1] = bufnr
		end
	end
	return result
end

-- Each layer returns a restore function when it paused something, false when
-- it was present but already quiet, and nil when it is not loaded at all.
local layers = {
	{
		name = "matchup",
		pause = function()
			if vim.fn.exists(":NoMatchParen") ~= 2 then
				return nil
			end
			if vim.g.matchup_matchparen_enabled == 0 then
				return false
			end
			vim.cmd("NoMatchParen")
			return function()
				vim.cmd("DoMatchParen")
			end
		end,
	},
	{
		name = "illuminate",
		pause = function()
			local engine = loaded("illuminate.engine")
			if not engine then
				return nil
			end
			if engine.is_paused() then
				return false
			end
			engine.pause()
			return function()
				engine.resume()
			end
		end,
	},
	{
		name = "indent lines",
		pause = function()
			local ibl, config = loaded("ibl"), loaded("ibl.config")
			if not ibl or not config then
				return nil
			end
			if not config.get_config(vim.api.nvim_get_current_buf()).enabled then
				return false
			end
			ibl.update({ enabled = false })
			return function()
				ibl.update({ enabled = true })
			end
		end,
	},
	{
		name = "colours",
		pause = function()
			local plugin = loaded("nvim-highlight-colors")
			if not plugin then
				return nil
			end
			if not plugin.is_active() then
				return false
			end
			plugin.turn_off()
			return function()
				plugin.turn_on()
			end
		end,
	},
	{
		name = "todo comments",
		pause = function()
			local plugin, highlight = loaded("todo-comments"), loaded("todo-comments.highlight")
			if not plugin or not highlight then
				return nil
			end
			if not highlight.enabled then
				return false
			end
			plugin.disable()
			return function()
				plugin.enable()
			end
		end,
	},
	{
		name = "lightbulb",
		pause = function()
			local plugin = loaded("nvim-lightbulb")
			if not plugin then
				return nil
			end
			local ok, registrations = pcall(vim.api.nvim_get_autocmds, { group = "LightBulb" })
			if not ok or #registrations == 0 then
				return false
			end
			pcall(vim.api.nvim_clear_autocmds, { group = "LightBulb" })
			for _, bufnr in ipairs(loaded_buffers()) do
				pcall(plugin.clear_lightbulb, bufnr)
			end
			return function()
				local spec = require("lazy.core.config").plugins["nvim-lightbulb"]
				plugin.setup(spec and require("lazy.core.plugin").values(spec, "opts", false) or {})
			end
		end,
	},
	{
		name = "scrollbar",
		pause = function()
			local plugin = loaded("scrollview")
			if not plugin then
				return nil
			end
			if not vim.g.scrollview_enabled then
				return false
			end
			plugin.set_state(false)
			return function()
				plugin.set_state(true)
			end
		end,
	},
	{
		name = "line blame",
		pause = function()
			local config = loaded("gitsigns.config")
			if not config then
				return nil
			end
			if not config.config.current_line_blame then
				return false
			end
			require("gitsigns").toggle_current_line_blame(false)
			return function()
				require("gitsigns").toggle_current_line_blame(true)
			end
		end,
	},
	{
		name = "code lenses",
		pause = function()
			local buffers = {}
			for _, bufnr in ipairs(loaded_buffers()) do
				if vim.lsp.codelens.is_enabled({ bufnr = bufnr }) then
					vim.lsp.codelens.enable(false, { bufnr = bufnr })
					buffers[#buffers + 1] = bufnr
				end
			end
			if #buffers == 0 then
				return false
			end
			return function()
				for _, bufnr in ipairs(buffers) do
					if vim.api.nvim_buf_is_loaded(bufnr) then
						vim.lsp.codelens.enable(true, { bufnr = bufnr })
					end
				end
			end
		end,
	},
	{
		name = "inlay hints",
		pause = function()
			local buffers = {}
			for _, bufnr in ipairs(loaded_buffers()) do
				if vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }) then
					vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
					buffers[#buffers + 1] = bufnr
				end
			end
			if #buffers == 0 then
				return false
			end
			return function()
				for _, bufnr in ipairs(buffers) do
					if vim.api.nvim_buf_is_loaded(bufnr) then
						vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
					end
				end
			end
		end,
	},
	{
		name = "expanded diagnostics",
		pause = function()
			local diagnostics = loaded("user.core.diagnostics")
			if not diagnostics then
				return nil
			end
			if diagnostics.current() ~= "lines" then
				return false
			end
			diagnostics.set("text")
			return function()
				diagnostics.set("lines")
			end
		end,
	},
}

function M.active()
	return state ~= nil
end

---Names of the layers paused by the current quiet session.
function M.paused()
	local names = {}
	for _, entry in ipairs(state and state.restores or {}) do
		names[#names + 1] = entry.name
	end
	return names
end

function M.enable()
	if state then
		return M.paused()
	end
	local restores = {}
	for _, layer in ipairs(layers) do
		local ok, restore = pcall(layer.pause)
		if ok and type(restore) == "function" then
			restores[#restores + 1] = { name = layer.name, restore = restore }
		elseif not ok then
			vim.notify(
				"Could not pause " .. layer.name .. ": " .. tostring(restore),
				vim.log.levels.WARN,
				{ title = "Quiet" }
			)
		end
	end
	state = { restores = restores }
	local names = M.paused()
	vim.notify(
		#names > 0 and ("Quiet: paused " .. table.concat(names, ", ")) or "Quiet: nothing to pause in this mode",
		vim.log.levels.INFO,
		{ title = "Quiet" }
	)
	return names
end

function M.disable()
	if not state then
		return {}
	end
	local restored = {}
	for index = #state.restores, 1, -1 do
		local entry = state.restores[index]
		local ok, err = pcall(entry.restore)
		if ok then
			restored[#restored + 1] = entry.name
		else
			vim.notify(
				"Could not restore " .. entry.name .. ": " .. tostring(err),
				vim.log.levels.WARN,
				{ title = "Quiet" }
			)
		end
	end
	state = nil
	vim.notify(
		#restored > 0 and ("Quiet off: restored " .. table.concat(restored, ", ")) or "Quiet off",
		vim.log.levels.INFO,
		{ title = "Quiet" }
	)
	return restored
end

function M.toggle()
	if state then
		return M.disable()
	end
	return M.enable()
end

return M
