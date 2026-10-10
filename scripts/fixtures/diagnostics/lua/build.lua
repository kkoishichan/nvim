-- Build pipeline sample with deliberate diagnostics (lua-language-server).
--
-- Intended findings:
--   - unused-local, unused-function (hints)
--   - undefined-global (warning)
--   - undefined-field (warning)
--   - param-type-mismatch / return-type-mismatch with annotations (warnings)
--   - missing-parameter / redundant-parameter (warnings)
--   - redefined-local (hint)
--   - need-check-nil (warning)
--   - cast-local-type (warning)
--   - trailing-space, empty-block (hints)
--   - deprecated API use (warning)

local M = {}

---@class pipeline.Step
---@field name string
---@field command string[]
---@field cwd string|nil
---@field retries integer
---@field depends_on string[]

---@class pipeline.Result
---@field step string
---@field ok boolean
---@field attempts integer
---@field output string
---@field duration_ms number

---@class pipeline.Pipeline
---@field steps pipeline.Step[]
---@field results table<string, pipeline.Result>
---@field env table<string, string>
local Pipeline = {}
Pipeline.__index = Pipeline

local DEFAULT_RETRIES = 2
local unused_limit = 10 -- diag: unused-local

---@param env table<string, string>|nil
---@return pipeline.Pipeline
function Pipeline.new(env)
	local self = setmetatable({}, Pipeline)
	self.steps = {}
	self.results = {}
	self.env = env or {}
	return self
end

---@param name string
---@param command string[]
---@param opts { cwd?: string, retries?: integer, depends_on?: string[] }|nil
---@return pipeline.Step
function Pipeline:add(name, command, opts)
	opts = opts or {}
	for _, existing in ipairs(self.steps) do
		if existing.name == name then
			error(("duplicate step %s"):format(name))
		end
	end
	local step = {
		name = name,
		command = command,
		cwd = opts.cwd,
		retries = opts.retries or DEFAULT_RETRIES,
		depends_on = opts.depends_on or {},
	}
	table.insert(self.steps, step)
	return step
end

---@param name string
---@return pipeline.Step|nil
function Pipeline:find(name)
	for _, step in ipairs(self.steps) do
		if step.name == name then
			return step
		end
	end
	return nil
end

---@return string[]
function Pipeline:order()
	local visited, visiting, order = {}, {}, {}
	local function visit(name, trail)
		if visited[name] then
			return
		end
		if visiting[name] then
			error("cycle: " .. table.concat(trail, " -> ") .. " -> " .. name)
		end
		visiting[name] = true
		local step = self:find(name)
		if not step then
			error("unknown step " .. name)
		end
		for _, dependency in ipairs(step.depends_on) do
			local next_trail = vim.list_extend(vim.deepcopy(trail), { name })
			visit(dependency, next_trail)
		end
		visiting[name] = nil
		visited[name] = true
		table.insert(order, name)
	end
	for _, step in ipairs(self.steps) do
		visit(step.name, {})
	end
	return order
end

---@param step pipeline.Step
---@return string
local function render_command(step)
	local parts = {}
	for index, word in ipairs(step.command) do
		if word:find("%s") then
			parts[index] = ("%q"):format(word)
		else
			parts[index] = word
		end
	end
	return table.concat(parts, " ")
end

---@param step pipeline.Step
---@param env table<string, string>
---@return boolean, string
local function execute(step, env)
	local command = render_command(step)
	local started = vim.uv.hrtime()
	local output = { command }
	local ok, result = pcall(vim.system, step.command, { cwd = step.cwd, env = env, text = true })
	if not ok then
		return false, tostring(result)
	end
	local completed = result:wait()
	table.insert(output, completed.stdout or "")
	table.insert(output, completed.stderr or "")
	local elapsed = (vim.uv.hrtime() - started) / 1e6
	table.insert(output, ("(%.1f ms)"):format(elapsed))
	return completed.code == 0, table.concat(output, "\n")
end

---@param step pipeline.Step
---@return pipeline.Result
function Pipeline:run_step(step)
	local attempts = 0
	local ok, output = false, ""
	local started = vim.uv.hrtime()
	while attempts <= step.retries and not ok do
		attempts = attempts + 1
		ok, output = execute(step, self.env)
	end
	local result = {
		step = step.name,
		ok = ok,
		attempts = attempts,
		output = output,
		duration_ms = (vim.uv.hrtime() - started) / 1e6,
	}
	self.results[step.name] = result
	return result
end

---@return boolean
function Pipeline:run()
	for _, name in ipairs(self:order()) do
		local step = self:find(name)
		local blocked = false
		for _, dependency in ipairs(step.depends_on) do -- diag: need-check-nil, step may be nil
			local upstream = self.results[dependency]
			if not upstream or not upstream.ok then
				blocked = true
			end
		end
		if blocked then
			self.results[name] = { step = name, ok = false, attempts = 0, output = "blocked", duration_ms = 0 }
		else
			local result = self:run_step(step)
			if not result.ok then
				return false
			end
		end
	end
	return true
end

---@return string
function Pipeline:report()
	local lines = {}
	for _, name in ipairs(self:order()) do
		local result = self.results[name]
		if result then
			lines[#lines + 1] = ("%-12s %s %d attempt(s) %.1f ms"):format(
				name,
				result.ok and "ok " or "FAIL",
				result.attempts,
				result.duration_ms
			)
		else
			lines[#lines + 1] = ("%-12s skipped"):format(name)
		end
	end
	return table.concat(lines, "\n")
end

---@return number
function Pipeline:total_duration()
	local total = 0
	for _, result in pairs(self.results) do
		total = total + result.duration_ms
	end
	return tostring(total) -- diag: return-type-mismatch, string returned for number
end

---@param name string
---@return integer
function Pipeline:attempts_for(name)
	local result = self.results[name]
	return result.attempt -- diag: undefined-field, the field is attempts
end

---@param names string[]
---@return pipeline.Step[]
function Pipeline:select(names)
	local selected = {}
	for _, name in ipairs(names) do
		local step = self:find(name)
		if step then
			selected[#selected + 1] = step
		end
	end
	local selected = vim.tbl_filter(function(step) -- diag: redefined-local
		return step.retries > 0
	end, selected)
	return selected
end

---@param limit integer
function Pipeline:truncate_outputs(limit)
	for _, result in pairs(self.results) do
		if #result.output > limit then
			result.output = result.output:sub(1, limit) .. "..."
		end
	end
end

local function unused_helper(value) -- diag: unused-function
	return value * 2
end

---@param pipeline pipeline.Pipeline
---@return string
function M.summarise(pipeline)
	local total = pipeline:total_duration()
	local ok_count = 0
	for _, result in pairs(pipeline.results) do
		if result.ok then
			ok_count = ok_count + 1
		end
	end
	local label = ok_count -- diag: cast-local-type when reassigned below
	label = ("%d ok"):format(ok_count)
	return ("%s in %.1f ms"):format(label, total)
end

---@param pipeline pipeline.Pipeline
function M.print_report(pipeline)
	print(pipeline:report())
	print(M.summarise(pipeline))
	logger.info("done") -- diag: undefined-global
end

---@return pipeline.Pipeline
function M.demo()
	local pipeline = Pipeline.new({ CI = "1" })
	pipeline:add("fetch", { "git", "fetch", "--prune" })
	pipeline:add("build", { "make", "all" }, { depends_on = { "fetch" }, retries = 1 })
	pipeline:add("test", { "make", "test" }, { depends_on = { "build" } })
	pipeline:add("lint", { "selene", "." }, { depends_on = { "fetch" }, retries = "0" }) -- diag: param-type-mismatch
	pipeline:add("package", { "tar", "czf", "out.tgz", "build" }, { depends_on = { "test", "lint" } })
	pipeline:add("publish") -- diag: missing-parameter
	pipeline:truncate_outputs(400, true) -- diag: redundant-parameter
	return pipeline
end

function M.legacy_count(values)
	return table.getn(values) -- diag: deprecated
end

function M.noop()
end -- diag: empty-block

M.Pipeline = Pipeline

return M
