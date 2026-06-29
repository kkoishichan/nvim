-- Display follows the modern-IDE pattern, adapted to Neovim: underline + gutter
-- signs are always on (location at a glance); the full message for the *current
-- line* expands beneath it via virtual_lines (built-in, 0.11+). This keeps long
-- messages from overflowing the window the way trailing virtual_text does, shows
-- code and message together without occluding, and points at the exact column.
local base = {
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = "E",
			[vim.diagnostic.severity.WARN] = "W",
			[vim.diagnostic.severity.INFO] = "I",
			[vim.diagnostic.severity.HINT] = "H",
		},
	},
	float = {
		border = "rounded",
		source = true,
	},
}

-- Trailing inline text, used only in the "text" fallback mode. Collapse newlines
-- and cap the length so it never runs off the window.
local virtual_text = {
	spacing = 4,
	source = "if_many",
	prefix = ">",
	format = function(diagnostic)
		local message = diagnostic.message:gsub("%s*\n%s*", " ")
		if #message > 80 then
			message = message:sub(1, 79) .. "…"
		end
		return message
	end,
}

-- <leader>ud cycles: expanded current line -> short trailing text -> off.
local modes = { "lines", "text", "off" }
local mode = "lines"

local function apply_diagnostic_mode()
	vim.diagnostic.config(vim.tbl_extend("force", base, {
		virtual_lines = mode == "lines" and { current_line = true } or false,
		virtual_text = mode == "text" and virtual_text or false,
	}))
end

apply_diagnostic_mode()

vim.keymap.set("n", "<leader>ud", function()
	for index, name in ipairs(modes) do
		if name == mode then
			mode = modes[index % #modes + 1]
			break
		end
	end
	apply_diagnostic_mode()
	vim.notify("Diagnostics: " .. mode, vim.log.levels.INFO, { title = "Diagnostics" })
end, { desc = "Cycle diagnostic display" })

vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })

vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })

vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })
vim.keymap.set("n", "<leader>cD", vim.diagnostic.setloclist, { desc = "Diagnostic loclist" })
