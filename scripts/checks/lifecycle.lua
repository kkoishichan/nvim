return function()
	assert(not package.loaded["user.core.ai"], "AI implementation was loaded before its first action")
	assert(not package.loaded["user.core.ai_terminal"], "AI terminals were initialized during startup")
	local provider_map
	for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
		if mapping.desc == "AI provider" then
			provider_map = mapping.callback
		end
	end
	assert(type(provider_map) == "function", "AI entry mapping is unavailable")
	local select, prompted = vim.ui.select, false
	vim.ui.select = function(_, _, callback)
		prompted = true
		callback(nil)
	end
	local began = vim.uv.hrtime()
	provider_map()
	local elapsed = (vim.uv.hrtime() - began) / 1e6
	vim.ui.select = select
	assert(prompted and package.loaded["user.core.ai"], "First AI action did not load and dispatch")
	print(("AI first-use module load and canceled provider picker: %.2f ms"):format(elapsed))

	local highlights = require("user.core.highlights")
	local count = highlights.count()
	local old_calls, new_calls = 0, 0
	highlights.on_colorscheme("lifecycle-test", function()
		old_calls = old_calls + 1
	end)
	for _ = 1, 6 do
		highlights.on_colorscheme("lifecycle-test", function()
			new_calls = new_calls + 1
		end)
		package.loaded["user.core.highlights"] = nil
		highlights = require("user.core.highlights")
	end
	assert(highlights.count() == count + 1, "Named highlights accumulated callbacks during reload")
	local events = vim.api.nvim_get_autocmds({ group = "user_custom_highlights", event = "ColorScheme" })
	assert(#events == 1, "Theme dispatcher accumulated autocmds")
	vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
	assert(old_calls == 1 and new_calls == 7, "A replaced highlight callback was still called")
	highlights.remove("lifecycle-test")
	assert(highlights.count() == count, "Highlight callback was not released")
end
