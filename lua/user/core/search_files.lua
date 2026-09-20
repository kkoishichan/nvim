-- A bounded, incremental file walk for machines without search executables.
-- Directory-local ignore rules are inherited; ignored directories and symlinks
-- are never traversed. Callers choose when to yield between iterator steps.
local M = {}
local metadata = { [".git"] = true, [".jj"] = true, [".hg"] = true, [".svn"] = true }

local function rules_at(directory, inherited)
	local rules = vim.list_extend({}, inherited)
	for _, file in ipairs({ ".gitignore", ".ignore" }) do
		local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(directory, file))
		for _, line in ipairs(ok and lines or {}) do
			line = line:gsub("\r$", "")
			while line:sub(-1) == " " and line:sub(-2, -2) ~= "\\" do
				line = line:sub(1, -2)
			end
			if line ~= "" and line:sub(1, 1) ~= "#" then
				local negate = line:sub(1, 1) == "!"
				if negate then
					line = line:sub(2)
				end
				local directory_only = line:sub(-1) == "/"
				line = line:gsub("/$", "")
				local basename = not line:find("/", 1, true)
				line = line:gsub("^/", "")
				local parsed, glob = pcall(vim.glob.to_lpeg, line)
				if parsed then
					rules[#rules + 1] = {
						base = directory == "/" and "/" or directory .. "/",
						glob = glob,
						basename = basename,
						directory_only = directory_only,
						negate = negate,
					}
				end
			end
		end
	end
	return rules
end

local function ignored(path, name, directory, rules)
	local excluded = false
	for _, rule in ipairs(rules) do
		if not rule.directory_only or directory then
			local relative = rule.basename and name or path:sub(#rule.base + 1)
			if rule.glob:match(relative) then
				excluded = not rule.negate
			end
		end
	end
	return excluded
end

function M.iter(root)
	root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p")):gsub("/+$", "")
	if root == "" then
		root = "/"
	end
	local stats = { visited = 0, truncated = false, unreadable = 0 }
	local stack = {}
	local function push(directory, rules)
		local scan = vim.uv.fs_scandir(directory)
		if scan then
			stack[#stack + 1] = { directory = directory, scan = scan, rules = rules_at(directory, rules) }
		else
			stats.unreadable = stats.unreadable + 1
		end
	end
	push(root, {})
	return function()
		if #stack == 0 then
			return nil, true
		end
		if stats.visited >= 50000 then
			stats.truncated = true
			return nil, true
		end
		local frame = stack[#stack]
		local name, kind = vim.uv.fs_scandir_next(frame.scan)
		if not name then
			stack[#stack] = nil
			return nil, false
		end
		stats.visited = stats.visited + 1
		local path = vim.fs.joinpath(frame.directory, name)
		if not metadata[name] and not ignored(path, name, kind == "directory", frame.rules) then
			if kind == "directory" then
				push(path, frame.rules)
			elseif kind == "file" then
				return path, false
			end
		end
		return nil, false
	end,
		stats
end

return M
