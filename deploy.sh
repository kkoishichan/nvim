#!/usr/bin/env bash
# Deploy this Neovim configuration across machines.
#
# On a new machine (without cloning the repository first):
#   bash <(curl -fsSL https://raw.githubusercontent.com/koishi510/nvim/main/deploy.sh)
#
# Or from an existing clone:
#   ./deploy.sh
#
# Workflow: install system dependencies -> ensure nvim >= 0.11 -> back up and
# clone the configuration -> restore plugins headlessly from lazy-lock.json.
# Supports Arch, Debian/Ubuntu, Fedora, openSUSE, and macOS (Homebrew).

set -euo pipefail

REPO_HTTPS="https://github.com/koishi510/nvim.git"
REPO_SSH="git@github.com:koishi510/nvim.git"
NVIM_MIN_MINOR=11 # Require nvim >= 0.11

# Offline dictionary used by lua/user/core/dict.lua. The configuration expects
# it under ~/.local/share.
DICT_URL="https://github.com/skywind3000/ECDICT-ultimate/releases/download/1.0.0/ecdict-ultimate-sqlite.zip"
DICT_DB="$HOME/.local/share/trans/ultimate.db"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"

repo_url="$REPO_HTTPS"
skip_deps=0
with_extras=0
skip_sync=0
run_mason=0
with_dict=0

usage() {
	cat <<'EOF'
Usage: deploy.sh [options]

  --ssh           Clone over SSH (HTTPS is the default and needs no key setup)
  --repo <url>    Use a custom repository URL
  --no-deps       Skip system dependency installation
  --with-extras   Install optional dependencies (lazygit, Node.js, poppler, sqlite3, etc.)
  --mason         Run :MasonToolsInstallSync headlessly after deployment
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
	--mason) run_mason=1 ;;
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

install_deps() {
	detect_pkg_mgr
	if [ -z "$PKG_MGR" ]; then
		warn "Could not detect a package manager. Install these manually: git neovim>=0.11 ripgrep fd a C compiler unzip curl tar"
		return
	fi
	info "Installing dependencies with $PKG_MGR"

	local required extras
	case "$PKG_MGR" in
	pacman)
		required=(git neovim ripgrep fd gcc unzip curl tar)
		extras=(lazygit nodejs npm yarn poppler sqlite)
		;;
	apt)
		$SUDO apt-get update
		required=(git neovim ripgrep fd-find build-essential unzip curl tar)
		extras=(lazygit nodejs npm poppler-utils sqlite3)
		;;
	dnf)
		required=(git neovim ripgrep fd-find gcc unzip curl tar)
		extras=(lazygit nodejs poppler-utils sqlite)
		;;
	zypper)
		required=(git neovim ripgrep fd gcc unzip curl tar)
		extras=(lazygit nodejs poppler-tools sqlite3)
		;;
	brew)
		required=(git neovim ripgrep fd)
		extras=(lazygit node yarn poppler sqlite)
		;;
	esac

	pkg_install "${required[@]}" || warn "Some required dependencies failed to install; check the output above"

	if [ "$with_extras" -eq 1 ]; then
		local pkg
		for pkg in "${extras[@]}"; do
			pkg_install "$pkg" || warn "Optional dependency $pkg failed to install; skipping it"
		done
	fi

	# Debian and Ubuntu package fd as fdfind, so provide an fd symlink.
	if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
		mkdir -p "$LOCAL_BIN"
		ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
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

	case ":$PATH:" in
	*":$LOCAL_BIN:"*) ;;
	*) warn "$LOCAL_BIN is not in PATH; add 'export PATH=\"$LOCAL_BIN:\$PATH\"' to your shell configuration" ;;
	esac
	hash -r
	nvim_ok || die "Neovim is still unavailable after installation; check PATH"
}

# ------------------------------------------------------- Configuration deployment

deploy_config() {
	if [ -d "$CONFIG_DIR/.git" ]; then
		local origin
		origin=$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null || true)
		case "$origin" in
		*koishi510/nvim* | "$repo_url")
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

	if [ "$run_mason" -eq 1 ]; then
		info "Installing Mason formatter and linter tools"
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
  - Mason installs language servers when their corresponding file types are opened.
  - Inline images and PDF previews require kitty and poppler; --with-extras installs poppler.
  - The offline dictionary expects ECDICT-ultimate at ~/.local/share/trans/ultimate.db.
    Use --dict to download it from github.com/skywind3000/ECDICT-ultimate.
EOF
