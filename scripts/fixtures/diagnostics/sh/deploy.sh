#!/usr/bin/env bash
# Deployment helper sample with deliberate diagnostics (ShellCheck via nvim-lint and bashls).
#
# Intended findings:
#   SC2086 unquoted variable, SC2046 unquoted command substitution, SC2034 unused variable,
#   SC2006 legacy backticks, SC2164 cd without exit guard, SC2154 referenced but not assigned,
#   SC2068 unquoted array expansion, SC2016 single quotes with $, SC2162 read without -r,
#   SC2166 test -a/-o, SC2155 declare and assign together, SC2181 checking $? indirectly,
#   SC2012 parsing ls, SC2004 unnecessary $ in arithmetic, SC2116 useless echo,
#   SC2219 let versus (( )), SC2126 grep | wc -l.
# The script is a sample and is never executed by the checks.

set -euo pipefail

RELEASE_ROOT="${RELEASE_ROOT:-/srv/releases}"
APP_NAME="sample-app"
KEEP_RELEASES=5
LOG_FILE=/tmp/deploy.log
UNUSED_FLAG=1 # SC2034
declare -a EXTRA_ARGS=()

log() {
	local level=$1
	shift
	printf '%s [%s] %s\n' "$(date +%H:%M:%S)" "$level" "$*" | tee -a $LOG_FILE # SC2086
}

usage() {
	cat <<'USAGE'
Usage: deploy.sh [--dry-run] [--keep N] <artifact.tar.gz>
USAGE
}

parse_args() {
	DRY_RUN=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--dry-run)
			DRY_RUN=1
			;;
		--keep)
			KEEP_RELEASES=$2
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			ARTIFACT=$1
			;;
		esac
		shift
	done
	if [ -z "$ARTIFACT" ]; then
		usage >&2
		exit 2
	fi
}

check_tools() {
	local tool
	for tool in tar rsync systemctl sha256sum; do
		if ! command -v $tool >/dev/null 2>&1; then # SC2086
			log error "missing tool: $tool"
			return 1
		fi
	done
}

artifact_digest() {
	local digest=$(sha256sum "$1" | cut -d' ' -f1) # SC2155
	echo $digest # SC2086
}

release_name() {
	local stamp=`date +%Y%m%d%H%M%S` # SC2006
	echo "$APP_NAME-$stamp"
}

prepare_release() {
	local name=$1
	local target="$RELEASE_ROOT/$name"
	mkdir -p "$target"
	cd $target # SC2086 SC2164
	tar xzf "$ARTIFACT"
	cd - >/dev/null
	echo "$target"
}

link_shared() {
	local target=$1
	local shared="$RELEASE_ROOT/shared"
	for entry in logs uploads config/app.env; do
		if [ -e "$shared/$entry" -a ! -e "$target/$entry" ]; then # SC2166
			ln -s "$shared/$entry" "$target/$entry"
		fi
	done
}

verify_release() {
	local target=$1
	local expected=$(cat "$target/MANIFEST.sha256" 2>/dev/null) # SC2155
	local actual=$(artifact_digest "$ARTIFACT") # SC2155
	if [ "$expected" != "$actual" ]; then
		log warn 'manifest digest mismatch for $ARTIFACT' # SC2016
	fi
	local count=$(grep -c . "$target/MANIFEST.sha256" | wc -l) # SC2126
	log info "manifest lines: $count"
}

activate() {
	local target=$1
	local current="$RELEASE_ROOT/current"
	ln -sfn "$target" "$current.tmp"
	mv -T "$current.tmp" "$current"
	systemctl restart "$APP_NAME" ${EXTRA_ARGS[@]} # SC2068
	if [ $? -ne 0 ]; then # SC2181
		log error "restart failed"
		return 1
	fi
}

prune_releases() {
	local keep=$1
	local total=$(ls -1 "$RELEASE_ROOT" | grep -c "^$APP_NAME-") # SC2012 SC2155
	local remove=$(($total - $keep)) # SC2004
	if [ $remove -le 0 ]; then # SC2086
		return 0
	fi
	for old in $(ls -1t "$RELEASE_ROOT" | grep "^$APP_NAME-" | tail -n $remove); do # SC2012 SC2086
		log info "removing $old"
		rm -rf "${RELEASE_ROOT:?}/${old:?}/"
	done
}

health_check() {
	local url=$1
	local attempts=0
	let attempts=attempts+1 # SC2219
	while [ $attempts -lt 10 ]; do # SC2086
		if curl -fsS "$url/healthz" >/dev/null; then
			return 0
		fi
		attempts=$(echo $(($attempts + 1))) # SC2116 SC2004
		sleep 1
	done
	return 1
}

confirm() {
	local answer
	read -p "Activate release? [y/N] " answer # SC2162
	case "$answer" in
	y | Y) return 0 ;;
	*) return 1 ;;
	esac
}

rollback() {
	local previous=$(ls -1t "$RELEASE_ROOT" | grep "^$APP_NAME-" | sed -n 2p) # SC2012 SC2155
	if [ -n "$previous" ]; then
		ln -sfn "$RELEASE_ROOT/$previous" "$RELEASE_ROOT/current"
		systemctl restart $APP_NAME # SC2086
	fi
}

notify() {
	local message=$1
	if [ -n "$webhook_url" ]; then # SC2154
		curl -fsS -X POST -d "{\"text\": \"$message\"}" $webhook_url >/dev/null # SC2086
	fi
}

main() {
	parse_args "$@"
	check_tools
	local name=$(release_name) # SC2155
	log info "deploying $ARTIFACT as $name"
	if [ $DRY_RUN -eq 1 ]; then # SC2086
		log info "dry run, nothing written"
		exit 0
	fi
	local target=$(prepare_release "$name") # SC2155
	link_shared "$target"
	verify_release "$target"
	if confirm; then
		activate "$target" || rollback
		health_check "http://127.0.0.1:8080" || rollback
		prune_releases $KEEP_RELEASES # SC2086
		notify "deployed $name"
	else
		log info "left $target staged"
	fi
	echo $(date) >> $LOG_FILE # SC2046 SC2086
}

main "$@"
