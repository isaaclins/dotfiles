#!/usr/bin/env bash
# Author: Isaaclins
#
# setup.sh
# Usage:
#   ./setup.sh [options]
#
# thats it. it should install everything like I want. not like you want.
#
# IMPORTANT STUFF:
# - $DOTFILES_DIR is set to the path to your dotfiles directory

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

# Colored output helpers (only if stdout is a TTY)
if [ -t 1 ]; then
    BOLD='\033[1m'; RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; RESET='\033[0m'
else
    BOLD=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; RESET=''
fi

log_info()  { echo -e "${BLUE}[*]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[✔]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
log_error() { echo -e "${RED}[x]${RESET} $*" 1>&2; }

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Setup failed with exit code $exit_code"
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
${BOLD}Dotfiles setup${RESET}

Usage: ./${SCRIPT_NAME} [options]

Options:
  -y, --yes               Run non-interactively; assume "yes" to prompts
  -d, --dotfiles-dir PATH Use PATH as DOTFILES_DIR
  --set-default-fish      Set fish as the default shell (may prompt for sudo)
  -h, --help              Show this help message and exit

Environment:
  DOTFILES_DIR            Path to your dotfiles directory. Defaults to the directory
                          containing this script if not set.
EOF
}
YES=0
SET_DEFAULT_FISH=0
DOTFILES_DIR_ARG=0

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            YES=1
            ;;
        -d|--dotfiles-dir)
            if [ $# -lt 2 ]; then
                log_error "Missing PATH for $1"
                usage
                exit 1
            fi
            DOTFILES_DIR="$2"
            DOTFILES_DIR_ARG=1
            shift
            ;;
        --set-default-fish)
            SET_DEFAULT_FISH=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

log_info "🚀 Starting dotfiles setup..."

# Default DOTFILES_DIR to the folder containing this script if not provided
DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$DEFAULT_DIR}"

if [ $YES -eq 0 ] && [ ${DOTFILES_DIR_ARG:-0} -eq 0 ]; then
    read -rp "Enter the path to your dotfiles directory [${DOTFILES_DIR}]: " _input || true
    if [ -n "${_input:-}" ]; then
        DOTFILES_DIR="${_input}"
    fi
fi

if [ ! -d "$DOTFILES_DIR" ]; then
    log_error "DOTFILES_DIR does not exist: $DOTFILES_DIR"
    exit 1
fi

if command -v launchctl >/dev/null 2>&1; then
    launchctl setenv DOTFILES_DIR "$DOTFILES_DIR" || true
    log_ok "DOTFILES_DIR is set to $(launchctl getenv DOTFILES_DIR 2>/dev/null || echo "$DOTFILES_DIR")"
else
    export DOTFILES_DIR
    log_ok "DOTFILES_DIR exported for this session: $DOTFILES_DIR"
fi

setup_brew_env() {
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        return 0
    fi
    if [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        return 0
    fi
    return 1
}

install_homebrew() {
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    setup_brew_env || true
}

ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        setup_brew_env || true
        log_ok "Homebrew is already installed."
        return 0
    fi

    if [ $YES -eq 1 ]; then
        install_homebrew
        return 0
    fi

    while true; do
        read -rp "Homebrew not found. Install it now? (y/n): " yn
        case $yn in
            [Yy]*) install_homebrew; break ;;
            [Nn]*) log_warn "Skipping Homebrew installation. Some installs may fail."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

brew_formula_installed() {
    brew list --formula --versions "$1" >/dev/null 2>&1
}

brew_cask_installed() {
    brew list --cask --versions "$1" >/dev/null 2>&1
}

install_formula() {
    local formula="$1"
    if brew_formula_installed "$formula"; then
        log_ok "$formula is already installed (formula)."
        return 0
    fi
    if [ $YES -eq 1 ]; then
        log_info "Installing $formula..."
        brew install "$formula"
        return 0
    fi
    while true; do
        read -rp "Do you want to install $formula (formula)? (y/n): " yn
        case $yn in
            [Yy]*) log_info "Installing $formula..."; brew install "$formula"; break ;;
            [Nn]*) log_warn "Skipping $formula installation."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

install_cask() {
    local cask="$1"
    if ! brew info --cask "$cask" >/dev/null 2>&1; then
        log_warn "Cask not found: $cask"
        return 1
    fi
    if brew_cask_installed "$cask"; then
        log_ok "$cask is already installed (cask)."
        return 0
    fi
    if [ $YES -eq 1 ]; then
        log_info "Installing $cask (cask)..."
        brew install --cask "$cask"
        return 0
    fi
    while true; do
        read -rp "Do you want to install $cask (cask)? (y/n): " yn
        case $yn in
            [Yy]*) log_info "Installing $cask..."; brew install --cask "$cask"; break ;;
            [Nn]*) log_warn "Skipping $cask installation."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

install_cask_with_fallback() {
    # Try each provided cask name until one succeeds
    local tried=()
    for candidate in "$@"; do
        if brew info --cask "$candidate" >/dev/null 2>&1; then
            if install_cask "$candidate"; then
                return 0
            fi
        else
            tried+=("$candidate")
        fi
    done
    if [ ${#tried[@]} -gt 0 ]; then
        log_warn "No available cask found among: ${tried[*]}"
    fi
    return 1
}

mas_signed_in() {
    command -v mas >/dev/null 2>&1 || return 1
    mas account >/dev/null 2>&1
}

mas_app_installed() {
    local app_id="$1"
    command -v mas >/dev/null 2>&1 || return 1
    mas list | awk '{print $1}' | grep -qx "$app_id"
}

install_mas_app() {
    local app_name="$1"
    local app_id="$2"
    # Ensure mas is available
    if ! command -v mas >/dev/null 2>&1; then
        install_formula mas || true
    fi

    if ! command -v mas >/dev/null 2>&1; then
        log_warn "mas CLI not available; cannot install ${app_name} from App Store."
        return 1
    fi

    if ! mas_signed_in; then
        log_warn "Not signed into the Mac App Store. Skipping ${app_name} installation."
        return 0
    fi

    if mas_app_installed "$app_id"; then
        log_ok "${app_name} is already installed via App Store."
        return 0
    fi

    if [ $YES -eq 1 ]; then
        log_info "Installing ${app_name} from the Mac App Store..."
        mas install "$app_id" || log_warn "Failed to install ${app_name} via mas."
        return 0
    fi

    while true; do
        read -rp "Install ${app_name} from the Mac App Store now? (y/n): " yn
        case $yn in
            [Yy]*) log_info "Installing ${app_name}..."; mas install "$app_id" || log_warn "Failed to install ${app_name} via mas."; break ;;
            [Nn]*) log_warn "Skipping ${app_name} installation."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

ensure_homebrew

# Core tools
install_formula git
install_formula fish

# Apps
install_cask ghostty
install_cask cursor
install_cask_with_fallback raycast
install_cask_with_fallback zen zen-browser
if ! install_cask_with_fallback amphetamine; then
    # Amphetamine is App Store-only; fall back to MAS (App ID 937984704)
    install_mas_app "Amphetamine" 937984704 || true
fi
install_cask_with_fallback alt-tab
install_cask_with_fallback hammerspoon
install_cask_with_fallback middleclick
install_cask_with_fallback appcleaner
install_cask_with_fallback horo
install_cask_with_fallback latest
install_cask_with_fallback tinkertool
install_cask_with_fallback aldente

ask_install "fish" "brew install fish"
ask_install "ghostty" "brew install ghostty"
ask_install "cursor" "brew install cursor"
ask_install "hammerspoon" "brew install hammerspoon"
defaults write org.hammerspoon.Hammerspoon MJConfigFile "$DOTFILES_DIR/hammerspoon/init.lua"

