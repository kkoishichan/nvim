#!/usr/bin/env bash
# Prepare optional real-workflow dependencies; the check command never installs.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
destination=${1:?Usage: prepare-python-js.sh /absolute/dependency-directory [--allow-network]}
network=${2:-}
case "$destination" in /*) ;; *) printf 'Use an absolute destination.\n' >&2; exit 2 ;; esac
case "$network" in '' | --allow-network) ;; *) printf 'Unknown option: %s\n' "$network" >&2; exit 2 ;; esac
mkdir -p "$destination"
cp "$root/scripts/fixtures/python-js/package.json" "$root/scripts/fixtures/python-js/package-lock.json" "$destination/"
npm_options=(--offline)
pip_options=(--no-index)
if [ "$network" = --allow-network ]; then
	npm_options=()
	pip_options=()
fi
npm --prefix "$destination" ci "${npm_options[@]}" --cache "${NVIM_WORKFLOW_NPM_CACHE:-$destination/npm-cache}" --ignore-scripts --no-audit --no-fund
python3 -m venv --system-site-packages "$destination/python-env"
"$destination/python-env/bin/python" -m pip install "${pip_options[@]}" --disable-pip-version-check -r "$root/scripts/fixtures/python-js/requirements.txt"
printf '\nPrepared. Run:\nNVIM_WORKFLOW_PYTHON_JS_DEPS=%q ./scripts/check.sh workflow_python_js\n' "$destination"
