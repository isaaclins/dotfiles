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
        if ! brew install --cask "$cask"; then
            log_warn "Failed to install $cask via brew; continuing."
        fi

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            YES=1
            [Yy]*)
                log_info "Installing $cask..."
            PYTHON_BIN=""
                if ! brew install --cask "$cask"; then
                    log_warn "Failed to install $cask via brew; continuing."
                fi
                break
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

DEFAULT_HS_CONFIG_DIR="$HOME/.config/hammerspoon"
HS_CONFIG_DIR="${HS_CONFIG:-$DEFAULT_HS_CONFIG_DIR}"
export HS_CONFIG="$HS_CONFIG_DIR"

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
        if ! brew install "$formula"; then
            log_warn "Failed to install $formula via brew; continuing."
            return 1
        fi
        return 0
    fi
    while true; do
        read -rp "Do you want to install $formula (formula)? (y/n): " yn
        case $yn in
            [Yy]*)
                log_info "Installing $formula..."
                if ! brew install "$formula"; then
                    log_warn "Failed to install $formula via brew; continuing."
                    return 1
                fi
                break
                ;;
            [Nn]*) log_warn "Skipping $formula installation."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
    return 0
}

install_cask() {
    local cask="$1"
    if ! brew info --cask "$cask" >/dev/null 2>&1; then
        log_warn "Cask not found: $cask"
        return 1
    fi

    if cask_bundle_present "$cask"; then
        return 0
    fi

    if brew_cask_installed "$cask"; then
        log_ok "$cask is already installed (cask)."
        return 0
    fi
    if [ $YES -eq 1 ]; then
        log_info "Installing $cask (cask)..."

cask_bundle_present() {
    local cask="$1"

    if [ -z "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
        return 1
    fi

    local json
    if ! json="$(brew info --cask --json=v2 "$cask" 2>/dev/null)"; then
        return 1
    fi

    local -a app_names=()
    while IFS= read -r name; do
        [ -n "$name" ] && app_names+=("$name")
    done < <(printf '%s' "$json" | python3 - <<'PY'
    done < <(printf '%s' "$json" | "$PYTHON_BIN" - <<'PY'
        if ! brew install --cask "$cask"; then
            log_warn "Failed to install $cask via brew; continuing."
            return 1
        fi
        return 0
    fi
    while true; do
        read -rp "Do you want to install $cask (cask)? (y/n): " yn
        case $yn in
            [Yy]*)
                log_info "Installing $cask..."
                if ! brew install --cask "$cask"; then
                    log_warn "Failed to install $cask via brew; continuing."
                    return 1
                fi
                break
                ;;
            [Nn]*) log_warn "Skipping $cask installation."; break ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
    return 0
}

install_cask_with_fallback() {
    # Try each provided cask name until one succeeds

    if [ ${#app_names[@]} -eq 0 ]; then
        return 1
    fi

    local search_dirs=(
        "/Applications"
        "/Applications/Utilities"
        "$HOME/Applications"
    )

    local name dir
    for name in "${app_names[@]}"; do
        for dir in "${search_dirs[@]}"; do
            if [ -e "$dir/$name" ]; then
                log_ok "$cask app detected at $dir/$name (skipping brew cask)."
                return 0
            fi
        done
    done

    return 1
}
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

ensure_command_line_tools() {
    if xcode-select -p >/dev/null 2>&1; then
        log_ok "Command Line Tools already installed."
        return 0
    fi

    if [ $YES -eq 1 ]; then
        log_info "Installing Xcode Command Line Tools (GUI prompt will appear)..."
        if xcode-select --install >/dev/null 2>&1; then
            log_info "Command Line Tools installation requested; rerun after completion if needed."
        else
            log_warn "Unable to trigger Command Line Tools installer automatically."
        fi
        return 0
    fi

    while true; do
        read -rp "Xcode Command Line Tools not detected. Install now? (y/n): " yn
        case $yn in
            [Yy]*)
                if xcode-select --install >/dev/null 2>&1; then
                    log_info "Command Line Tools installation requested; rerun after completion if needed."
                else
                    log_warn "Unable to trigger Command Line Tools installer automatically."
                fi
                break
                ;;
            [Nn]*)
                log_warn "Skipping Command Line Tools installation. Some tooling may fail."
                break
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

ensure_python() {
    if [ -n "$PYTHON_BIN" ] && [ -x "$PYTHON_BIN" ]; then
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="$(command -v python3)"
        return 0
    fi

    if [ -x "/usr/bin/python3" ]; then
        PYTHON_BIN="/usr/bin/python3"
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        log_info "Installing python3 via Homebrew for setup helpers..."
        if install_formula python; then
            if command -v python3 >/dev/null 2>&1; then
                PYTHON_BIN="$(command -v python3)"
                return 0
            fi
        fi
    fi

    log_warn "Python 3 unavailable; app bundle detection will be skipped."
    return 1
}

ensure_line_in_file() {
    local file="$1"
    local line="$2"

    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -Fqx "$line" "$file" >/dev/null 2>&1; then
        return 1
    fi

    printf '%s\n' "$line" >>"$file"
    return 0
}

set_shell_export() {
    local file="$1"
    local var="$2"
    local value="$3"
    local line="export $var=\"$value\""

    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -Fqx "$line" "$file" >/dev/null 2>&1; then
        return 1
    fi

    if grep -Eq "^export $var=" "$file" >/dev/null 2>&1; then
        local tmp
        tmp="$(mktemp "${TMPDIR:-/tmp}/dotfiles-export.XXXXXX")"
        awk -v var="$var" -v repl="$line" '
            $0 ~ "^export "var"=" { print repl; next }
            { print }
        ' "$file" >"$tmp"
        mv "$tmp" "$file"
        return 0
    fi

    printf '%s\n' "$line" >>"$file"
    return 0
}

backup_existing() {
    local path="$1"
    local backup_root="$DOTFILES_DIR/.backups"
    local ts
    local name
    local backup_path

    mkdir -p "$backup_root"
    ts="$(date +%Y%m%d-%H%M%S)"
    name="$(basename "$path")"
    backup_path="$backup_root/$name.$ts"

    mv "$path" "$backup_path"
    log_warn "Moved existing $path to $backup_path"
}

link_path() {
    local src="$1"
    local dest="$2"

    if [ ! -e "$src" ]; then
        log_warn "Source path missing: $src"
        return 1
    fi

    if [ "$src" = "$dest" ]; then
        log_info "Skipping link for $dest; source and destination match."
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ]; then
        local current
        current="$(readlink "$dest")"
        if [ "$current" = "$src" ]; then
            log_ok "$dest already links to $src"
            return 0
        fi
    fi

    if [ -e "$dest" ]; then
        backup_existing "$dest"
    fi

    ln -sfn "$src" "$dest"
    log_ok "Linked $dest -> $src"
}

configure_shell_env() {
    if set_shell_export "$HOME/.zshrc" "HS_CONFIG" "$HS_CONFIG_DIR"; then
        log_ok "Updated HS_CONFIG export in $HOME/.zshrc"
    else
        log_info "HS_CONFIG export already up to date in $HOME/.zshrc"
    fi

    if set_shell_export "$HOME/.bashrc" "HS_CONFIG" "$HS_CONFIG_DIR"; then
        log_ok "Updated HS_CONFIG export in $HOME/.bashrc"
    else
        log_info "HS_CONFIG export already up to date in $HOME/.bashrc"
    fi

    if command -v fish >/dev/null 2>&1; then
        fish -c "set -Ux HS_CONFIG '$HS_CONFIG_DIR'" || log_warn "Failed to set HS_CONFIG in fish universal variables"
    fi

    if command -v launchctl >/dev/null 2>&1; then
        launchctl setenv HS_CONFIG "$HS_CONFIG_DIR" || true
    fi
}

deploy_hammerspoon() {
    local hs_src="$DOTFILES_DIR/hammerspoon"

    if [ ! -d "$hs_src" ]; then
        log_info "No hammerspoon directory found in dotfiles; skipping."
        return 0
    fi

    mkdir -p "$HS_CONFIG_DIR"

    for path in "$hs_src"/*; do
        [ -e "$path" ] || continue
        local name
        name="$(basename "$path")"
        link_path "$path" "$HS_CONFIG_DIR/$name"
    done

    defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HS_CONFIG_DIR/init.lua" 2>/dev/null || true
}

deploy_fish() {
    local fish_src="$DOTFILES_DIR/fish"
    local fish_dest="$HOME/.config/fish"

    if [ ! -d "$fish_src" ]; then
        log_info "No fish directory found in dotfiles; skipping."
        return 0
    fi

    link_path "$fish_src" "$fish_dest"
}

run_brewfile() {
    local brewfile="$DOTFILES_DIR/Brewfile"
    if [ -f "$brewfile" ]; then
        log_info "Applying Brewfile..."
        brew bundle --file "$brewfile" || log_warn "brew bundle encountered issues"
    fi
}

set_default_shell() {
    if [ $SET_DEFAULT_FISH -eq 0 ]; then
        return 0
    fi

    local fish_path
    fish_path="$(command -v fish || true)"

    if [ -z "$fish_path" ]; then
        log_warn "Fish shell not found; cannot set as default shell."
        return 0
    fi

    if ! grep -Fxq "$fish_path" /etc/shells >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            log_info "Adding $fish_path to /etc/shells (sudo may prompt)..."
            echo "$fish_path" | sudo tee -a /etc/shells >/dev/null || {
                log_warn "Failed to add $fish_path to /etc/shells"
                return 1
            }
        else
            log_warn "sudo unavailable; cannot add $fish_path to /etc/shells"
            return 1
        fi
    fi

    if [ "${SHELL:-}" = "$fish_path" ]; then
        log_ok "Fish is already the default shell."
        return 0
    fi

    if chsh -s "$fish_path"; then
        log_ok "Default shell changed to fish ($fish_path)."
    else
        log_warn "Failed to change default shell to fish."
    fi
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

ensure_command_line_tools
ensure_homebrew

if command -v brew >/dev/null 2>&1; then
    setup_brew_env || true
    log_info "Updating Homebrew..."
    brew update >/dev/null 2>&1 || log_warn "brew update encountered an issue"

    ensure_python || true

    run_brewfile

    FORMULAE=(
        git
        fish
        python
        mas
    )

    for formula in "${FORMULAE[@]}"; do
        install_formula "$formula" || true
    done

    CASKS=(
        ghostty
        cursor
        hammerspoon
        alt-tab
        middleclick
        appcleaner
        horo
        latest
        tinkertool
        aldente
    )

    for cask in "${CASKS[@]}"; do
        install_cask "$cask" || true
    done

    install_cask_with_fallback raycast || true
    install_cask_with_fallback zen zen-browser || true
    if ! install_cask_with_fallback amphetamine; then
        install_mas_app "Amphetamine" 937984704 || true
    fi
else
    log_warn "Homebrew is unavailable; skipping package installations."
fi

deploy_fish
deploy_hammerspoon
configure_shell_env
set_default_shell

log_ok "✨ Dotfiles setup complete."
