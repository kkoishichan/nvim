#!/usr/bin/env bash
# Run static checks and independent, non-interactive Neovim regression groups.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
MASON_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"
export NVIM_CHECK_ONLY=1 NVIM_APPNAME=nvim
export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0

usage() {
	cat <<'EOF'
Usage: ./scripts/check.sh [--group NAME | NAME] ...

Groups: static, integration, performance, editing_cost, treesitter_predicates, matchup_cache, startup_loading, ui_runtime, scrolling_colors,
        statusline_refresh, scrollview_refresh, ai, languages, projects,
        project_actions, toolchain, terminals, workflow_actions, signature, lifecycle, pdf_lifecycle,
        windows, layout_session, ui_themes, offline_assets, deployment
Optional real-tool groups: workflow_python_js, workflow_native, workflow_java_docs
With no arguments, run the fast groups above. Real-tool groups require their SDKs.
Examples: ./scripts/check.sh performance
          ./scripts/check.sh --group static --group ai
EOF
}

groups=()
add_group() {
	local existing
	case "$1" in
	static | integration | performance | editing_cost | treesitter_predicates | matchup_cache | startup_loading | ui_runtime | scrolling_colors | statusline_refresh | scrollview_refresh | ai | languages | projects | project_actions | toolchain | terminals | workflow_actions | signature | lifecycle | pdf_lifecycle | windows | layout_session | ui_themes | offline_assets | deployment | workflow_python_js | workflow_native | workflow_java_docs) ;;
	*)
		printf 'Unknown check group: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	for existing in ${groups[@]+"${groups[@]}"}; do
		[ "$existing" != "$1" ] || return 0
	done
	groups+=("$1")
}

while [ $# -gt 0 ]; do
	case "$1" in
	--group)
		if [ $# -lt 2 ]; then
			printf '%s\n' '--group requires a group name' >&2
			exit 2
		fi
		add_group "$2"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) add_group "$1" ;;
	esac
	shift
done
if [ "${#groups[@]}" -eq 0 ]; then
	groups=(static integration performance editing_cost treesitter_predicates matchup_cache startup_loading ui_runtime scrolling_colors statusline_refresh scrollview_refresh ai languages projects project_actions toolchain terminals workflow_actions signature lifecycle pdf_lifecycle windows layout_session ui_themes offline_assets deployment)
fi

tool() {
	if [ -x "$MASON_BIN/$1" ]; then
		printf '%s\n' "$MASON_BIN/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	else
		printf 'Missing check dependency: %s\n' "$1" >&2
		return 1
	fi
}

check_static() {
	local stylua selene
	local shell_files=("$ROOT"/scripts/*.sh)
	stylua=$(tool stylua)
	selene=$(tool selene)
	local script_file
	for script_file in "${shell_files[@]}"; do bash -n "$script_file"; done
	if command -v shellcheck >/dev/null 2>&1 || [ -x "$MASON_BIN/shellcheck" ]; then
		for script_file in "${shell_files[@]}"; do "$(tool shellcheck)" "$script_file"; done
	fi
	python3 - "$ROOT/scripts" <<'PY'
import pathlib
import sys
for path in pathlib.Path(sys.argv[1]).glob("*.py"):
    compile(path.read_bytes(), str(path), "exec")
PY
	"$stylua" --check "$ROOT/init.lua" "$ROOT/lua" "$ROOT/after" "$ROOT/scripts"
	"$selene" "$ROOT/init.lua" "$ROOT/lua" "$ROOT/after" "$ROOT/scripts"

	if rg -n 'vim\.validate\s*=|open_floating_preview\s*=|vim\.treesitter\._|vim\.highlight' \
		"$ROOT/init.lua" "$ROOT/lua" "$ROOT/after"; then
		printf 'Unsupported/private Neovim API patch found.\n' >&2
		return 1
	fi
	if command -v jq >/dev/null 2>&1; then
		jq --exit-status 'type == "object"' "$ROOT/lazy-lock.json" >/dev/null
	fi
}

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
verified=0
for group in "${groups[@]}"; do
	printf 'Running %s checks...\n' "$group"
	if [ "$group" = static ]; then
		check_static
		continue
	fi
	if [ "$group" = deployment ]; then
		"$ROOT/scripts/check-deploy.sh"
		continue
	fi
	if [ "$verified" -eq 0 ]; then
		mkdir -p "$TMP_ROOT/verify/cache" "$TMP_ROOT/verify/state" "$TMP_ROOT/verify/config"
		printf 'Verifying locked dependencies before loading the configuration...\n'
		NVIM_TEST_ROOT="$ROOT" XDG_CONFIG_HOME="$TMP_ROOT/verify/config" \
			XDG_CACHE_HOME="$TMP_ROOT/verify/cache" XDG_STATE_HOME="$TMP_ROOT/verify/state" \
			NVIM_LOG_FILE="$TMP_ROOT/verify/nvim.log" \
			nvim --headless -u NONE -i NONE -l "$ROOT/scripts/verify-lock.lua"
		verified=1
	fi
	group_tmp="$TMP_ROOT/$group"
	mkdir -p "$group_tmp/cache" "$group_tmp/state" "$group_tmp/config/nvim"
	# Share only repository code; machine preferences and persistent state stay
	# outside checks. The lock remains the one belonging to this checkout.
	for entry in init.lua lua after spell lazy-lock.json; do
		ln -s "$ROOT/$entry" "$group_tmp/config/nvim/$entry"
	done
	script="$ROOT/scripts/run-check.lua"
	[ "$group" != integration ] || script="$ROOT/scripts/check.lua"
	NVIM_TEST_ROOT="$ROOT" NVIM_TEST_GROUP="$group" NVIM_TEST_TMP="$group_tmp" \
		XDG_CONFIG_HOME="$group_tmp/config" XDG_CACHE_HOME="$group_tmp/cache" XDG_STATE_HOME="$group_tmp/state" NVIM_LOG_FILE="$group_tmp/nvim.log" \
		nvim --headless --cmd 'lua vim.opt.runtimepath:prepend(vim.env.NVIM_TEST_ROOT)' \
		-u "$ROOT/init.lua" -i NONE -l "$script"
done

printf 'All selected checks passed.\n'
