return function(_)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local support = assert(loadfile(root .. "/scripts/check-support.lua"))()
	local lock = support.json(root .. "/lazy-lock.json")
	local original_system = vim.system
	local attempted_downloads = {}
	-- Blink uses vim.system for Git metadata, checksums and release downloads.
	-- Keep the real local processes and native matcher, but fail before starting
	-- any downloader. This tests the normal cached-release path, not a Lua engine
	-- substitute or a replacement for the plugin's setup/selection algorithm.
	vim.system = function(argv, ...)
		local executable = vim.fs.basename(argv[1])
		local remote = executable == "curl" or executable == "wget"
		if executable == "git" then
			for _, argument in ipairs(argv) do
				if argument == "clone" or argument == "fetch" or argument == "pull" or argument == "ls-remote" then
					remote = true
				end
			end
		end
		if remote then
			attempted_downloads[#attempted_downloads + 1] = table.concat(argv, " ")
			error("Network preparation attempted inside an offline check")
		end
		return original_system(argv, ...)
	end
	local ok, err = xpcall(function()
		support.verify_blink(vim.fn.stdpath("data"), lock["blink.cmp"].commit)
		require("lazy").load({ plugins = { "blink.cmp" } })
		assert(
			vim.wait(10000, function()
				local fuzzy = package.loaded["blink.cmp.fuzzy"]
				return fuzzy and fuzzy.implementation_type == "rust"
			end, 20),
			"The matching prepared Blink library did not select the real Rust matcher"
		)
		local fuzzy = require("blink.cmp.fuzzy")
		assert(
			fuzzy.implementation == require("blink.cmp.fuzzy.rust"),
			"Runtime matcher differs from the prepared native library"
		)
		assert(
			debug.getinfo(fuzzy.implementation.get_keyword_range, "S").what == "C",
			"Keyword matching is using a Lua substitute"
		)
		local start, finish = fuzzy.get_keyword_range("alpha_beta", 3, "full")
		assert(start == 0 and finish == 10, "Prepared Rust matcher could not perform keyword matching")
		assert(
			#attempted_downloads == 0,
			"Cached Blink startup attempted network access: " .. table.concat(attempted_downloads, "; ")
		)
	end, debug.traceback)
	vim.system = original_system
	assert(ok, err)
	print("Offline asset evidence: locked native Blink matcher loaded and executed without a download")
end
