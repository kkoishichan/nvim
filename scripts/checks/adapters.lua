-- The adapter registry must make a fallback visible: a degradation entry, one
-- notice per session, state in :ModeInfo and health; and the colour preview
-- adapter must fall back instead of failing its plugin's configuration.
return function()
	local adapters = require("user.core.adapters")
	local mode = require("user.core.mode")
	adapters.reset()
	local notices = {}
	local notify = vim.notify
	vim.notify = function(message, level, opts)
		notices[#notices + 1] = { message = message, level = level, title = opts and opts.title }
	end

	assert(adapters.record("alpha", true, "repaired 2 things") == true, "An active record did not return true")
	assert(adapters.record("beta", false, "source changed") == false, "An inactive record did not return false")
	assert(
		adapters.record("gamma", false, "nothing to repair", { quiet = true }) == false,
		"A quiet inactive record did not return false"
	)
	assert(adapters.run("delta", function()
		error("boom")
	end) == false, "A failing setup was not recorded as inactive")
	assert(adapters.run("epsilon", function()
		return true
	end) == true, "A successful setup was not recorded as active")
	vim.wait(50, function()
		return #notices > 0
	end, 5)
	vim.wait(50, function()
		return false
	end, 5)
	assert(
		#notices == 1 and notices[1].title == "Adapters" and notices[1].message:find("beta", 1, true),
		vim.inspect(notices)
	)
	local subjects = {}
	for _, entry in ipairs(mode.degradations()) do
		subjects[entry.subject] = entry.reason
	end
	assert(subjects["adapter beta"] == "source changed", "Inactive adapter was not recorded as a degradation")
	assert(
		subjects["adapter delta"] and subjects["adapter delta"]:find("boom", 1, true),
		"Setup error was not recorded"
	)
	assert(subjects["adapter gamma"] == nil, "A quiet entry was recorded as a degradation")
	local names = {}
	for _, entry in ipairs(adapters.list()) do
		names[#names + 1] = entry.name .. ":" .. tostring(entry.active)
	end
	assert(
		table.concat(names, ",") == "alpha:true,beta:false,gamma:false,delta:false,epsilon:true",
		table.concat(names, ",")
	)
	local summary = adapters.summary()
	assert(summary:find("alpha on", 1, true) and summary:find("beta off (source changed)", 1, true), summary)
	assert(
		adapters.record("beta", true) == true and not adapters.summary():find("beta off", 1, true),
		"Re-recording an adapter did not replace its state"
	)
	assert(#adapters.list() == 5, "Re-recording duplicated an entry")

	-- :ModeInfo and :checkhealth user both print the registry.
	local echoed = {}
	local echo = vim.api.nvim_echo
	vim.api.nvim_echo = function(chunks, ...)
		for _, chunk in ipairs(chunks) do
			echoed[#echoed + 1] = chunk[1]
		end
		return echo(chunks, ...)
	end
	vim.cmd.ModeInfo()
	vim.api.nvim_echo = echo
	assert(table.concat(echoed):find("adapters%s+alpha on"), "ModeInfo did not list adapters")
	local reports = {}
	local health = vim.health
	local fake = setmetatable({}, { __index = health })
	for _, kind in ipairs({ "ok", "warn", "info", "error", "start" }) do
		fake[kind] = function(message)
			reports[#reports + 1] = kind .. ": " .. message
		end
	end
	vim.health = fake
	local ok, err = pcall(require("user.health").check)
	vim.health = health
	assert(ok, err)
	local joined = table.concat(reports, "\n")
	assert(joined:find("ok: Adapter alpha active", 1, true), joined)
	assert(joined:find("warn: Adapter delta inactive", 1, true), "Health did not warn about a failed adapter")
	assert(joined:find("info: Adapter gamma inactive", 1, true), "Health did not keep a quiet adapter informational")
	vim.notify = notify
	adapters.reset()

	-- The colour preview adapter configures an unrecognised plugin natively.
	local real = package.loaded["nvim-highlight-colors"]
	local configured = {}
	package.loaded["nvim-highlight-colors"] = {
		setup = function(opts)
			configured[#configured + 1] = opts
		end,
		is_active = function()
			return true
		end,
	}
	local preview = require("user.core.color_preview")
	preview.shutdown()
	local active, reason = preview.setup({ render = "background" })
	assert(active == false and type(reason) == "string", "Unrecognised plugin activated the adapter")
	assert(#configured == 1 and configured[1].render == "background", "Unrecognised plugin was not configured natively")
	assert(vim._user_color_preview == nil, "Fallback left the adapter registered as owner")
	package.loaded["nvim-highlight-colors"] = real
	print("Adapters passed: registry, single notice, degradation, ModeInfo, health and colour preview fallback")
end
