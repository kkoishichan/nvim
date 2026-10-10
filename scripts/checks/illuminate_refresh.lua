-- Reference highlighting must request once per cursor rest rather than once
-- per movement event, while leaving a highlighted word still clears at once.
return function()
	local api = vim.api
	local old_ignore = vim.o.eventignore
	-- The fixture drives the engine directly; the plugin's own movement
	-- autocmds would otherwise add refreshes of their own to the counts.
	vim.o.eventignore = "CursorMoved,CursorMovedI,TextChanged,ModeChanged"
	require("lazy").load({ plugins = { "vim-illuminate" } })
	local engine = require("illuminate.engine")
	local reference = require("illuminate.reference")
	local adapter = require("user.core.illuminate_refresh")
	adapter.shutdown()
	local native = engine.refresh_references
	assert(adapter.setup(), "Reference highlight adapter did not activate")
	assert(engine.refresh_references ~= native, "Adapter did not replace the refresh entry")

	vim.cmd.tabnew()
	local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
	api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha beta alpha", "alpha gamma" })
	vim.bo[buf].filetype = "lua"
	api.nvim_win_set_cursor(win, { 1, 0 })

	local requests, answer = 0, nil
	local fake = {
		is_ready = function()
			return true
		end,
		initiate_request = function()
			requests = requests + 1
			answer = nil
		end,
		get_references = function()
			return answer
		end,
	}
	local get_provider = engine.get_provider
	engine.get_provider = function()
		return fake, "fake"
	end
	local references = {
		{ { 0, 0 }, { 0, 5 }, "text" },
		{ { 0, 11 }, { 0, 16 }, "text" },
		{ { 1, 0 }, { 1, 5 }, "text" },
	}
	local function extmarks()
		return #api.nvim_buf_get_extmarks(buf, -1, 0, -1, {})
	end
	local function settle(ms)
		vim.wait(ms, function()
			return false
		end, 5)
	end

	-- A burst of movement events is one request once the cursor rests.
	for _ = 1, 40 do
		engine.refresh_references()
	end
	assert(requests == 0, "Movement events requested references synchronously")
	assert(
		vim.wait(400, function()
			return requests == 1
		end, 5),
		"A rested cursor did not request references"
	)
	answer = references
	assert(
		vim.wait(600, function()
			return #reference.buf_get_references(buf) == 3
		end, 5),
		"References were not drawn after the response"
	)
	assert(extmarks() > 0, "References were recorded but not highlighted")
	settle(150)
	assert(requests == 1, "An idle cursor sent further requests")
	assert(adapter.stats().coalesced == 39 and adapter.stats().refreshes == 1, vim.inspect(adapter.stats()))

	-- Moving between references keeps the highlight while the next request waits.
	api.nvim_win_set_cursor(win, { 1, 11 })
	engine.refresh_references()
	assert(#reference.buf_get_references(buf) == 3 and extmarks() > 0, "Moving within references cleared them")
	assert(requests == 1, "Moving within references requested synchronously")
	assert(
		vim.wait(400, function()
			return requests == 2
		end, 5),
		"The new reference position was not requested"
	)
	answer = references
	settle(200)

	-- Leaving the word clears immediately, exactly like the plugin, and the
	-- request for the new position still waits for the cursor to rest.
	api.nvim_win_set_cursor(win, { 2, 7 })
	engine.refresh_references()
	assert(#reference.buf_get_references(buf) == 0, "Leaving a highlighted word did not clear references at once")
	assert(extmarks() == 0, "Leaving a highlighted word left highlights behind")
	assert(requests == 2, "Clearing sent a request synchronously")
	assert(
		vim.wait(400, function()
			return requests == 3
		end, 5),
		"The new position was not requested"
	)
	answer = {}
	settle(200)
	assert(#reference.buf_get_references(buf) == 0 and extmarks() == 0, "An empty answer left highlights")

	-- A request whose window is no longer current when the cursor rests is
	-- dropped: the plugin would discard its answer anyway.
	api.nvim_win_set_cursor(win, { 1, 0 })
	engine.refresh_references()
	vim.cmd.tabnew()
	local scratch = api.nvim_get_current_buf()
	settle(200)
	assert(requests == 3, "A refresh for a window that was left still went out")
	api.nvim_set_current_win(win)
	api.nvim_buf_delete(scratch, { force = true })

	-- Ownership: shutdown restores the native entry; reloading the module keeps
	-- one owner and one cleanup handler; an obsolete owner cannot remove the
	-- replacement; an unverified engine keeps its native entry.
	adapter.shutdown()
	assert(engine.refresh_references == native, "Shutdown did not restore the native refresh")
	assert(vim._user_illuminate_refresh == nil, "Shutdown did not release the owner")
	package.loaded["user.core.illuminate_refresh"] = nil
	local reloaded = require("user.core.illuminate_refresh")
	assert(reloaded.setup() and reloaded.setup(), "Reload did not activate")
	assert(#api.nvim_get_autocmds({ group = "user_illuminate_refresh" }) == 1, "Reload accumulated cleanup owners")
	assert(vim._user_illuminate_refresh == reloaded, "Reload did not take ownership")
	adapter.shutdown()
	assert(
		vim._user_illuminate_refresh == reloaded and engine.refresh_references ~= native,
		"An obsolete owner removed the replacement"
	)
	package.loaded["user.core.illuminate_refresh"] = nil
	local third = require("user.core.illuminate_refresh")
	assert(third.setup(), "Second reload did not activate")
	assert(
		vim._user_illuminate_refresh == third and reloaded.stats().active == false,
		"Double reload kept the old owner"
	)
	assert(
		#api.nvim_get_autocmds({ group = "user_illuminate_refresh" }) == 1,
		"Double reload accumulated cleanup owners"
	)
	for _ = 1, 10 do
		engine.refresh_references()
	end
	assert(
		vim.wait(400, function()
			return requests == 4
		end, 5),
		"The replacement lost the coalesced request"
	)
	assert(requests == 4 and third.stats().coalesced == 9, "Double reload accumulated wrappers")
	third.shutdown()
	assert(engine.refresh_references == native, "Final shutdown did not restore the native refresh")
	local real_engine = package.loaded["illuminate.engine"]
	package.loaded["illuminate.engine"] = { refresh_references = function() end }
	assert(not third.setup(), "An unverified engine was patched")
	package.loaded["illuminate.engine"] = real_engine
	assert(engine.refresh_references == native, "Refusing an unverified engine changed the real one")

	engine.get_provider = get_provider
	assert(third.setup(), "The adapter did not reactivate for the session")
	api.nvim_buf_delete(buf, { force = true })
	vim.o.eventignore = old_ignore
	print(
		"Illuminate refresh passed: 40 movement events -> 1 request, immediate clearing, dropped stale window, reload and cleanup"
	)
end
