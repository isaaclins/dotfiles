#!/usr/bin/env bash
# Author: Isaaclins
#
# setup.sh
# Usage:
#   ./setup.sh [options]
#
# Run this on a fresh macOS install to bootstrap Homebrew, apply dotfiles, and
# kick off the interactive installer TUI that reads from your Brewfile.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

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

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")" && pwd)}"
HS_CONFIG_DIR="$HOME/.hammerspoon"
FISH_EXPORT_FILE="$HOME/.config/fish/conf.d/dotfiles_exports.fish"

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

ensure_rust_toolchain() {
    if command -v cargo >/dev/null 2>&1; then
        log_ok "Rust toolchain already installed."
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        log_warn "Homebrew unavailable; cannot install Rust automatically."
        return 1
    fi

    log_info "Installing Rust toolchain via Homebrew..."
    if brew install rust; then
        setup_brew_env || true
    else
        log_warn "brew install rust failed."
    fi

    if command -v cargo >/dev/null 2>&1; then
        log_ok "Rust toolchain is ready."
        return 0
    fi

    log_warn "Rust toolchain unavailable; skipping installer build."
    return 1
}

run_brewfile() {
    local brewfile="$DOTFILES_DIR/Brewfile"
    if [ ! -f "$brewfile" ]; then
        log_warn "No Brewfile found at $brewfile"
        return 1
    fi

    log_info "Running brew bundle..."
    if ! brew bundle --file="$brewfile"; then
        log_warn "brew bundle reported errors; continuing."
    fi
}

build_and_run_installer() {
    local manifest="$DOTFILES_DIR/scripts/install_tools_tui/Cargo.toml"
    if [ ! -f "$manifest" ]; then
        log_warn "Installer manifest not found at $manifest; skipping TUI build."
        return 1
    fi

    if ! command -v cargo >/dev/null 2>&1; then
        log_warn "Cargo not available; skipping installer build."
        return 1
    fi

    log_info "Building install_tools_tui (release)..."
    if ! cargo build --release --manifest-path "$manifest"; then
        log_error "Failed to build install_tools_tui."
        return 1
    fi

    local binary="$DOTFILES_DIR/scripts/install_tools_tui/target/release/install_tools_tui"
    if [ ! -x "$binary" ]; then
        log_error "Built installer not found at $binary."
        return 1
    fi

    log_info "Launching install_tools_tui..."
    if ! BREWFILE_PATH="$DOTFILES_DIR/Brewfile" "$binary"; then
        log_error "Installer TUI exited with an error."
        return 1
    fi

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
        if set_shell_export "$FISH_EXPORT_FILE" "HS_CONFIG" "$HS_CONFIG_DIR"; then
            log_ok "Updated HS_CONFIG export in fish conf.d"
        else
            log_info "HS_CONFIG export already up to date in fish conf.d"
        fi
    fi
}

set_default_shell() {
    local target_shell="$1"

    if [ -z "$target_shell" ]; then
        log_warn "No shell specified for set_default_shell."
        return 1
    fi

    local shell_path
    shell_path="$(command -v "$target_shell")" || {
        log_warn "Shell not found in PATH: $target_shell"
        return 1
    }

    if [ "$SHELL" = "$shell_path" ]; then
        log_ok "$target_shell is already the default shell."
        return 0
    fi

    if ! grep -Fxq "$shell_path" /etc/shells; then
        if [ $YES -eq 1 ]; then
            log_info "Adding $shell_path to /etc/shells (requires sudo)..."
            if ! echo "$shell_path" | sudo tee -a /etc/shells >/dev/null; then
                log_warn "Failed to add $shell_path to /etc/shells."
                return 1
            fi
        else
            log_warn "$shell_path is not in /etc/shells. Add it manually and rerun."
            return 1
        fi
    fi

    if [ $YES -eq 1 ]; then
        log_info "Changing default shell to $target_shell..."
        if chsh -s "$shell_path"; then
            log_ok "Default shell changed to $target_shell."
        else
            log_warn "Failed to change default shell to $target_shell."
        fi
    else
        log_warn "Skipping default shell change. Run with --set-default-fish or use -y for non-interactive."
    fi
}

deploy_hammerspoon() {
    local hammerspoon_src="$DOTFILES_DIR/hammerspoon"
    local hammerspoon_dest="$HOME/.hammerspoon"

    if [ ! -d "$hammerspoon_src" ]; then
        log_warn "Hammerspoon config directory not found at $hammerspoon_src"
        return 1
    fi

    link_path "$hammerspoon_src" "$hammerspoon_dest"
    HS_CONFIG_DIR="$hammerspoon_dest"

    if command -v defaults >/dev/null 2>&1; then
        log_info "Pointing Hammerspoon at $HS_CONFIG_DIR/init.lua..."
        defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HS_CONFIG_DIR/init.lua" || true
    fi

    if command -v osascript >/dev/null 2>&1; then
        log_info "Restarting Hammerspoon for configuration reload..."
        osascript -e 'tell application "Hammerspoon" to quit' || true
        sleep 1
        osascript -e 'tell application "Hammerspoon" to activate' || true
    fi
}

deploy_fish() {
    local fish_src="$DOTFILES_DIR/fish"
    local fish_dest="$HOME/.config/fish"

    if [ ! -d "$fish_src" ]; then
        log_warn "Fish config directory not found at $fish_src"
        return 1
    fi

    link_path "$fish_src" "$fish_dest"
}

deploy_git() {
    local git_src="$DOTFILES_DIR/git"
    local git_dest="$HOME/.config/git"

    if [ ! -d "$git_src" ]; then
        log_warn "Git config directory not found at $git_src"
        return 1
    fi

    link_path "$git_src" "$git_dest"

    if [ -f "$git_dest/ignore" ]; then
        git config --global core.excludesfile "$git_dest/ignore"
        log_ok "Configured global gitignore."
    fi
}

deploy_misc() {
    link_path "$DOTFILES_DIR/htop/htoprc" "$HOME/.config/htop/htoprc"
    link_path "$DOTFILES_DIR/neofetch/config.conf" "$HOME/.config/neofetch/config.conf"
}

main() {
    log_info "Starting setup..."

    if [ $DOTFILES_DIR_ARG -eq 0 ]; then
        local default_dir="$DOTFILES_DIR"
        read -rp "Dotfiles directory [$default_dir]: " input
        if [ -n "$input" ]; then
            DOTFILES_DIR="$(cd "$input" && pwd)"
        fi
    fi

    if [ ! -d "$DOTFILES_DIR" ]; then
        log_error "Dotfiles directory not found: $DOTFILES_DIR"
        exit 1
    fi

    log_info "Using DOTFILES_DIR=$DOTFILES_DIR"

    ensure_command_line_tools
    ensure_homebrew

    if command -v brew >/dev/null 2>&1; then
        run_brewfile
        if ensure_rust_toolchain; then
            build_and_run_installer || log_warn "Installer TUI encountered issues."
        else
            log_warn "Rust toolchain unavailable; skipping installer build."
        fi
    else
        log_warn "Homebrew not available; skipping brew installs."
    fi

    deploy_hammerspoon
    configure_shell_env

    deploy_fish
    deploy_git
    deploy_misc

    if [ $SET_DEFAULT_FISH -eq 1 ]; then
        set_default_shell fish
    fi

    log_ok "Setup complete. 🚀"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)
            YES=1
            shift
            ;;
        --set-default-fish)
            SET_DEFAULT_FISH=1
            shift
            ;;
        -d|--dotfiles-dir)
            if [ $# -lt 2 ]; then
                log_error "--dotfiles-dir requires a path argument"
                exit 1
            fi
            DOTFILES_DIR="$(cd "$2" && pwd)"
            DOTFILES_DIR_ARG=1
            shift 2
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
done

main "$@"
