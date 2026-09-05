#!/usr/bin/env bash
# Restore an explicit configuration revision without replacing a working config
# until its clone, checkout and plugin verification have all succeeded.
set -euo pipefail

repo_url=https://github.com/kkoishichan/nvim.git
config_ref=main
nvim_version=v0.12.5
tree_sitter_version=0.26.9
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
local_bin="$HOME/.local/bin"
local_opt="$HOME/.local/opt"
dict_db="$HOME/.local/share/trans/ultimate.db"
dict_url=https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip
profiles=()
dry_run=0
skip_deps=0
skip_sync=0
with_extras=0
with_dict=0
pkg_mgr=""
sudo_cmd=()
stage_dir=""
backup_dir=""
backup_taken=0
committed=0
deps_partial=0
tools_partial=0
dict_partial=0

usage() {
	cat <<'USAGE'
Usage: ./scripts/deploy.sh [options]
  --ref REF               Configuration branch, tag or commit (default: main)
  --nvim-version vX.Y.Z    Exact Neovim release (default: v0.12.5)
  --profile NAME          minimal/python/web/java/native/docs/full; repeatable
                          Every profile includes minimal. Default: minimal.
  --mason                 Alias for --profile full (complete pinned catalog)
  --dry-run               Print the complete plan; no writes or installations
  --repo URL              Alternate configuration repository
  --ssh                   Use git@github.com:kkoishichan/nvim.git
  --config-dir PATH       Configuration destination (default: XDG config/nvim)
  --no-deps               Skip system package installation; still validate tools
  --no-sync               Defer plugin and Mason restoration to a later run
  --with-extras           Add lazygit, SQLite, ImageMagick and Poppler
  --dict                  Download the optional ECDICT database
  -h, --help              Show help
Exit codes: 2 arguments; 10 dependencies; 20 clone/ref/switch;
            21 plugins; 30 partial Mason tools; 40 optional dictionary.
USAGE
}
info() { printf '==> %s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
fail() {
	local code=$1
	shift
	printf 'Error: %s\n' "$*" >&2
	exit "$code"
}
value() { [ "$#" -ge 2 ] && [ -n "$2" ] || fail 2 "$1 requires a value"; }
add_profile() {
	local existing
	case "$1" in minimal | python | web | java | native | docs | full) ;;
	*) fail 2 "Unknown profile: $1" ;;
	esac
	for existing in ${profiles[@]+"${profiles[@]}"}; do
		[ "$existing" != "$1" ] || return 0
	done
	profiles+=("$1")
}
parse_arguments() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--ref)
			value "$@"
			config_ref=$2
			shift
			;;
		--nvim-version)
			value "$@"
			nvim_version=$2
			shift
			;;
		--profile)
			value "$@"
			add_profile "$2"
			shift
			;;
		--repo)
			value "$@"
			repo_url=$2
			shift
			;;
		--config-dir)
			value "$@"
			config_dir=$2
			shift
			;;
		--ssh) repo_url=git@github.com:kkoishichan/nvim.git ;;
		--mason) add_profile full ;;
		--dry-run) dry_run=1 ;;
		--no-deps) skip_deps=1 ;;
		--no-sync) skip_sync=1 ;;
		--with-extras) with_extras=1 ;;
		--dict) with_dict=1 ;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			usage >&2
			fail 2 "Unknown option: $1"
			;;
		esac
		shift
	done
	[ "${#profiles[@]}" -gt 0 ] || profiles=(minimal)
	[[ "$nvim_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 2 '--nvim-version must be an exact release such as v0.12.5'
	nvim_version="v${nvim_version#v}"
	version_numbers=${nvim_version#v}
	version_major=${version_numbers%%.*}
	version_minor=${version_numbers#*.}
	version_minor=${version_minor%%.*}
	[ "$version_major" -gt 0 ] || [ "$version_minor" -ge 12 ] || fail 2 'This configuration requires Neovim 0.12 or newer'
	case "$config_ref" in -*) fail 2 'A configuration ref cannot start with -' ;; esac
	case "$repo_url" in -*) fail 2 'A repository URL cannot start with -' ;; esac
	config_dir=${config_dir%/}
	case "$config_dir" in '' | / | . | .. | */. | */..) fail 2 'Choose a configuration directory, not a filesystem root or dot path' ;; esac
	case "$config_dir" in /*) ;; *) config_dir="$PWD/$config_dir" ;; esac
	profile_csv=$(
		IFS=,
		printf '%s' "${profiles[*]}"
	)

}

has_profile() {
	local profile
	for profile in "${profiles[@]}"; do
		[ "$profile" != full ] && [ "$profile" != "$1" ] || return 0
	done
	return 1
}
# Use OS detection only for package names and the official Neovim asset.
detect_dependencies() {
	system=$(uname -s)
	architecture=$(uname -m)
	case "$architecture" in x86_64) architecture=x86_64 ;; aarch64 | arm64) architecture=arm64 ;; esac
	case "$system" in Linux) asset="nvim-linux-$architecture" ;; Darwin) asset="nvim-macos-$architecture" ;; *) asset="unsupported-$system-$architecture" ;; esac
	tree_asset=${asset/nvim-/tree-sitter-}
	tree_asset=${tree_asset/x86_64/x64}
	if [ "$system" = Darwin ]; then
		pkg_mgr=brew
	elif command -v pacman >/dev/null 2>&1; then
		pkg_mgr=pacman
	elif command -v apt-get >/dev/null 2>&1; then
		pkg_mgr=apt
	elif command -v dnf >/dev/null 2>&1; then
		pkg_mgr=dnf
	elif command -v zypper >/dev/null 2>&1; then
		pkg_mgr=zypper
	fi
	if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then sudo_cmd=(sudo); fi

	required=()
	profile_packages=()
	extras=()
	case "$pkg_mgr" in
	pacman)
		required=(git fzf ripgrep fd gcc make unzip curl tar gzip)
		has_profile python && profile_packages+=(nodejs npm python python-pip)
		has_profile web && profile_packages+=(nodejs npm)
		has_profile java && profile_packages+=(jdk21-openjdk)
		has_profile native && profile_packages+=(go rust python python-pip cmake ninja)
		has_profile docs && profile_packages+=(nodejs npm perl typst texlive-binextra texlive-latexrecommended poppler imagemagick)
		extras=(lazygit sqlite poppler imagemagick)
		;;
	apt)
		required=(git fzf ripgrep fd-find build-essential unzip curl tar gzip)
		has_profile python && profile_packages+=(nodejs npm python3 python3-venv python3-pip)
		has_profile web && profile_packages+=(nodejs npm)
		has_profile java && profile_packages+=(openjdk-21-jdk)
		has_profile native && profile_packages+=(golang-go cargo python3 python3-venv python3-pip cmake ninja-build)
		has_profile docs && profile_packages+=(nodejs npm perl typst latexmk texlive-latex-base poppler-utils imagemagick)
		extras=(lazygit sqlite3 poppler-utils imagemagick)
		;;
	dnf)
		required=(git fzf ripgrep fd-find gcc make unzip curl tar gzip)
		has_profile python && profile_packages+=(nodejs npm python3 python3-pip)
		has_profile web && profile_packages+=(nodejs npm)
		has_profile java && profile_packages+=(java-21-openjdk-devel)
		has_profile native && profile_packages+=(golang cargo python3 python3-pip cmake ninja-build)
		has_profile docs && profile_packages+=(nodejs npm perl typst latexmk texlive-latex poppler-utils ImageMagick)
		extras=(lazygit sqlite poppler-utils ImageMagick)
		;;
	zypper)
		required=(git fzf ripgrep fd gcc make unzip curl tar gzip)
		has_profile python && profile_packages+=(nodejs npm python3 python3-pip)
		has_profile web && profile_packages+=(nodejs npm)
		has_profile java && profile_packages+=(java-21-openjdk-devel)
		has_profile native && profile_packages+=(go cargo python3 python3-pip cmake ninja)
		has_profile docs && profile_packages+=(nodejs npm perl typst texlive-latexmk texlive-latex poppler-tools ImageMagick)
		extras=(lazygit sqlite3 poppler-tools ImageMagick)
		;;
	brew)
		required=(git fzf ripgrep fd)
		has_profile python && profile_packages+=(node python)
		has_profile web && profile_packages+=(node)
		has_profile java && profile_packages+=(openjdk@21)
		has_profile native && profile_packages+=(go rust python cmake ninja)
		has_profile docs && profile_packages+=(node perl typst basictex poppler imagemagick)
		extras=(lazygit sqlite poppler imagemagick)
		;;
	esac
	# Full also includes Python-hosted YAML tools, Go linters, and Perl's latexindent.
	# The language profiles above already cover these prerequisites.

}

print_command() {
	printf '    '
	printf '%q ' "$@"
	printf '\n'
}
pkg_install() {
	case "$pkg_mgr" in
	pacman) ${sudo_cmd[@]+"${sudo_cmd[@]}"} pacman -S --needed --noconfirm "$@" ;;
	apt) ${sudo_cmd[@]+"${sudo_cmd[@]}"} apt-get install -y "$@" ;;
	dnf) ${sudo_cmd[@]+"${sudo_cmd[@]}"} dnf install -y "$@" ;;
	zypper) ${sudo_cmd[@]+"${sudo_cmd[@]}"} zypper install -y "$@" ;;
	brew) brew install "$@" ;;
	*) return 1 ;;
	esac
}
plan() {
	info "Plan only: no files, directories, links, installs or downloads will be created"
	info "Repository: $repo_url; requested ref: $config_ref (resolved to a commit before cutover)"
	info "Destination: $config_dir; profiles: $profile_csv; package manager: ${pkg_mgr:-unavailable}"
	if [ "$skip_deps" -eq 0 ]; then
		info "System packages (Neovim is installed separately at its exact release):"
		print_command "${required[@]}" ${profile_packages[@]+"${profile_packages[@]}"}
		[ "$with_extras" -eq 0 ] || print_command "${extras[@]}"
	else info 'System package installation skipped; executable/version checks still run'; fi
	info "Ensure exact Neovim $nvim_version; reuse an exact match or download:"
	print_command "https://github.com/neovim/neovim/releases/download/$nvim_version/$asset.tar.gz"
	info "Neovim release directory: $local_opt/$asset-$nvim_version; executable link: $local_bin/nvim"
	if [ "$skip_sync" -eq 0 ]; then
		info "Ensure tree-sitter CLI $tree_sitter_version; reuse an exact match or download its official binary:"
		print_command "https://github.com/tree-sitter/tree-sitter/releases/download/v$tree_sitter_version/$tree_asset.gz"
		info 'Compile and verify all locked syntax parsers and prepare the pinned Blink completion asset'
	fi
	info 'Clone into an exclusive sibling release directory, fetch/verify ref, detached checkout, validate configuration'
	if [ "$skip_sync" -eq 0 ]; then
		info 'Restore plugins in staging from lazy-lock.json; verify plugin commits before moving the original configuration'
		info "After cutover, restore only pinned Mason profiles: $profile_csv (all include minimal)"
	else info 'Plugin and Mason restoration explicitly deferred (--no-sync)'; fi
	info 'Move the old configuration to a unique sibling backup/config; exclusively link the destination to the release'
	info 'On cutover failure, restore a link to backup/config only if the destination is absent; never overwrite a concurrent directory'
	[ "$with_dict" -eq 0 ] || info "Optional dictionary: $dict_url -> $dict_db"
	info 'Keep backup/release directories for recovery; shared plugin and Mason data are not rolled back'
}

# Neither the active configuration nor a concurrently-created destination is
# removed by cleanup. fs_symlink fails atomically with EEXIST on every platform.
link_exclusive() {
	NVIM_DEPLOY_LINK_SOURCE=$1 NVIM_DEPLOY_LINK_TARGET=$2 nvim --headless -u NONE -i NONE -n \
		--cmd 'lua local ok,err=vim.uv.fs_symlink(vim.env.NVIM_DEPLOY_LINK_SOURCE,vim.env.NVIM_DEPLOY_LINK_TARGET,{dir=true}); if not ok then io.stderr:write(tostring(err).."\n"); vim.cmd("cquit 1") end' +qa
}
cleanup() {
	local code=$?
	if [ -n "$stage_dir" ] && [ "$(readlink "$config_dir" 2>/dev/null || true)" = "$stage_dir/config" ]; then
		committed=1
	fi
	if [ "$backup_taken" -eq 1 ] && [ "$committed" -eq 0 ]; then
		if [ ! -e "$config_dir" ] && [ ! -L "$config_dir" ]; then
			link_exclusive "$backup_dir/config" "$config_dir" || warn "Automatic recovery could not link $backup_dir/config"
		fi
		warn "Original configuration is preserved at $backup_dir/config; destination was not overwritten during recovery"
	fi
	if [ -n "$stage_dir" ] && [ "$committed" -eq 0 ]; then rm -rf -- "$stage_dir"; fi
	return "$code"
}

install_dependencies() {
	if [ "$skip_deps" -eq 0 ]; then
		[ -n "$pkg_mgr" ] || fail 10 'Unsupported package manager; install prerequisites and use --no-deps'
		command -v "${pkg_mgr/apt/apt-get}" >/dev/null 2>&1 || fail 10 "Package manager $pkg_mgr is unavailable"
		info "Installing dependencies for $profile_csv with $pkg_mgr"
		if [ "$pkg_mgr" = apt ]; then ${sudo_cmd[@]+"${sudo_cmd[@]}"} apt-get update || fail 10 'Package index update failed; configuration unchanged'; fi
		pkg_install "${required[@]}" ${profile_packages[@]+"${profile_packages[@]}"} || fail 10 'Required dependencies failed; configuration unchanged'
		if [ "$with_extras" -eq 1 ]; then
			for package in "${extras[@]}"; do pkg_install "$package" || deps_partial=1; done
		fi
	fi
	if [ "$pkg_mgr" = brew ] && has_profile java; then
		jdk_prefix=$(brew --prefix openjdk@21 2>/dev/null || true)
		if [ -x "$jdk_prefix/libexec/openjdk.jdk/Contents/Home/bin/java" ]; then
			export JAVA_HOME="$jdk_prefix/libexec/openjdk.jdk/Contents/Home"
			export PATH="$JAVA_HOME/bin:$PATH"
		fi
	fi
	for executable in git curl tar unzip gzip rg; do command -v "$executable" >/dev/null 2>&1 || fail 10 "Missing dependency: $executable"; done
	command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 || fail 10 'Missing C compiler'
	if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
		mkdir -p "$local_bin"
		[ -e "$local_bin/fd" ] || ln -s "$(command -v fdfind)" "$local_bin/fd"
		export PATH="$local_bin:$PATH"
	fi
	command -v fd >/dev/null 2>&1 || fail 10 'Missing dependency: fd (or fdfind)'
	fzf_version=$(FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --version 2>/dev/null) || fail 10 'Missing fzf >= 0.36.0'
	[[ "$fzf_version" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?([[:space:]]|\+|-|$) ]] || fail 10 'Could not read the fzf version'
	[ "$((10#${BASH_REMATCH[1]}))" -gt 0 ] || [ "$((10#${BASH_REMATCH[2]}))" -ge 36 ] || fail 10 'fzf >= 0.36.0 is required'

}

nvim_exact() {
	local output
	output=$(nvim --version 2>/dev/null) || return 1
	[ "${output%%$'\n'*}" = "NVIM $nvim_version" ]
}
install_nvim() {
	case "$asset" in nvim-linux-x86_64 | nvim-linux-arm64 | nvim-macos-x86_64 | nvim-macos-arm64) ;;
	*) fail 10 "Unsupported official Neovim asset: $asset" ;;
	esac
	local release="$local_opt/$asset-$nvim_version" download
	if [ ! -x "$release/bin/nvim" ]; then
		mkdir -p "$local_opt" "$local_bin"
		download=$(mktemp -d "$local_opt/.nvim-download.XXXXXX")
		if ! curl -fL --retry 2 "https://github.com/neovim/neovim/releases/download/$nvim_version/$asset.tar.gz" -o "$download/nvim.tar.gz" ||
			! tar -xzf "$download/nvim.tar.gz" -C "$download" || [ ! -x "$download/$asset/bin/nvim" ]; then
			rm -rf -- "$download"
			fail 10 'Pinned Neovim download/extraction failed; configuration unchanged'
		fi
		if [ -e "$release" ]; then
			rm -rf -- "$download"
			fail 10 "Neovim release destination exists but is incomplete: $release"
		fi
		mv "$download/$asset" "$release" || fail 10 'Could not place the Neovim release'
		rm -rf -- "$download"
	fi
	mkdir -p "$local_bin"
	if [ -e "$local_bin/nvim" ] && [ ! -L "$local_bin/nvim" ]; then
		fail 10 "Refusing to replace a regular executable at $local_bin/nvim; move it manually or put exact $nvim_version on PATH"
	fi
	local release_version
	release_version=$("$release/bin/nvim" --version) || fail 10 'Downloaded Neovim could not execute'
	[ "${release_version%%$'\n'*}" = "NVIM $nvim_version" ] || fail 10 "Release directory does not contain $nvim_version: $release"
	ln -sfn "$release/bin/nvim" "$local_bin/nvim"
	export PATH="$local_bin:$PATH"
	hash -r
	nvim_exact || fail 10 "Downloaded Neovim does not match $nvim_version"
}

tree_sitter_exact() {
	local output
	output=$(tree-sitter --version 2>/dev/null) || return 1
	case "$output" in "tree-sitter $tree_sitter_version" | "tree-sitter $tree_sitter_version "*) return 0 ;; *) return 1 ;; esac
}
install_tree_sitter() {
	case "$tree_asset" in tree-sitter-linux-x64 | tree-sitter-linux-arm64 | tree-sitter-macos-x64 | tree-sitter-macos-arm64) ;;
	*) fail 10 "Unsupported official tree-sitter asset: $tree_asset" ;; esac
	local release="$local_opt/tree-sitter-v$tree_sitter_version" download
	if [ ! -x "$release/tree-sitter" ]; then
		mkdir -p "$local_opt" "$local_bin"
		download=$(mktemp -d "$local_opt/.tree-sitter-download.XXXXXX")
		if ! curl -fL --retry 2 "https://github.com/tree-sitter/tree-sitter/releases/download/v$tree_sitter_version/$tree_asset.gz" -o "$download/cli.gz" ||
			! gzip -dc "$download/cli.gz" >"$download/tree-sitter"; then
			rm -rf -- "$download"
			fail 10 'Pinned tree-sitter CLI download/extraction failed'
		fi
		chmod +x "$download/tree-sitter"
		if [ -e "$release" ]; then
			rm -rf -- "$download"
			fail 10 "Incomplete tree-sitter destination: $release"
		fi
		mv "$download" "$release" || fail 10 'Could not place the tree-sitter CLI release'
	fi
	mkdir -p "$local_bin"
	if [ -e "$local_bin/tree-sitter" ] && [ ! -L "$local_bin/tree-sitter" ]; then
		fail 10 "Refusing to replace regular executable $local_bin/tree-sitter; put tree-sitter $tree_sitter_version on PATH"
	fi
	local output
	output=$("$release/tree-sitter" --version) || fail 10 'Downloaded tree-sitter CLI could not execute'
	case "$output" in "tree-sitter $tree_sitter_version" | "tree-sitter $tree_sitter_version "*) ;; *) fail 10 'tree-sitter release version mismatch' ;; esac
	ln -sfn "$release/tree-sitter" "$local_bin/tree-sitter"
	export PATH="$local_bin:$PATH"
	hash -r
	tree_sitter_exact || fail 10 'Pinned tree-sitter CLI is not available on PATH'
}

# Capture destination identity before network work. A separate installer or user
# creating/replacing it while staging runs must not be displaced at cutover.
identity() {
	if [ ! -e "$config_dir" ] && [ ! -L "$config_dir" ]; then
		printf absent
	elif [ "$system" = Darwin ]; then
		stat -f '%d:%i' "$config_dir"
	else stat -c '%d:%i' "$config_dir"; fi
}
deploy_configuration() {
	original_identity=$(identity)
	parent=$(dirname "$config_dir")
	mkdir -p "$parent" || fail 20 'Could not create the configuration parent directory'
	parent=$(cd "$parent" && pwd -P)
	config_dir="$parent/$(basename "$config_dir")"
	stage_dir=$(mktemp -d "$parent/.nvim-release.XXXXXX") || fail 20 'Could not create a staging directory'
	info "Cloning $repo_url at requested ref $config_ref into staging"
	git clone --no-checkout --filter=blob:none -- "$repo_url" "$stage_dir/config" || fail 20 'Configuration clone failed; original configuration unchanged'
	git -C "$stage_dir/config" fetch --depth 1 -- origin "$config_ref" || fail 20 "Could not fetch configuration ref $config_ref; original configuration unchanged"
	resolved_ref=$(git -C "$stage_dir/config" rev-parse --verify 'FETCH_HEAD^{commit}') || fail 20 'Requested ref did not resolve to a commit'
	git -C "$stage_dir/config" checkout --detach "$resolved_ref" || fail 20 'Configuration checkout failed; original configuration unchanged'
	for file in init.lua lazy-lock.json; do [ -f "$stage_dir/config/$file" ] || fail 20 "Revision $resolved_ref lacks $file"; done
	if [ -f "$config_dir/preferences.json" ]; then
		cp "$config_dir/preferences.json" "$stage_dir/config/preferences.json" || fail 20 'Could not preserve preferences.json in staging'
	fi
	info "Resolved configuration commit: $resolved_ref"
	# Lazy resets runtimepath from stdpath(config); an isolated config namespace
	# makes both the init and after directories point at this exact checkout.
	mkdir -p "$stage_dir/xdg-config"
	ln -s "$stage_dir/config" "$stage_dir/xdg-config/nvim"
	if [ "$skip_sync" -eq 0 ]; then
		for file in scripts/deploy-plugins.lua scripts/deploy-tools.lua scripts/verify-lock.lua scripts/prepare-checks.lua scripts/check-support.lua; do
			[ -f "$stage_dir/config/$file" ] || fail 20 "Revision $resolved_ref lacks $file; choose a deployment-compatible revision or --no-sync"
		done
		info 'Preparing, restoring and verifying the staged plugin lock'
		XDG_CONFIG_HOME="$stage_dir/xdg-config" NVIM_APPNAME=nvim NVIM_TEST_ROOT="$stage_dir/config" NVIM_PREPARE_PARSERS=1 NVIM_PREPARE_TOOLS=0 NVIM_PREPARE_ASSETS=1 NVIM_PREPARE_NVIM_VERSION="$nvim_version" \
			nvim --headless -u NONE -i NONE -l "$stage_dir/config/scripts/prepare-checks.lua" || fail 21 'Plugin preparation failed; original configuration unchanged'
		XDG_CONFIG_HOME="$stage_dir/xdg-config" NVIM_APPNAME=nvim NVIM_DEPLOY_ROOT="$stage_dir/config" NVIM_TEST_ROOT="$stage_dir/config" nvim --headless -n -i NONE \
			--cmd 'lua vim.opt.runtimepath:prepend(vim.env.NVIM_DEPLOY_ROOT)' -u "$stage_dir/config/init.lua" \
			-l "$stage_dir/config/scripts/deploy-plugins.lua" || fail 21 'Plugin restore failed; original configuration unchanged'
		XDG_CONFIG_HOME="$stage_dir/xdg-config" NVIM_APPNAME=nvim NVIM_TEST_ROOT="$stage_dir/config" NVIM_VERIFY_TOOLS=0 NVIM_VERIFY_PARSERS=1 NVIM_VERIFY_ASSETS=1 \
			nvim --headless -u NONE -i NONE -l "$stage_dir/config/scripts/verify-lock.lua" || fail 21 'Plugin lock verification failed; original configuration unchanged'
	fi
	[ "$(identity)" = "$original_identity" ] || fail 20 'Destination changed during staging; refusing to replace it'
	if [ "$original_identity" != absent ]; then
		backup_dir=$(mktemp -d "$parent/nvim.backup.$(date +%Y%m%d%H%M%S).XXXXXX") || fail 20 'Could not reserve a backup directory'
		mv "$config_dir" "$backup_dir/config" || fail 20 'Could not back up the current configuration'
		backup_taken=1
	fi
	link_exclusive "$stage_dir/config" "$config_dir" || fail 20 'Cutover failed; preserving the original backup and any concurrently-created destination'
	committed=1
	info "Configuration active: $config_dir -> $stage_dir/config"
	[ "$backup_taken" -eq 0 ] || info "Previous configuration: $backup_dir/config"
	printf 'repository=%s\nrequested_ref=%s\ncommit=%s\nneovim=%s\nprofiles=%s\n' \
		"$repo_url" "$config_ref" "$resolved_ref" "$nvim_version" "$profile_csv" >"$stage_dir/deployment.txt"
	if [ "$skip_sync" -eq 0 ]; then
		XDG_CONFIG_HOME="$stage_dir/xdg-config" NVIM_APPNAME=nvim NVIM_DEPLOY_ROOT="$stage_dir/config" NVIM_DEPLOY_PROFILES="$profile_csv" nvim --headless -n -i NONE \
			--cmd 'lua vim.opt.runtimepath:prepend(vim.env.NVIM_DEPLOY_ROOT)' -u "$stage_dir/config/init.lua" \
			-l "$stage_dir/config/scripts/deploy-tools.lua" || tools_partial=1
	else info 'Plugin and Mason installation deferred by --no-sync'; fi
	if [ "$with_dict" -eq 1 ] && [ ! -s "$dict_db" ]; then
		download=$(mktemp -d)
		mkdir -p "$(dirname "$dict_db")"
		if ! curl -fL "$dict_url" -o "$download/dict.zip" || ! unzip -o "$download/dict.zip" -d "$(dirname "$dict_db")" || [ ! -s "$dict_db" ]; then dict_partial=1; fi
		rm -rf -- "$download"
	fi
	[ "$tools_partial" -eq 0 ] || fail 30 "Configuration is active, but selected Mason tools are incomplete ($profile_csv). Rerun with the same --ref and --profile; backup remains available."
	[ "$deps_partial" -eq 0 ] || fail 10 'Configuration is active, but requested optional system packages were not all installed'
	[ "$dict_partial" -eq 0 ] || fail 40 'Configuration is active, but the optional dictionary installation failed'
	info "Deployment complete at commit $resolved_ref ($profile_csv). Keep the release and backup directories until recovery is no longer needed."

}

main() {
	parse_arguments "$@"
	detect_dependencies
	if [ "$dry_run" -eq 1 ]; then
		plan
		return 0
	fi
	trap cleanup EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	install_dependencies
	nvim_exact || install_nvim
	info "Neovim: $nvim_version"
	if [ "$skip_sync" -eq 0 ]; then tree_sitter_exact || install_tree_sitter; fi
	deploy_configuration
}
main "$@"
