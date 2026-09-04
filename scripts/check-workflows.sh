#!/usr/bin/env bash
# Real language servers, tests, formatters and debug adapters; no installs.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [ "$#" -eq 0 ]; then
	set -- workflow_python_js workflow_native workflow_java_docs
fi
exec "$ROOT/scripts/check.sh" "$@"
