local M = {}
local owner
local hashes = {
	ts_syntax = "a52c2aa7aa63583673b7725ffdef62c0c666cb7976b8c7d6c708b7283a57338c",
	ts_engine = "3004e5a95f96a19edf46446de1466bd2b08c20fce69b3f6fade6054f5ced0085",
}

function M.syntax(fn, args)
	if owner and owner.interrupt then
		owner.interrupt()
	end
	return require("treesitter-matchup.syntax")[fn](args[1], args[2], args[3])
end

function M.engine(fn, args)
	if fn ~= "is_enabled" and owner and owner.interrupt and owner.interrupt() then
		return fn == "get_matching" and {} or nil
	end
	return require("treesitter-matchup.internal")[fn](args[1], args[2], args[3])
end

function M.stats()
	return {
		automatic_yield = owner ~= nil and owner.interrupt ~= nil,
		interruptions = owner and owner.interruptions or 0,
		resumes = owner and owner.resumes or 0,
	}
end

local function checked_source(path, hash)
	local input = path and io.open(path, "rb")
	local source = input and input:read("*a")
	if input then
		input:close()
	end
	return source and vim.fn.sha256(source) == hash
end

local function definition(name)
	if vim.fn.exists("*" .. name) == 0 then
		return nil
	end
	local lines = {}
	for _, line in ipairs(vim.split(vim.fn.execute("function " .. name), "\n")) do
		-- The listing also contains a localized "last set from" message.
		if line:match("^%s*function%s+") or line:match("^%s*endfunction") or line:match("^%s*%d+%s+") then
			lines[#lines + 1] = line:gsub("^%s*%d+%s+", ""):gsub("^%s*function%s+", "function! ")
		end
	end
	return table.concat(lines, "\n")
end

function M.setup()
	local changed = {}
	for file, hash in pairs(hashes) do
		local path = vim.api.nvim_get_runtime_file("autoload/matchup/" .. file .. ".vim", false)[1]
		if checked_source(path, hash) then
			local entry = file == "ts_syntax" and "synID" or "is_enabled"
			if vim.fn.exists("*matchup#" .. file .. "#" .. entry) == 0 then
				vim.cmd.source(vim.fn.fnameescape(path))
			end
			local suffix = "/autoload/matchup/" .. file .. ".vim"
			local resolved = vim.fn.resolve(path)
			for _, script in ipairs(vim.fn.getscriptinfo()) do
				if script.name:sub(-#suffix) == suffix and vim.fn.resolve(script.name) == resolved then
					local name = "<SNR>" .. script.sid .. "_forward"
					local before = definition(name)
					local module = file == "ts_syntax" and "syntax" or "internal"
					local expected = "letl:ret=luaeval('require\"treesitter-matchup."
						.. module
						.. "\".' .a:fn.'(unpack(_A))',a:000)returnl:ret"
					local body = before and before:match("\n(.*)\n%s*endfunction")
					-- Do not replace another extension's version of the bridge.
					if body and body:gsub("%s+", "") == expected:gsub("%s+", "") then
						local method = file == "ts_syntax" and "syntax" or "engine"
						vim.cmd(
							before:match("^[^\n]+")
								.. "\n"
								.. "return v:lua.require'user.core.matchup_bridge'."
								.. method
								.. "(a:fn, a:000)\nendfunction"
						)
						changed[#changed + 1] = { name = name, before = before, after = definition(name) }
					end
					break
				end
			end
		end
	end
	local state = { active = true, interruptions = 0, resumes = 0 }
	if #changed == 2 then
		local perf = vim.api.nvim_get_runtime_file("autoload/matchup/perf.vim", false)[1]
		local perf_checked = checked_source(perf, "7dee44a93911a7c78ccdbd29bb8801f80051e048cde64ff50acbb3e9fa1462b3")
		for _, script in ipairs(vim.fn.getscriptinfo()) do
			if
				perf_checked
				and script.name:match("/autoload/matchup/matchparen%.vim$")
				and checked_source(script.name, "f739bef77e2ad4b8fd1c47356a1e9efa6e3ddd6b01323daa211f627ba3df49ba")
			then
				state.interrupt = require("user.core.matchup_input")(state, "<SNR>" .. script.sid .. "_timer_callback")
				break
			end
		end
		owner = state
	end
	return function()
		if not state.active then
			return
		end
		state.active = false
		if owner == state then
			owner = nil
		end
		for _, item in ipairs(changed) do
			if definition(item.name) == item.after then
				vim.cmd(item.before)
			end
		end
	end,
		#changed
end

return M
