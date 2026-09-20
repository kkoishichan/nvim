-- Explicit deployment operation. No tools are installed by requiring toolchain.
local profiles = vim.split(vim.env.NVIM_DEPLOY_PROFILES or "minimal", ",", { trimempty = true })
local function install()
	-- Deployment prepares this pinned plugin separately from the runtime set.
	-- Start no editor plugins just to install explicitly selected tools.
	vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/mason.nvim")
	require("mason").setup({ PATH = "skip" })
	local registry = require("mason-registry")
	local ready, refreshed = false, false
	registry.refresh(function(ok)
		ready, refreshed = true, ok
	end)
	assert(vim.wait(120000, function()
		return ready
	end, 50) and refreshed, "Mason registry refresh failed or timed out")
	local failures = {}
	for _, spec in ipairs(require("user.toolchain").ensure_installed(profiles)) do
		local ok, err = pcall(function()
			local package = registry.get_package(spec[1])
			if package:is_installed() and package:get_installed_version() == spec.version then
				return
			end
			assert(not package:is_installing(), spec[1] .. " is being installed by another process")
			local completed, succeeded = false, false
			local handle = package:install({ version = spec.version }, function(success)
				completed, succeeded = true, success
			end)
			if not vim.wait(600000, function()
				return completed
			end, 100) then
				if handle and handle.terminate then
					pcall(handle.terminate, handle)
				end
				error(spec[1] .. " install timed out")
			end
			assert(
				succeeded and package:is_installed() and package:get_installed_version() == spec.version,
				spec[1] .. " did not install its pinned version " .. spec.version
			)
		end)
		if not ok then
			failures[#failures + 1] = tostring(err)
		end
	end
	assert(#failures == 0, "Incomplete Mason restore:\n" .. table.concat(failures, "\n"))
	print("Pinned Mason profiles restored: " .. table.concat(profiles, ", "))
end
local ok, err = pcall(install)
if not ok then
	vim.api.nvim_err_writeln(tostring(err))
	vim.cmd("cquit 30")
end
