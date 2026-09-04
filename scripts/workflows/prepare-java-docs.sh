#!/usr/bin/env bash
# Prepare pinned Java workflow dependencies outside the user's Maven cache.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
if [ "$#" -ne 1 ]; then
	printf 'Usage: %s TEMP_DEPENDENCY_DIRECTORY\n' "$0" >&2
	exit 2
fi
mkdir -p "$1"
JAVA_DEPS=$(cd -- "$1" && pwd)
mkdir -p "$JAVA_DEPS/project" "$JAVA_DEPS/repository" "$JAVA_DEPS/gradle"
cp -R "$ROOT/scripts/fixtures/java-docs/maven/." "$JAVA_DEPS/project/"
mvn --batch-mode --no-transfer-progress -f "$JAVA_DEPS/project/pom.xml" \
	"-Dmaven.repo.local=$JAVA_DEPS/repository" test-compile
printf 'Java dependencies prepared. Run NVIM_JAVA_WORKFLOW_DEPS=%q ./scripts/check.sh workflow_java_docs\n' "$JAVA_DEPS"
