#!/usr/bin/env bash
# Run static checks and a clean, non-interactive Neovim startup.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
MASON_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"

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

STYLUA=$(tool stylua)
SELENE=$(tool selene)

bash -n "$ROOT/deploy.sh" "$ROOT/scripts/check.sh"
if command -v shellcheck >/dev/null 2>&1 || [ -x "$MASON_BIN/shellcheck" ]; then
	"$(tool shellcheck)" "$ROOT/deploy.sh" "$ROOT/scripts/check.sh"
fi
if command -v yamllint >/dev/null 2>&1 || [ -x "$MASON_BIN/yamllint" ]; then
	"$(tool yamllint)" "$ROOT/.github/workflows/ci.yml"
fi

"$STYLUA" --check "$ROOT/init.lua" "$ROOT/lua" "$ROOT/after" "$ROOT/scripts/check.lua"
"$SELENE" "$ROOT/init.lua" "$ROOT/lua" "$ROOT/after" "$ROOT/scripts/check.lua"

if rg -n 'vim\.validate\s*=|open_floating_preview\s*=|vim\.treesitter\._|vim\.highlight' \
	"$ROOT/init.lua" "$ROOT/lua" "$ROOT/after"; then
	printf 'Unsupported/private Neovim API patch found.\n' >&2
	exit 1
fi

if command -v jq >/dev/null 2>&1; then
	jq --exit-status 'type == "object"' "$ROOT/lazy-lock.json" >/dev/null
fi

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
NVIM_TEST_TMP="$TMP_ROOT" XDG_CACHE_HOME="$TMP_ROOT/cache" XDG_STATE_HOME="$TMP_ROOT/state" \
	nvim --headless --cmd "set runtimepath^=$ROOT" -u "$ROOT/init.lua" -i NONE \
	-l "$ROOT/scripts/check.lua"

printf 'All checks passed.\n'
