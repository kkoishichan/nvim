#!/usr/bin/env bash
# Run static checks and independent, non-interactive Neovim regression groups.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
MASON_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"

usage() {
	cat <<'EOF'
Usage: ./scripts/check.sh [--group NAME | NAME] ...

Groups: static, integration, performance, ai, languages, projects,
        project_actions, toolchain, terminals, workflow_actions
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
	static | integration | performance | ai | languages | projects | project_actions | toolchain | terminals | workflow_actions | workflow_python_js | workflow_native | workflow_java_docs) ;;
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
	groups=(static integration performance ai languages projects project_actions toolchain terminals workflow_actions)
fi

tool() {
	if command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	elif [ -x "$MASON_BIN/$1" ]; then
		printf '%s\n' "$MASON_BIN/$1"
	else
		printf 'Missing check dependency: %s\n' "$1" >&2
		return 1
	fi
}

check_static() {
	local stylua selene
	stylua=$(tool stylua)
	selene=$(tool selene)
	bash -n "$ROOT/scripts/deploy.sh" "$ROOT/scripts/check.sh"
	if command -v shellcheck >/dev/null 2>&1 || [ -x "$MASON_BIN/shellcheck" ]; then
		"$(tool shellcheck)" "$ROOT/scripts/deploy.sh" "$ROOT/scripts/check.sh"
	fi
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
for group in "${groups[@]}"; do
	printf 'Running %s checks...\n' "$group"
	if [ "$group" = static ]; then
		check_static
		continue
	fi
	group_tmp="$TMP_ROOT/$group"
	mkdir -p "$group_tmp/cache" "$group_tmp/state"
	script="$ROOT/scripts/run-check.lua"
	[ "$group" != integration ] || script="$ROOT/scripts/check.lua"
	NVIM_TEST_ROOT="$ROOT" NVIM_TEST_GROUP="$group" NVIM_TEST_TMP="$group_tmp" \
		XDG_CACHE_HOME="$group_tmp/cache" XDG_STATE_HOME="$group_tmp/state" NVIM_LOG_FILE="$group_tmp/nvim.log" \
		nvim --headless --cmd 'lua vim.opt.runtimepath:prepend(vim.env.NVIM_TEST_ROOT)' \
		-u "$ROOT/init.lua" -i NONE -l "$script"
done

printf 'All selected checks passed.\n'
