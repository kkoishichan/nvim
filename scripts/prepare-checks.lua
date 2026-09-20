local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
local data = vim.fn.stdpath("data")
local cache = vim.env.NVIM_PREPARE_CACHE_DATA
cache = cache ~= "" and cache or nil
local offline = vim.env.NVIM_PREPARE_OFFLINE == "1"
vim.opt.rtp:prepend(root)
local support = assert(loadfile(root .. "/scripts/check-support.lua"))()
local command, json = support.command, support.json
local function copy(source, destination)
	vim.fn.mkdir(vim.fs.dirname(destination), "p")
	command({ "cp", "-a", source, destination })
end
local nvim_version = vim.env.NVIM_PREPARE_NVIM_VERSION or "0.12.5"
nvim_version = nvim_version:gsub("^v", "")
assert(vim.version.eq(vim.version(), nvim_version), "Preparation requires Neovim " .. nvim_version)
if vim.env.NVIM_PREPARE_PARSERS ~= "0" then
	local cli = command({ "tree-sitter", "--version" }):match("(%d+%.%d+%.%d+)")
	assert(cli and vim.version.ge(cli, "0.26.1"), "tree-sitter-cli >= 0.26.1 is required (not the npm package)")
end
require("user.core.lazy_bootstrap").ensure({ root = root, cache = cache, offline = offline })
-- The complete lock is still validated against the complete spec: a slim
-- installation chooses what to put on disk, it never narrows the version
-- source. Only the names below are actually restored.
local lock, plugins = support.plugins(root, data)
local mode = support.mode()
local names = support.selected_plugins(root, data, mode)
if vim.env.NVIM_PREPARE_TOOLS ~= "0" and not vim.tbl_contains(names, "mason.nvim") then
	-- Check-tool preparation also needs an installer on a fresh slim host.
	table.insert(names, "mason.nvim")
end
for _, name in ipairs(names) do
	local plugin, pin = plugins[name], lock[name].commit
	local exists = vim.uv.fs_stat(plugin.dir .. "/.git") ~= nil
	if not exists then
		local source = cache and cache .. "/lazy/" .. name
		if not source or not vim.uv.fs_stat(source .. "/.git") then
			assert(not offline, "Missing cached plugin: " .. name)
			source = plugin.url
		end
		print("Preparing locked plugin: " .. name)
		command({ "git", "clone", "--filter=blob:none", "--no-checkout", "--no-hardlinks", source, plugin.dir })
	end
	assert(
		not exists or command({ "git", "status", "--porcelain", "--untracked-files=no" }, plugin.dir) == "",
		"Refusing to overwrite modified plugin: " .. name
	)
	command({ "git", "remote", "set-url", "origin", plugin.url }, plugin.dir)
	local available = vim.system({ "git", "cat-file", "-e", pin .. "^{commit}" }, {
		cwd = plugin.dir,
		env = { GIT_ALLOW_PROTOCOL = "file", GIT_TERMINAL_PROMPT = "0" },
	}):wait(10000)
	if available.code ~= 0 then
		assert(not offline, "Offline preparation lacks locked commit for " .. name .. ": " .. pin)
		command({ "git", "fetch", "--depth=1", "origin", pin }, plugin.dir)
	end
	command({ "git", "checkout", "--detach", pin }, plugin.dir)
end
print(("Prepared %d of %d locked plugins for %s mode."):format(#names, vim.tbl_count(lock), mode))

local parsers, info = {}, {}
if vim.env.NVIM_PREPARE_PARSERS ~= "0" then
	parsers, info = support.parser_info(data)
end
local missing = {}
for _, parser in ipairs(parsers) do
	local revision_path = data .. "/site/parser-info/" .. parser .. ".revision"
	local revision = vim.uv.fs_stat(revision_path) and vim.trim(table.concat(vim.fn.readfile(revision_path), "\n"))
	local expected = info[parser].install_info and info[parser].install_info.revision
	if not vim.uv.fs_stat(data .. "/site/parser/" .. parser .. ".so") or (expected and revision ~= expected) then
		table.insert(missing, parser)
	end
end
if #missing > 0 then
	assert(
		not offline,
		"Offline environment lacks " .. #missing .. " matching parsers; prepare once with network access"
	)
	print(("Building %d of %d selected parsers from the locked Tree-sitter catalog."):format(#missing, #parsers))
	assert(
		require("nvim-treesitter").install(missing, { force = true, max_jobs = 4, summary = true }):wait(300000),
		"Parser preparation failed"
	)
end

local pending = {}
for _, name in ipairs(vim.env.NVIM_PREPARE_TOOLS == "0" and {} or support.tools) do
	local pin = assert(require("user.toolchain").version(name), "Missing configured tool pin: " .. name)
	local destination = data .. "/mason/packages/" .. name
	local function matches(directory)
		if not vim.uv.fs_stat(directory .. "/mason-receipt.json") then
			return false
		end
		return json(directory .. "/mason-receipt.json").source.id:sub(-#pin - 1) == "@" .. pin
	end
	if not matches(destination) then
		local cached = cache and cache .. "/mason/packages/" .. name
		if cached and matches(cached) and not vim.uv.fs_stat(destination) then
			print("Reusing matching tool cache: " .. name .. "@" .. pin)
			copy(cached, destination)
		else
			table.insert(pending, { name = name, version = pin })
		end
	end
	if matches(destination) then
		local receipt = json(destination .. "/mason-receipt.json")
		vim.fn.mkdir(data .. "/mason/bin", "p")
		for binary, target in pairs(receipt.links.bin) do
			local link = data .. "/mason/bin/" .. binary
			if not vim.uv.fs_lstat(link) then
				assert(vim.uv.fs_symlink("../packages/" .. name .. "/" .. target, link))
			end
		end
	end
end
if #pending > 0 then
	assert(not offline, "Offline environment lacks matching Mason check tools")
	vim.opt.rtp:prepend(data .. "/lazy/mason.nvim")
	require("mason").setup({ PATH = "skip" })
	local registry = require("mason-registry")
	local refreshed, success = false, false
	registry.refresh(function(ok)
		refreshed, success = true, ok
	end)
	assert(vim.wait(120000, function()
		return refreshed
	end, 50) and success, "Could not refresh Mason registry")
	for _, tool in ipairs(pending) do
		print("Preparing check tool: " .. tool.name .. "@" .. tool.version)
		local completed, installed = false, false
		registry.get_package(tool.name):install({ version = tool.version }, function(ok)
			completed, installed = true, ok
		end)
		assert(vim.wait(120000, function()
			return completed
		end, 50) and installed, "Mason preparation failed: " .. tool.name)
	end
end

-- Blink's native matcher is an optional plugin asset, prepared explicitly so
-- opening a completion menu during checks cannot initiate a download. A mode
-- without a completion engine never installs the plugin, so there is nothing
-- to prepare.
if mode == "fast" then
	print("Slim preparation completed; the completion matcher is not part of this installation.")
	return
end
if vim.env.NVIM_PREPARE_ASSETS == "0" then
	print("Requested dependency preparation completed; optional plugin assets were not requested.")
	return
end
local blink = data .. "/lazy/blink.cmp"
local target = blink .. "/target/release"
if cache and not vim.uv.fs_stat(target) and vim.uv.fs_stat(cache .. "/lazy/blink.cmp/target/release") then
	if command({ "git", "rev-parse", "HEAD" }, cache .. "/lazy/blink.cmp") == lock["blink.cmp"].commit then
		copy(cache .. "/lazy/blink.cmp/target/release", target)
	end
end
vim.opt.rtp:prepend(blink)
if offline then
	support.verify_blink(data, lock["blink.cmp"].commit)
	print("Dependency preparation completed from the existing locked cache.")
	return
end
require("blink.cmp.config").fuzzy.prebuilt_binaries.download = true
local downloaded, download_error, implementation = false, nil, nil
require("blink.cmp.fuzzy.download").ensure_downloaded(function(err, selected)
	downloaded, download_error, implementation = true, err, selected
end)
assert(
	vim.wait(120000, function()
		return downloaded
	end, 50),
	"Blink matcher preparation timed out"
)
assert(
	not download_error and implementation == "rust",
	"Blink native matcher was not prepared: " .. tostring(download_error)
)
support.verify_blink(data, lock["blink.cmp"].commit)
print("Dependency preparation completed; no language servers or debuggers beyond the check tool set were installed.")
