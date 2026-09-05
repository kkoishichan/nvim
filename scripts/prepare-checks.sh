#!/usr/bin/env bash
# Explicit dependency preparation. Never call this from the check entrypoint.
# --cache-data reuses Git sources, pinned tools and Blink's native matcher.
# Parsers are built from source; --offline requires them in destination already.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
destination=${1:?Usage: prepare-checks.sh /absolute/environment [--cache-data /absolute/nvim-data] [--offline]}
shift
case "$destination" in /*) ;; *) printf 'Use an absolute environment directory.\n' >&2; exit 2 ;; esac
cache_data=''
offline=0
while [ "$#" -gt 0 ]; do
	case "$1" in
	--cache-data) cache_data=${2:?--cache-data requires a directory}; shift ;;
	--offline) offline=1 ;;
	*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
	esac
	shift
done
for command in nvim git curl tar cc tree-sitter python3; do
	command -v "$command" >/dev/null || { printf 'Missing preparation prerequisite: %s\n' "$command" >&2; exit 1; }
done
mkdir -p "$destination/config" "$destination/data" "$destination/cache" "$destination/state"
if [ ! -e "$destination/config/nvim" ]; then
	ln -s "$root" "$destination/config/nvim"
fi
if [ "$(readlink -f "$destination/config/nvim")" != "$root" ]; then
	printf 'Environment belongs to another checkout: %s\n' "$destination/config/nvim" >&2
	exit 1
fi
export NVIM_TEST_ROOT="$root"
export NVIM_APPNAME=nvim
export NVIM_PREPARE_CACHE_DATA="$cache_data" NVIM_PREPARE_OFFLINE="$offline"
export XDG_CONFIG_HOME="$destination/config" XDG_DATA_HOME="$destination/data"
export XDG_CACHE_HOME="$destination/cache" XDG_STATE_HOME="$destination/state"
unset NVIM_CHECK_ONLY
nvim --headless -u NONE -i NONE -l "$root/scripts/prepare-checks.lua"
NVIM_CHECK_ONLY=1 nvim --headless -u NONE -i NONE -l "$root/scripts/verify-lock.lua"
{
	printf 'export XDG_CONFIG_HOME=%q\n' "$XDG_CONFIG_HOME"
	printf 'export XDG_DATA_HOME=%q\n' "$XDG_DATA_HOME"
	printf 'export XDG_CACHE_HOME=%q\n' "$XDG_CACHE_HOME"
	printf 'export XDG_STATE_HOME=%q\n' "$XDG_STATE_HOME"
	printf 'export NVIM_TEST_ROOT=%q\n' "$root"
	printf 'export NVIM_APPNAME=nvim\n'
	printf 'export NVIM_CHECK_ONLY=1\n'
	# shellcheck disable=SC2016 # Expand PATH when the generated file is sourced.
	printf 'export PATH=%q:"$PATH"\n' "$XDG_DATA_HOME/nvim/mason/bin"
} > "$destination/environment.sh"
printf '\nPrepared. Run:\nsource %q\n./scripts/check.sh\n' "$destination/environment.sh"
