#!/usr/bin/env bash
# 跨设备部署本 Neovim 配置。
#
# 在新机器上（无需先克隆仓库）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/koishi510/nvim/main/deploy.sh)
#
# 或在已克隆的仓库内：
#   ./deploy.sh
#
# 流程：安装系统依赖 -> 确保 nvim >= 0.11 -> 备份并克隆配置 -> 按
# lazy-lock.json 无头还原插件。支持 Arch / Debian·Ubuntu / Fedora /
# openSUSE / macOS(Homebrew)。

set -euo pipefail

REPO_HTTPS="https://github.com/koishi510/nvim.git"
REPO_SSH="git@github.com:koishi510/nvim.git"
NVIM_MIN_MINOR=11 # 要求 nvim >= 0.11

# 离线词典（lua/user/core/dict.lua 使用，路径在配置里写死为 ~/.local/share）
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
用法: deploy.sh [选项]

  --ssh           用 SSH 地址克隆（默认 HTTPS，新机器无需配置密钥）
  --repo <url>    自定义仓库地址
  --no-deps       跳过系统依赖安装
  --with-extras   同时安装可选依赖（lazygit / node / yarn / poppler / sqlite3 ...）
  --mason         部署后无头执行 :MasonToolsInstallSync 批量安装 formatter/linter
  --dict          下载 ECDICT-ultimate 离线词典（压缩包约 300MB，解压后 1.2GB）
  --no-sync       跳过无头插件安装（之后首次打开 nvim 时再装）
  -h, --help      显示本帮助
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--ssh) repo_url="$REPO_SSH" ;;
	--repo)
		repo_url="${2:?--repo 需要一个地址}"
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
		echo "未知选项: $1" >&2
		usage >&2
		exit 1
		;;
	esac
	shift
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m警告:\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2
	exit 1
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	if command -v sudo >/dev/null; then
		SUDO="sudo"
	else
		warn "没有 sudo，系统包安装可能失败"
	fi
fi

# ---------------------------------------------------------------- 包管理器

PKG_MGR=""
detect_pkg_mgr() {
	if [ "$(uname -s)" = Darwin ]; then
		command -v brew >/dev/null || die "macOS 上请先安装 Homebrew: https://brew.sh"
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
		warn "无法识别包管理器，请自行安装: git neovim(>=0.11) ripgrep fd C编译器 unzip curl tar"
		return
	fi
	info "使用 $PKG_MGR 安装依赖"

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

	pkg_install "${required[@]}" || warn "部分必需依赖安装失败，请检查上方输出"

	if [ "$with_extras" -eq 1 ]; then
		local pkg
		for pkg in "${extras[@]}"; do
			pkg_install "$pkg" || warn "可选依赖 $pkg 安装失败，跳过"
		done
	fi

	# Debian/Ubuntu 的 fd 叫 fdfind，补一个 fd 软链接
	if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
		mkdir -p "$LOCAL_BIN"
		ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
		info "已链接 fdfind -> $LOCAL_BIN/fd"
	fi
}

# ------------------------------------------------------- nvim 版本兜底

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
	[ "$(uname -s)" = Linux ] || die "请手动安装 Neovim >= 0.$NVIM_MIN_MINOR"
	local arch asset
	case "$(uname -m)" in
	x86_64) arch=x86_64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) die "未支持的架构 $(uname -m)，请手动安装 Neovim >= 0.$NVIM_MIN_MINOR" ;;
	esac
	asset="nvim-linux-$arch"

	info "从 GitHub Releases 安装最新稳定版 Neovim 到 $LOCAL_OPT/$asset"
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
	*) warn "$LOCAL_BIN 不在 PATH 中，请把 'export PATH=\"$LOCAL_BIN:\$PATH\"' 加入 shell 配置" ;;
	esac
	hash -r
	nvim_ok || die "Neovim 安装后仍不可用，请检查 PATH"
}

# ---------------------------------------------------------------- 配置部署

deploy_config() {
	if [ -d "$CONFIG_DIR/.git" ]; then
		local origin
		origin=$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null || true)
		case "$origin" in
		*koishi510/nvim* | "$repo_url")
			info "检测到已有配置仓库，执行 git pull"
			git -C "$CONFIG_DIR" pull --ff-only || warn "pull 失败（本地有改动？），保持现状"
			return
			;;
		esac
	fi

	if [ -e "$CONFIG_DIR" ]; then
		local backup
		backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
		info "备份现有配置到 $backup"
		mv "$CONFIG_DIR" "$backup"
	fi

	info "克隆 $repo_url -> $CONFIG_DIR"
	git clone --depth 1 "$repo_url" "$CONFIG_DIR"
}

# ---------------------------------------------------------------- 离线词典

install_dict() {
	if [ -s "$DICT_DB" ]; then
		info "词典已存在: $DICT_DB，跳过下载"
		return
	fi
	if ! command -v unzip >/dev/null; then
		warn "缺少 unzip，跳过词典安装；可手动下载: $DICT_URL"
		return
	fi

	info "下载 ECDICT-ultimate 词典（压缩包约 300MB，解压后 1.2GB）"
	local tmp
	tmp=$(mktemp -d)
	mkdir -p "$(dirname "$DICT_DB")"
	if curl -fL --progress-bar "$DICT_URL" -o "$tmp/ecdict.zip" &&
		unzip -o "$tmp/ecdict.zip" -d "$(dirname "$DICT_DB")" >/dev/null &&
		[ -s "$DICT_DB" ]; then
		info "词典安装完成: $DICT_DB"
	else
		warn "词典下载或解压失败，可手动安装: $DICT_URL"
	fi
	rm -rf "$tmp"

	command -v sqlite3 >/dev/null ||
		warn "查询词典还需要 sqlite3（--with-extras 会安装，或手动安装）"
}

# ------------------------------------------------------------ 无头初始化

sync_plugins() {
	info "按 lazy-lock.json 无头安装插件（首次可能需要几分钟）"
	nvim --headless "+Lazy! restore" +qa || warn "插件安装出错，可稍后在 nvim 内执行 :Lazy restore"

	if [ "$run_mason" -eq 1 ]; then
		info "批量安装 Mason 工具（formatter / linter）"
		nvim --headless "+MasonToolsInstallSync" +qa ||
			warn "Mason 工具安装出错，可稍后在 nvim 内执行 :MasonToolsInstall"
	fi
}

# -------------------------------------------------------------------- 主流程

[ "$skip_deps" -eq 1 ] || install_deps

if ! nvim_ok; then
	warn "未找到 Neovim >= 0.$NVIM_MIN_MINOR，尝试从官方 Release 安装"
	install_nvim_tarball
fi
info "Neovim: $(nvim --version | head -1)"

deploy_config

[ "$with_dict" -eq 0 ] || install_dict

[ "$skip_sync" -eq 1 ] || sync_plugins

info "部署完成，运行 nvim 开始使用"
cat <<'EOF'

提示:
  - 终端请使用 Nerd Font 字体，否则图标显示异常
  - 语言服务器会在打开对应文件时由 Mason 自动安装
  - 内联图片 / PDF 预览需要 kitty 终端 + poppler（--with-extras 可装 poppler）
  - 离线词典需要 ECDICT-ultimate 数据库: ~/.local/share/trans/ultimate.db
    （--dict 可自动下载，来源: github.com/skywind3000/ECDICT-ultimate）
EOF
