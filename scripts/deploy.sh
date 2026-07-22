#!/usr/bin/env bash
# Deploy this Neovim configuration across machines.
#
# On a new machine (without cloning the repository first):
#   bash <(curl -fsSL https://raw.githubusercontent.com/kkoishichan/nvim/main/scripts/deploy.sh)
#
# Or from an existing clone:
#   ./scripts/deploy.sh
#
# Workflow: install system dependencies -> ensure nvim >= 0.12 -> back up and
# clone the configuration -> restore plugins headlessly from lazy-lock.json.
# Supports Arch, Debian/Ubuntu, Fedora, openSUSE, and macOS (Homebrew).

set -euo pipefail

REPO_HTTPS="https://github.com/kkoishichan/nvim.git"
REPO_SSH="git@github.com:kkoishichan/nvim.git"
NVIM_MIN_MINOR=12 # Require nvim >= 0.12

# Offline dictionary used by lua/user/core/dict.lua. The configuration expects
# it under ~/.local/share.
DICT_URL="https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip"
DICT_DB="$HOME/.local/share/trans/ultimate.db"
DOTNET_INSTALL_URL="https://dot.net/v1/dotnet-install.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
DOTNET_DIR="$LOCAL_OPT/dotnet"

repo_url="$REPO_HTTPS"
skip_deps=0
with_extras=0
skip_sync=0
with_toolchain=0
with_dict=0

# Logical capabilities required to install or run the complete pinned Mason
# catalog. Package names remain distribution-specific in install_deps().
toolchain_prerequisites=(node npm python pip go cargo java dotnet perl)

usage() {
	cat <<'EOF'
Usage: ./scripts/deploy.sh [options]

  --ssh           Clone over SSH (HTTPS is the default and needs no key setup)
  --repo <url>    Use a custom repository URL
  --no-deps       Skip system dependency installation
  --with-extras   Install optional dependencies (lazygit, Node.js, ImageMagick, poppler, etc.)
  --mason         Install the pinned Mason toolchain and its prerequisites
  --dict          Download ECDICT-ultimate (~300 MB archive, ~1.2 GB extracted)
  --no-sync       Skip headless plugin installation and defer it to first launch
  -h, --help      Show this help message
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--ssh) repo_url="$REPO_SSH" ;;
	--repo)
		repo_url="${2:?--repo requires a URL}"
		shift
		;;
	--no-deps) skip_deps=1 ;;
	--with-extras) with_extras=1 ;;
	--mason) with_toolchain=1 ;;
	--dict) with_dict=1 ;;
	--no-sync) skip_sync=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
	shift
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
	exit 1
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	if command -v sudo >/dev/null; then
		SUDO="sudo"
	else
		warn "sudo is unavailable; system package installation may fail"
	fi
fi

# -------------------------------------------------------------- Package manager

PKG_MGR=""
detect_pkg_mgr() {
	if [ "$(uname -s)" = Darwin ]; then
		command -v brew >/dev/null || die "Install Homebrew on macOS first: https://brew.sh"
		PKG_MGR=brew
	elif command -v pacman >/dev/null; then
		PKG_MGR=pacman
	elif command -v apt-get >/dev/null; then
		PKG_MGR=apt
	elif command -v dnf >/dev/null; then
		PKG_MGR=dnf
	elif command -v zypper >/dev/null; then
		PKG_MGR=zypper
	else
		PKG_MGR=""
	fi
}

pkg_install() {
	case "$PKG_MGR" in
	pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
	apt) $SUDO apt-get install -y "$@" ;;
	dnf) $SUDO dnf install -y "$@" ;;
	zypper) $SUDO zypper install -y "$@" ;;
	brew) brew install "$@" ;;
	esac
}

ensure_local_bin_path() {
	mkdir -p "$LOCAL_BIN"
	case ":$PATH:" in
	*":$LOCAL_BIN:"*) ;;
	*) warn "$LOCAL_BIN is not in PATH; add it to your shell configuration" ;;
	esac
	case "$PATH:" in
	"$LOCAL_BIN:"*) ;;
	*) export PATH="$LOCAL_BIN:$PATH" ;;
	esac
	hash -r
}

python_runtime() {
	local name python
	for name in python3 python; do
		if python=$(command -v "$name" 2>/dev/null); then
			if "$python" -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
				printf '%s\n' "$python"
				return 0
			fi
		fi
	done
	return 1
}

python_runtime_available() {
	python_runtime >/dev/null
}

pip_runtime_available() {
	local python
	python=$(python_runtime) || return 1
	"$python" -m pip --version >/dev/null 2>&1
}

java_runtime_available() {
	command -v java >/dev/null || return 1
	command -v javac >/dev/null || return 1
	local output version major
	output=$(java -version 2>&1) || return 1
	version=$(printf '%s\n' "$output" | sed -n '1s/.*version "\([^"]*\)".*/\1/p')
	[ -n "$version" ] ||
		version=$(printf '%s\n' "$output" | sed -n '1s/^openjdk[[:space:]][[:space:]]*\([^[:space:]]*\).*/\1/p')
	case "$version" in
	1.*)
		major=${version#1.}
		major=${major%%.*}
		;;
	*) major=${version%%[._+-]*} ;;
	esac
	case "$major" in
	"" | *[!0-9]*) return 1 ;;
	esac
	[ "$major" -ge 21 ]
}

dotnet_sdk_available() {
	command -v dotnet >/dev/null && [ -n "$(dotnet --list-sdks 2>/dev/null)" ]
}

prerequisite_available() {
	case "$1" in
	python) python_runtime_available ;;
	pip) pip_runtime_available ;;
	java) java_runtime_available ;;
	dotnet) dotnet_sdk_available ;;
	*) command -v "$1" >/dev/null ;;
	esac
}

prerequisite_label() {
	case "$1" in
	python) printf 'Python 3.9+' ;;
	java) printf 'JDK 21+' ;;
	dotnet) printf '.NET SDK' ;;
	*) printf '%s' "$1" ;;
	esac
}

validate_toolchain_prerequisites() {
	local prerequisite label joined
	local missing=()
	for prerequisite in "${toolchain_prerequisites[@]}"; do
		if ! prerequisite_available "$prerequisite"; then
			label=$(prerequisite_label "$prerequisite")
			missing+=("$label")
		fi
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		printf -v joined '%s, ' "${missing[@]}"
		warn "Missing Mason toolchain prerequisites: ${joined%, }"
	fi
}

activate_brew_jdk() {
	[ "$PKG_MGR" = brew ] || return 0
	local prefix java_home
	if ! prefix=$(brew --prefix openjdk@21 2>/dev/null); then
		return 0
	fi
	java_home="$prefix/libexec/openjdk.jdk/Contents/Home"
	[ -x "$java_home/bin/java" ] || return 0
	export JAVA_HOME="$java_home"
	case ":$PATH:" in
	*":$java_home/bin:"*) ;;
	*)
		export PATH="$java_home/bin:$PATH"
		warn "$java_home/bin was added for this deployment only; configure JAVA_HOME in your shell to keep using JDK 21+"
		;;
	esac
	hash -r
}

# Distribution repositories do not expose one portable .NET SDK package name.
# Use Microsoft's non-root installer as the single user-local fallback.
install_dotnet_sdk() {
	if dotnet_sdk_available; then
		info ".NET SDK: $(dotnet --version)"
		return
	fi
	if ! command -v curl >/dev/null; then
		warn "curl is unavailable; cannot install the .NET SDK"
		return 1
	fi

	local installer
	installer=$(mktemp)
	info "Installing the latest .NET LTS SDK to $DOTNET_DIR"
	if ! curl -fL --progress-bar "$DOTNET_INSTALL_URL" -o "$installer"; then
		rm -f "$installer"
		warn "Could not download the official .NET installer"
		return 1
	fi
	mkdir -p "$DOTNET_DIR" "$LOCAL_BIN"
	if ! bash "$installer" --channel LTS --install-dir "$DOTNET_DIR" --no-path; then
		rm -f "$installer"
		warn ".NET SDK installation failed"
		return 1
	fi
	rm -f "$installer"
	ln -sf "$DOTNET_DIR/dotnet" "$LOCAL_BIN/dotnet"
	export DOTNET_ROOT="$DOTNET_DIR"
	ensure_local_bin_path
	if ! dotnet_sdk_available; then
		warn ".NET was installed, but no SDK is available on PATH"
		return 1
	fi
	info ".NET SDK: $(dotnet --version)"
}

install_toolchain_prerequisites() {
	local package
	for package in "$@"; do
		pkg_install "$package" || warn "Toolchain prerequisite $package failed to install; some Mason tools may be unavailable"
	done
	activate_brew_jdk
	install_dotnet_sdk || warn "Install a compatible .NET SDK manually"
	validate_toolchain_prerequisites
}

install_deps() {
	detect_pkg_mgr
	if [ -z "$PKG_MGR" ]; then
		warn "Could not detect a package manager. Install these manually: git neovim>=0.12 ripgrep fd a C compiler unzip curl tar"
		if [ "$with_toolchain" -eq 1 ]; then
			install_dotnet_sdk || warn "Install a compatible .NET SDK manually"
			validate_toolchain_prerequisites
		fi
		return
	fi
	info "Installing dependencies with $PKG_MGR"

	local required extras toolchain_deps
	case "$PKG_MGR" in
	pacman)
		required=(git neovim ripgrep fd gcc unzip curl tar)
		extras=(lazygit nodejs npm poppler sqlite imagemagick typst texlive-binextra)
		toolchain_deps=(nodejs npm python python-pip go rust jdk21-openjdk perl)
		;;
	apt)
		$SUDO apt-get update
		required=(git neovim ripgrep fd-find build-essential unzip curl tar)
		extras=(lazygit nodejs npm poppler-utils sqlite3 imagemagick typst latexmk)
		toolchain_deps=(nodejs npm python3 python3-venv python3-pip golang-go cargo openjdk-21-jdk perl)
		;;
	dnf)
		required=(git neovim ripgrep fd-find gcc unzip curl tar)
		extras=(lazygit nodejs poppler-utils sqlite ImageMagick typst latexmk)
		toolchain_deps=(nodejs npm python3 python3-pip golang rust cargo java-21-openjdk-devel perl)
		;;
	zypper)
		required=(git neovim ripgrep fd gcc unzip curl tar)
		extras=(lazygit nodejs poppler-tools sqlite3 ImageMagick typst texlive-latexmk)
		toolchain_deps=(nodejs npm python3 python3-pip go rust cargo java-21-openjdk-devel perl)
		;;
	brew)
		required=(git neovim ripgrep fd)
		extras=(lazygit node poppler sqlite imagemagick typst latexmk)
		toolchain_deps=(node python go rust openjdk@21)
		;;
	esac

	pkg_install "${required[@]}" || warn "Some required dependencies failed to install; check the output above"

	if [ "$with_extras" -eq 1 ]; then
		local pkg
		for pkg in "${extras[@]}"; do
			pkg_install "$pkg" || warn "Optional dependency $pkg failed to install; skipping it"
		done
	fi

	if [ "$with_toolchain" -eq 1 ]; then
		install_toolchain_prerequisites "${toolchain_deps[@]}"
	fi

	# Debian and Ubuntu package fd as fdfind, so provide an fd symlink.
	if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
		mkdir -p "$LOCAL_BIN"
		ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
		ensure_local_bin_path
		info "Linked fdfind -> $LOCAL_BIN/fd"
	fi
}

# ------------------------------------------------------ Neovim version fallback

nvim_ok() {
	command -v nvim >/dev/null || return 1
	local ver major minor
	ver=$(nvim --version | head -1 | sed 's/^NVIM v//')
	major=${ver%%.*}
	minor=${ver#*.}
	minor=${minor%%.*}
	[ "$major" -gt 0 ] || [ "$minor" -ge "$NVIM_MIN_MINOR" ]
}

install_nvim_tarball() {
	[ "$(uname -s)" = Linux ] || die "Install Neovim >= 0.$NVIM_MIN_MINOR manually"
	local arch asset
	case "$(uname -m)" in
	x86_64) arch=x86_64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) die "Unsupported architecture $(uname -m); install Neovim >= 0.$NVIM_MIN_MINOR manually" ;;
	esac
	asset="nvim-linux-$arch"

	info "Installing the latest stable Neovim release to $LOCAL_OPT/$asset"
	mkdir -p "$LOCAL_OPT" "$LOCAL_BIN"
	curl -fL --progress-bar \
		"https://github.com/neovim/neovim/releases/latest/download/$asset.tar.gz" \
		-o "$LOCAL_OPT/$asset.tar.gz"
	rm -rf "${LOCAL_OPT:?}/$asset"
	tar -C "$LOCAL_OPT" -xzf "$LOCAL_OPT/$asset.tar.gz"
	rm -f "$LOCAL_OPT/$asset.tar.gz"
	ln -sf "$LOCAL_OPT/$asset/bin/nvim" "$LOCAL_BIN/nvim"

	ensure_local_bin_path
	nvim_ok || die "Neovim is still unavailable after installation; check PATH"
}

# ------------------------------------------------------- Configuration deployment

deploy_config() {
	if [ -d "$CONFIG_DIR/.git" ]; then
		local origin
		origin=$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null || true)
		case "$origin" in
		*kkoishichan/nvim* | "$repo_url")
			info "Existing configuration repository detected; running git pull"
			git -C "$CONFIG_DIR" pull --ff-only || warn "git pull failed, possibly because of local changes; leaving it unchanged"
			return
			;;
		esac
	fi

	if [ -e "$CONFIG_DIR" ]; then
		local backup
		backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
		info "Backing up the existing configuration to $backup"
		mv "$CONFIG_DIR" "$backup"
	fi

	info "Cloning $repo_url -> $CONFIG_DIR"
	git clone --depth 1 "$repo_url" "$CONFIG_DIR"
}

# ------------------------------------------------------------ Offline dictionary

install_dict() {
	if [ -s "$DICT_DB" ]; then
		info "Dictionary already exists at $DICT_DB; skipping download"
		return
	fi
	if ! command -v unzip >/dev/null; then
		warn "unzip is unavailable; skipping dictionary installation. Download it manually from $DICT_URL"
		return
	fi

	info "Downloading ECDICT-ultimate (~300 MB archive, ~1.2 GB extracted)"
	local tmp
	tmp=$(mktemp -d)
	mkdir -p "$(dirname "$DICT_DB")"
	if curl -fL --progress-bar "$DICT_URL" -o "$tmp/ecdict.zip" &&
		unzip -o "$tmp/ecdict.zip" -d "$(dirname "$DICT_DB")" >/dev/null &&
		[ -s "$DICT_DB" ]; then
		info "Dictionary installed at $DICT_DB"
	else
		warn "Dictionary download or extraction failed; install it manually from $DICT_URL"
	fi
	rm -rf "$tmp"

	command -v sqlite3 >/dev/null ||
		warn "Dictionary lookup also requires sqlite3; use --with-extras or install it manually"
}

# ---------------------------------------------------------- Headless initialization

sync_plugins() {
	info "Installing plugins headlessly from lazy-lock.json; the first run may take a few minutes"
	nvim --headless "+Lazy! restore" +qa || warn "Plugin installation failed; run :Lazy restore inside Neovim later"

	if [ "$with_toolchain" -eq 1 ]; then
		[ "$skip_deps" -eq 0 ] || validate_toolchain_prerequisites
		info "Installing the pinned Mason language and development toolchain"
		nvim --headless "+MasonToolsInstallSync" +qa ||
			warn "Mason tool installation failed; run :MasonToolsInstall inside Neovim later"
	fi
}

# ------------------------------------------------------------------- Main flow

[ "$skip_deps" -eq 1 ] || install_deps

if ! nvim_ok; then
	warn "Neovim >= 0.$NVIM_MIN_MINOR was not found; trying the official release"
	install_nvim_tarball
fi
info "Neovim: $(nvim --version | head -1)"

deploy_config

[ "$with_dict" -eq 0 ] || install_dict

[ "$skip_sync" -eq 1 ] || sync_plugins

info "Deployment complete. Run nvim to get started"
cat <<'EOF'

Notes:
  - Use a Nerd Font in your terminal so icons render correctly.
  - Mason tools are installed only when requested with --mason or :MasonToolsInstall.
  - --mason bootstraps prerequisites used by the pinned tools. Project SDKs,
    build systems, and project-specific versions remain project dependencies.
  - Inline images and PDF previews require a kitty-graphics terminal, ImageMagick, and poppler;
    --with-extras installs ImageMagick and poppler.
  - The offline dictionary expects ECDICT-ultimate at ~/.local/share/trans/ultimate.db.
    Use --dict to download it from github.com/skywind3000/ECDICT-ultimate.
EOF
