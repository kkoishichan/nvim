#!/usr/bin/env bash
# Destructive/failure branches run only against generated /tmp fixtures. Git,
# package managers, downloads, plugin sync and tool installation are substituted.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d /tmp/nvim-deploy-check.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
real_nvim=$(command -v nvim)
mkdir -p "$fixture/repository with spaces/scripts" "$fixture/bin"
printf 'new config\n' >"$fixture/repository with spaces/init.lua"
printf '{}\n' >"$fixture/repository with spaces/lazy-lock.json"
for file in deploy-plugins.lua deploy-tools.lua verify-lock.lua prepare-checks.lua check-support.lua deploy-preferences.lua; do
	printf '%s\n' '-- fixture' >"$fixture/repository with spaces/scripts/$file"
done
for tool in dirname basename date stat readlink awk cat cp; do
	ln -s "$(command -v "$tool")" "$fixture/bin/$tool"
done
cat >"$fixture/bin/mutator" <<'STUB'
#!/bin/bash
set -eu
name=${0##*/}
if [ "${FIXTURE_DRY:-0}" = 1 ]; then printf 'unexpected write: %s\n' "$name" >> "$FIXTURE_LOG"; exit 99; fi
case "$name" in
mkdir|mktemp|mv|rm|ln) exec "/bin/$name" "$@" ;;
*) printf 'package:%s %s\n' "$name" "$*" >> "$FIXTURE_LOG"; [ "${FIXTURE_FAIL:-}" != deps ] ;;
esac
STUB
for tool in mkdir mktemp mv rm ln; do ln -s mutator "$fixture/bin/$tool"; done
cat >"$fixture/bin/uname" <<'STUB'
#!/bin/bash
if [ "$1" = -s ]; then printf '%s\n' "${FIXTURE_OS:-Linux}"; else printf '%s\n' "${FIXTURE_ARCH:-x86_64}"; fi
STUB
cat >"$fixture/bin/id" <<'STUB'
#!/bin/bash
printf '0\n'
STUB
cat >"$fixture/bin/fzf" <<'STUB'
#!/bin/bash
printf '%s\n' "${FIXTURE_FZF:-0.65.1}"
STUB
cat >"$fixture/bin/git" <<'STUB'
#!/bin/bash
set -eu
[ "${FIXTURE_DRY:-0}" != 1 ] || { printf 'unexpected git\n' >> "$FIXTURE_LOG"; exit 99; }
printf 'git:%s\n' "$*" >> "$FIXTURE_LOG"
if [ "$1" = clone ]; then
	[ "${FIXTURE_FAIL:-}" != clone ] || exit 41
	destination=${!#}
	/bin/cp -R "$FIXTURE_REPO" "$destination"
else
	case "$3" in
	fetch) [ "${FIXTURE_FAIL:-}" != ref ] || exit 42 ;;
	rev-parse) printf '1234567890123456789012345678901234567890\n' ;;
	checkout)
		if [ "${FIXTURE_FAIL:-}" = concurrent-stage ]; then
			/bin/mkdir -p "$FIXTURE_TARGET"
			printf 'concurrent\n' > "$FIXTURE_TARGET/marker"
		fi
		;;
	*) exit 43 ;;
	esac
fi
STUB
cat >"$fixture/bin/nvim" <<'STUB'
#!/bin/bash
set -eu
if [ "$1" = --version ]; then printf 'NVIM %s\nBuild type: Release\n' "${FIXTURE_NVIM_VERSION:-v0.12.5}"; exit 0; fi
[ "${FIXTURE_DRY:-0}" != 1 ] || { printf 'unexpected nvim\n' >> "$FIXTURE_LOG"; exit 99; }
printf 'nvim:%s;profiles=%s;mode=%s;parsers=%s\n' "$*" "${NVIM_DEPLOY_PROFILES:-}" "${NVIM_MODE:-}" "${NVIM_PARSERS:-}" >> "$FIXTURE_LOG"
if [ -n "${NVIM_DEPLOY_LINK_SOURCE:-}" ]; then
	if [ ! -e "$FIXTURE_CASE/link-attempted" ]; then
		: > "$FIXTURE_CASE/link-attempted"
		case "${FIXTURE_FAIL:-}" in
		link) exit 1 ;;
		concurrent-link)
			/bin/mkdir -p "$NVIM_DEPLOY_LINK_TARGET"
			printf 'concurrent\n' > "$NVIM_DEPLOY_LINK_TARGET/marker"
			exit 1 ;;
		esac
	fi
	[ ! -e "$NVIM_DEPLOY_LINK_TARGET" ] && [ ! -L "$NVIM_DEPLOY_LINK_TARGET" ] || exit 1
	/bin/ln -s "$NVIM_DEPLOY_LINK_SOURCE" "$NVIM_DEPLOY_LINK_TARGET"
	exit 0
fi
case "$*" in
*deploy-preferences.lua*)
	# The real script merges into the staged file; the fixture only records that
	# the deployment asked for a mode and with which value.
	printf '{"runtime":{"mode":"%s"}}\n' "$NVIM_DEPLOY_EDITOR_MODE" > "$NVIM_DEPLOY_PREFERENCES"
	exit 0 ;;
esac
case "$*" in
*deploy-plugins.lua*|*deploy-tools.lua*)
	[ "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$NVIM_DEPLOY_ROOT" ] || exit 91 ;;
*prepare-checks.lua*)
	[ "$NVIM_PREPARE_PARSERS" = 1 ] && [ "$NVIM_PREPARE_ASSETS" = 1 ] && [ "$NVIM_PREPARE_TOOLS" = 0 ] || exit 92
	[ "$NVIM_PREPARE_NVIM_VERSION" = "${FIXTURE_NVIM_VERSION:-v0.12.5}" ] || exit 93 ;;
*verify-lock.lua*)
	[ "$NVIM_VERIFY_PARSERS" = 1 ] && [ "$NVIM_VERIFY_ASSETS" = 1 ] && [ "$NVIM_VERIFY_TOOLS" = 0 ] || exit 94 ;;
esac
case "$*" in
*deploy-plugins.lua*) [ "${FIXTURE_FAIL:-}" != sync ] || exit 21 ;;
*prepare-checks.lua*) [ "${FIXTURE_FAIL:-}" != prepare ] || exit 21 ;;
*verify-lock.lua*) [ "${FIXTURE_FAIL:-}" != verify ] || exit 21 ;;
*deploy-tools.lua*) [ "${FIXTURE_FAIL:-}" != tools ] || exit 30 ;;
esac
STUB
cat >"$fixture/bin/available" <<'STUB'
#!/bin/bash
[ "${FIXTURE_DRY:-0}" != 1 ] || { printf 'unexpected executable\n' >> "$FIXTURE_LOG"; exit 99; }
# An unexpected network/download branch must fail, never reach the real network.
case "${0##*/}" in curl|tar|unzip) exit 98 ;; esac
exit 0
STUB
for tool in curl tar unzip gzip rg cc fd; do ln -s available "$fixture/bin/$tool"; done
cat >"$fixture/bin/tree-sitter" <<'STUB'
#!/bin/bash
printf 'tree-sitter 0.26.9\n'
STUB
chmod +x "$fixture/bin/"{mutator,uname,id,fzf,git,nvim,available,tree-sitter}
export FIXTURE_REPO="$fixture/repository with spaces"
new_case() {
	FIXTURE_CASE="$fixture/$1"
	mkdir -p "$FIXTURE_CASE"
	FIXTURE_TARGET="$FIXTURE_CASE/target with spaces"
	FIXTURE_LOG="$FIXTURE_CASE/calls.log"
	: >"$FIXTURE_LOG"
	export FIXTURE_CASE FIXTURE_TARGET FIXTURE_LOG
}
expect_code() {
	local expected=$1 code=0
	shift
	PATH="$fixture/bin" /bin/bash "$root/scripts/deploy.sh" --config-dir "$FIXTURE_TARGET" --repo "$FIXTURE_REPO" "$@" >"$FIXTURE_CASE/output" 2>&1 || code=$?
	if [ "$code" -ne "$expected" ]; then
		cat "$FIXTURE_CASE/output"
		printf 'Expected %s, got %s\n' "$expected" "$code" >&2
		exit 1
	fi
	if [ "$expected" -ne 0 ] && rg -q 'Deployment complete' "$FIXTURE_CASE/output"; then
		printf 'Failed deployment claimed success\n' >&2
		exit 1
	fi
}
original() {
	mkdir -p "$FIXTURE_TARGET"
	printf 'original\n' >"$FIXTURE_TARGET/marker"
	printf '{"tools":{"prefer_mason":true}}\n' >"$FIXTURE_TARGET/preferences.json"
}
assert_original() { [ "$(cat "$FIXTURE_TARGET/marker")" = original ]; }
assert_backup() {
	local backups=("$FIXTURE_CASE"/nvim.backup.*/config/marker)
	[ "${#backups[@]}" -eq 1 ] && [ "$(cat "${backups[0]}")" = original ]
}
assert_no_release() {
	local releases=("$FIXTURE_CASE"/.nvim-release.*)
	[ ! -e "${releases[0]}" ]
}
# Simulated package-manager inventories cover all five branches without invoking
# any package manager. All mutations are guarded even when --no-deps is absent.
for manager in pacman apt-get dnf zypper brew; do
	new_case "dry-$manager"
	ln -s mutator "$fixture/bin/$manager"
	FIXTURE_OS=Linux
	[ "$manager" != brew ] || FIXTURE_OS=Darwin
	export FIXTURE_OS
	export FIXTURE_DRY=1
	expect_code 0 --dry-run --profile full --dict --with-extras --ref feature/replay --nvim-version v0.12.5
	[ ! -e "$FIXTURE_TARGET" ] && [ ! -s "$FIXTURE_LOG" ]
	rg -q 'fzf' "$FIXTURE_CASE/output"
	rg -q 'feature/replay' "$FIXTURE_CASE/output"
	case "$manager" in
	pacman) rg -q 'jdk21-openjdk' "$FIXTURE_CASE/output" ;;
	apt-get) rg -q 'openjdk-21-jdk' "$FIXTURE_CASE/output" ;;
	dnf | zypper) rg -q 'java-21-openjdk-devel' "$FIXTURE_CASE/output" ;;
	brew)
		rg -q 'openjdk@21' "$FIXTURE_CASE/output"
		rg -q 'nvim-macos-x86_64' "$FIXTURE_CASE/output"
		;;
	esac
	rm "$fixture/bin/$manager"
done
unset FIXTURE_DRY
export FIXTURE_OS=Linux
ln -s mutator "$fixture/bin/apt-get"
new_case minimal-plan
FIXTURE_DRY=1 expect_code 0 --dry-run
if rg -q 'nodejs|openjdk|golang|cargo|texlive' "$FIXTURE_CASE/output"; then
	printf 'Minimal profile requested unrelated SDKs\n' >&2
	exit 1
fi
for failure in clone ref prepare sync verify; do
	new_case "$failure"
	original
	export FIXTURE_FAIL=$failure
	code=20
	case "$failure" in prepare | sync | verify) code=21 ;; esac
	expect_code "$code" --no-deps --ref release/test
	assert_original
	assert_no_release
done
new_case dependency-failure
original
export FIXTURE_FAIL=deps
expect_code 10 --profile python
assert_original
[ ! -s "$FIXTURE_CASE/link-attempted" ]
new_case old-fzf
original
export FIXTURE_FAIL="" FIXTURE_FZF=0.35.1
expect_code 10 --no-deps
assert_original
unset FIXTURE_FZF
new_case rollback
original
export FIXTURE_FAIL=link
expect_code 20 --no-deps
assert_original
assert_backup
assert_no_release
new_case concurrent-before-switch
export FIXTURE_FAIL=concurrent-stage
expect_code 20 --no-deps
[ "$(cat "$FIXTURE_TARGET/marker")" = concurrent ]
assert_no_release
new_case concurrent-at-switch
original
export FIXTURE_FAIL=concurrent-link
expect_code 20 --no-deps
[ "$(cat "$FIXTURE_TARGET/marker")" = concurrent ]
assert_backup
assert_no_release
new_case mason-partial
original
export FIXTURE_FAIL=tools
expect_code 30 --no-deps --profile python --profile web
[ -L "$FIXTURE_TARGET" ] && [ "$(cat "$FIXTURE_TARGET/init.lua")" = 'new config' ]
assert_backup
rg -q 'profiles=python,web' "$FIXTURE_LOG"
new_case success
original
export FIXTURE_FAIL=""
expect_code 0 --no-deps --ref 1234567890123456789012345678901234567890 --profile java
[ -L "$FIXTURE_TARGET" ]
assert_backup
rg -q 'profiles=java' "$FIXTURE_LOG"
[ "$(cat "$FIXTURE_TARGET/preferences.json")" = '{"tools":{"prefer_mason":true}}' ]
rg -q 'Deployment complete at commit' "$FIXTURE_CASE/output"
new_case alternate-neovim
export FIXTURE_NVIM_VERSION=v0.12.4
expect_code 0 --no-deps --nvim-version 0.12.4
unset FIXTURE_NVIM_VERSION
new_case deferred
original
expect_code 0 --no-deps --no-sync --mason
assert_backup
if rg -q 'deploy-tools.lua|deploy-plugins.lua' "$FIXTURE_LOG"; then
	printf 'Deferred deployment started installation\n' >&2
	exit 1
fi
# A slim server installation: the fast plugin and parser set, no language tools
# unless a group is asked for, and the mode written down so a detached shell
# keeps it.
new_case fast-plan
FIXTURE_DRY=1 expect_code 0 --dry-run --editor-mode fast --parsers rust,go
rg -q 'editor mode: fast' "$FIXTURE_CASE/output"
rg -q 'Fast editor mode' "$FIXTURE_CASE/output"
rg -q 'Additional Tree-sitter parsers: rust,go' "$FIXTURE_CASE/output"
rg -q 'No Mason tool group was selected' "$FIXTURE_CASE/output"
if rg -q 'restore only pinned Mason profiles' "$FIXTURE_CASE/output"; then
	printf 'Fast plan promised a Mason restore\n' >&2
	exit 1
fi
new_case fast-success
original
export FIXTURE_FAIL=""
expect_code 0 --no-deps --editor-mode fast --parsers rust
[ -L "$FIXTURE_TARGET" ]
assert_backup
rg -q 'mode=fast;parsers=rust' "$FIXTURE_LOG"
[ "$(cat "$FIXTURE_TARGET/preferences.json")" = '{"runtime":{"mode":"fast"}}' ]
if rg -q 'deploy-tools.lua' "$FIXTURE_LOG"; then
	printf 'Fast deployment restored Mason tools without a selected group\n' >&2
	exit 1
fi
rg -q 'fast mode, tools: none' "$FIXTURE_CASE/output"
new_case fast-with-tools
original
expect_code 0 --no-deps --editor-mode fast --profile python
rg -q 'profiles=python' "$FIXTURE_LOG"
rg -q 'deploy-tools.lua' "$FIXTURE_LOG"
new_case bad-arguments
expect_code 2 --profile nonexistent
expect_code 2 --nvim-version latest
expect_code 2 --editor-mode turbo
expect_code 2 --parsers rust
expect_code 2 --editor-mode fast --parsers 'rust;rm -rf /'
expect_code 2 --ref

# Real Lua profile selection and failure propagation, with only external install
# operations stubbed; these checks never start Lazy or change the user's Mason.
cat >"$fixture/profile-check.lua" <<'LUA'
vim.opt.rtp:prepend(vim.env.NVIM_DEPLOY_CHECK_ROOT)
local tools = require("user.toolchain")
local function names(profiles)
	local selected = {}
	for _, item in ipairs(tools.ensure_installed(profiles)) do
		assert(item.version == tools.version(item[1]))
		assert(not selected[item[1]], "Duplicated profile tool")
		selected[item[1]] = true
	end
	return selected
end
local minimal = names("minimal")
assert(minimal.stylua and minimal.selene and minimal.ruff and minimal.shellcheck)
assert(not minimal.jdtls and not minimal.debugpy and not minimal.vtsls)
local combined = names({ "python", "web", "python" })
assert(combined.debugpy and combined.vtsls and combined["js-debug-adapter"] and not combined.jdtls)
assert(#tools.ensure_installed("full") == #tools.packages)
assert(not pcall(tools.ensure_installed, "missing"))
local copy = tools.ensure_installed("minimal")
copy[1].version = "mutated"
assert(tools.version(copy[1][1]) ~= "mutated")
-- Public installer callback failures must produce a failing process, even if
-- package:is_installed() says an older package remains present.
if vim.env.NVIM_DEPLOY_CHECK_FAILURE == "tools" then
	tools.ensure_installed = function() return { { "fixture", version = "1" } } end
	package.loaded.lazy = { load = function() end }
	package.loaded["mason-registry"] = {
		refresh = function(callback) callback(true) end,
		get_package = function()
			return {
				is_installed = function() return true end,
				get_installed_version = function() return "0" end,
				is_installing = function() return false end,
				install = function(_, _, callback) callback(false); return {} end,
			}
		end,
	}
	dofile(vim.env.NVIM_DEPLOY_CHECK_ROOT .. "/scripts/deploy-tools.lua")
elseif vim.env.NVIM_DEPLOY_CHECK_FAILURE == "plugins" or vim.env.NVIM_DEPLOY_CHECK_FAILURE == "lock" or vim.env.NVIM_DEPLOY_CHECK_FAILURE == "startup" then
	vim.env.NVIM_DEPLOY_ROOT = vim.env.NVIM_DEPLOY_CHECK_TMP .. "/plugin-helper"
	vim.fn.mkdir(vim.env.NVIM_DEPLOY_ROOT, "p")
	vim.fn.writefile({ vim.json.encode({ fixture = { branch = "main", commit = string.rep("a", 40) } }) }, vim.env.NVIM_DEPLOY_ROOT .. "/lazy-lock.json")
	package.loaded["user.lazy"] = true
	vim.g.lazy_did_setup = true
	local lock_path = vim.env.NVIM_DEPLOY_ROOT .. "/lazy-lock.json"
	vim.fn.writefile(vim.fn.readfile(lock_path, "b"), lock_path .. ".before", "b")
	if vim.env.NVIM_DEPLOY_CHECK_FAILURE == "startup" then vim.v.errmsg = "fixture startup failure" end
	package.loaded.lazy = {
		load = function() end, build = function() vim.fn.writefile({ "MUTATED" }, lock_path) end,
		plugins = function() return {{ name = "fixture", build = true, _ = { tasks = {{
			has_errors = function() return vim.env.NVIM_DEPLOY_CHECK_FAILURE == "plugins" end, output = function() return "build failed" end,
		}} } }} end,
	}
	dofile(vim.env.NVIM_DEPLOY_CHECK_ROOT .. "/scripts/deploy-plugins.lua")
end
LUA
# The real preference writer must record the mode without losing anything the
# host already configured.
mkdir -p "$fixture/preferences"
printf '{"tools":{"prefer_mason":true},"format":{"timeout_ms":900}}\n' >"$fixture/preferences/preferences.json"
NVIM_DEPLOY_PREFERENCES="$fixture/preferences/preferences.json" NVIM_DEPLOY_EDITOR_MODE=fast \
	"$real_nvim" --headless -u NONE -i NONE -l "$root/scripts/deploy-preferences.lua" >/dev/null
NVIM_DEPLOY_CHECK_FILE="$fixture/preferences/preferences.json" "$real_nvim" --headless -u NONE -i NONE \
	--cmd 'lua local v = vim.json.decode(table.concat(vim.fn.readfile(vim.env.NVIM_DEPLOY_CHECK_FILE), "\n")); assert(v.runtime.mode == "fast", "mode not recorded"); assert(v.tools.prefer_mason == true and v.format.timeout_ms == 900, "existing preferences were lost")' +qa

mkdir -p "$fixture/state" "$fixture/cache"
for failure in none tools plugins lock startup; do
	code=0
	NVIM_DEPLOY_CHECK_ROOT="$root" NVIM_DEPLOY_CHECK_TMP="$fixture" NVIM_DEPLOY_CHECK_FAILURE="$failure" \
		XDG_STATE_HOME="$fixture/state" XDG_CACHE_HOME="$fixture/cache" NVIM_LOG_FILE="$fixture/nvim.log" \
		"$real_nvim" --headless -u NONE -i NONE -l "$fixture/profile-check.lua" >"$fixture/lua-$failure.log" 2>&1 || code=$?
	case "$failure" in none) expected=0 ;; tools) expected=30 ;; plugins | lock | startup) expected=21 ;; esac
	if [ "$code" -ne "$expected" ]; then
		cat "$fixture/lua-$failure.log"
		printf 'Lua %s: expected %s got %s\n' "$failure" "$expected" "$code" >&2
		exit 1
	fi
	if [ "$expected" -eq 21 ]; then cmp "$fixture/plugin-helper/lazy-lock.json.before" "$fixture/plugin-helper/lazy-lock.json"; fi
done
printf 'Deployment fixtures passed: 5 platform plans, profiles, editor modes, parser selection, failure recovery, concurrency, exit codes.\n'
