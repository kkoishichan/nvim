return function(tmp)
	local root = assert(vim.env.NVIM_TEST_ROOT, "NVIM_TEST_ROOT is required")
	local work = tmp .. "/native"
	local fixture = root .. "/scripts/fixtures/native"
	local helper = dofile(root .. "/scripts/workflows/native.lua")
	local toolchain = require("user.toolchain")
	for _, name in ipairs({
		"cc",
		"c++",
		"cmake",
		"ctest",
		"go",
		"cargo",
		"clangd",
		"gopls",
		"rust-analyzer",
		"dlv",
		"codelldb",
	}) do
		assert(toolchain.executable(name), "Native workflow prerequisite is unavailable: " .. name)
	end
	vim.fn.mkdir(work, "p")
	for _, entry in ipairs(vim.fn.glob(fixture .. "/**/*", false, true)) do
		local destination = work .. entry:sub(#fixture + 1)
		if vim.fn.isdirectory(entry) == 1 then
			vim.fn.mkdir(destination, "p")
		else
			vim.fn.writefile(vim.fn.readfile(entry, "b"), destination, "b")
		end
	end
	vim.env.GOCACHE = tmp .. "/go-cache"
	vim.env.GOMODCACHE = tmp .. "/go-mod-cache"
	vim.env.GOPROXY = "off"
	vim.env.GOSUMDB = "off"
	vim.env.GOFLAGS = "-buildvcs=false"
	vim.env.CARGO_NET_OFFLINE = "true"

	local cpp = work .. "/c_cpp"
	helper.command({ "cmake", "-S", cpp, "-B", cpp .. "/build", "-DCMAKE_BUILD_TYPE=Debug" }, cpp)
	helper.command({ "cmake", "--build", cpp .. "/build" }, cpp)
	helper.command({ "ctest", "--test-dir", cpp .. "/build", "--output-on-failure" }, cpp)
	helper.command(
		{ "ctest", "--test-dir", cpp .. "/build", "--output-on-failure" },
		cpp,
		"failure",
		{ NVIM_NATIVE_FAIL = "1" }
	)
	assert(vim.uv.fs_symlink(cpp .. "/build/compile_commands.json", cpp .. "/compile_commands.json"))
	assert(
		#vim.json.decode(table.concat(vim.fn.readfile(cpp .. "/compile_commands.json"), "\n")) == 2,
		"CMake did not emit both compile commands"
	)
	for _, case in ipairs({
		{ "main.c", "native_c", "square", "int square(", "int invalid = unknown_native_identifier;" },
		{ "main.cpp", "native_cpp", "doubled", "int doubled(", 'int invalid = "nvim_type_error";' },
	}) do
		local source = cpp .. "/" .. case[1]
		local original = vim.fn.readfile(source)
		vim.fn.writefile(vim.list_extend(vim.deepcopy(original), { case[5] }), source)
		local build_error = helper.command({ "cmake", "--build", cpp .. "/build" }, cpp, "failure")
		assert(build_error:find(case[1], 1, true), "Build did not report the intentional source error")
		vim.fn.writefile(original, source)
		helper.command({ "cmake", "--build", cpp .. "/build" }, cpp)
		helper.command({ cpp .. "/build/" .. case[2], "fail" }, cpp, "failure")
		helper.language(cpp .. "/" .. case[1], cpp, "clangd", case[3], case[4], case[5])
		helper.breakpoint(cpp .. "/" .. case[1], cpp, {
			type = "codelldb",
			program = cpp .. "/build/" .. case[2],
			initCommands = { "settings set target.disable-aslr false" },
		})
	end

	local go = work .. "/go"
	helper.command({ "go", "test", "./..." }, go)
	helper.command({ "go", "test", "-count=1", "./..." }, go, "failure", { NVIM_NATIVE_FAIL = "1" })
	helper.command({ "go", "build", "-buildvcs=false", "-gcflags=all=-N -l", "-o", go .. "/native_go", "." }, go)
	helper.language(go .. "/main.go", go, "gopls", "Square", "func Square(", 'var invalid int = "nvim_type_error"')
	helper.neotest(go .. "/main_test.go", go)
	helper.breakpoint(go .. "/main.go", go, { type = "go", mode = "exec", program = go .. "/native_go" })

	local rust = work .. "/rust"
	helper.command({ "cargo", "test", "--offline" }, rust)
	helper.command({ "cargo", "test", "--offline" }, rust, "failure", { NVIM_NATIVE_FAIL = "1" })
	helper.command({ "cargo", "clippy", "--offline", "--", "-D", "warnings" }, rust)
	local source = rust .. "/src/main.rs"
	local original = vim.fn.readfile(source)
	local lint_error = vim.deepcopy(original)
	lint_error[2] = "    value * value + 0 // BREAKPOINT"
	vim.fn.writefile(lint_error, source)
	local clippy = helper.command({ "cargo", "clippy", "--offline", "--", "-D", "warnings" }, rust, "failure")
	assert(clippy:find("identity", 1, true), "Clippy did not identify the intentional identity operation")
	vim.fn.writefile(original, source)
	helper.command({ "cargo", "build", "--offline" }, rust)
	helper.language(
		source,
		rust,
		"rust-analyzer",
		"square",
		"fn square(",
		'fn invalid() { let _bad: i32 = "nvim_type_error"; }'
	)
	helper.neotest(source, rust)
	helper.breakpoint(source, rust, {
		type = "codelldb",
		program = rust .. "/target/debug/nvim-native-workflow",
		initCommands = { "settings set target.disable-aslr false" },
	})
	print(
		"Native workflow evidence: C/C++, Go and Rust builds, test pass/fail, LSP diagnostics/definitions, four breakpoint hits; Go/Rust Neotest and Clippy verified."
	)
end
