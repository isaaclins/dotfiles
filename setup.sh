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
PYTHON_BIN=""

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

brew_formula_installed() {
    brew list --formula --versions "$1" >/dev/null 2>&1
}

brew_cask_installed() {
    brew list --cask --versions "$1" >/dev/null 2>&1
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
            [Nn]*)
                log_warn "Skipping $formula installation."
                break
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done

    return 0
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

cask_bundle_present() {
    local cask="$1"

    if [ -z "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
        return 1
    fi

    local json
    json="$(brew info --cask --json=v2 "$cask" 2>/dev/null)" || return 1

    local -a app_names=()
    while IFS= read -r name; do
        [ -n "$name" ] && app_names+=("$name")
    done < <(printf '%s' "$json" | "$PYTHON_BIN" - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

apps = set()

def gather(node):
    if isinstance(node, str):
        if node.endswith('.app'):
            apps.add(node)
    elif isinstance(node, list):
        for item in node:
            gather(item)
    elif isinstance(node, dict):
        for value in node.values():
            gather(value)

for cask in data.get('casks', []):
    for artifact in cask.get('artifacts', []):
        gather(artifact)

for app in sorted(apps):
    print(app)
PY
)

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
        if brew install --cask "$cask"; then
            return 0
        fi
        log_warn "Failed to install $cask via brew; continuing."
        return 1
    fi

    while true; do
        read -rp "Do you want to install $cask (cask)? (y/n): " yn
        case $yn in
            [Yy]*)
                log_info "Installing $cask..."
                if brew install --cask "$cask"; then
                    return 0
                fi
                log_warn "Failed to install $cask via brew; continuing."
                return 1
                ;;
            [Nn]*)
                log_warn "Skipping $cask installation."
                return 0
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

install_cask_with_fallback() {
    local candidate
    for candidate in "$@"; do
        if brew info --cask "$candidate" >/dev/null 2>&1; then
            if install_cask "$candidate"; then
                return 0
            fi
        fi
    done

    log_warn "No suitable cask found among: $*"
    return 1
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

mas_install() {
    local app_name="$1"
    local app_id="$2"

    if ! command -v mas >/dev/null 2>&1; then
        log_warn "mas CLI not installed; skipping App Store apps."
        return 1
    fi

    if mas list | awk '{print $1}' | grep -Fxq "$app_id"; then
        log_ok "App Store app already installed: $app_name"
        return 0
    fi

    if [ $YES -eq 1 ]; then
        log_info "Installing $app_name from App Store..."
        if mas install "$app_id"; then
            return 0
        fi
        log_warn "Failed to install $app_name from App Store."
        return 1
    fi

    while true; do
        read -rp "Install $app_name from App Store? (y/n): " yn
        case $yn in
            [Yy]*)
                log_info "Installing $app_name from App Store..."
                if mas install "$app_id"; then
                    return 0
                fi
                log_warn "Failed to install $app_name from App Store."
                return 1
                ;;
            [Nn]*)
                log_warn "Skipping App Store install for $app_name."
                return 0
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

install_formulas() {
    local formula
    for formula in "$@"; do
        install_formula "$formula"
    done
}

install_casks() {
    local cask
    for cask in "$@"; do
        install_cask "$cask"
    done
}

FORMULAE=(
    git
    fish
    mas
    curl
    wget
    jq
    yq
    fd
    ripgrep
    fzf
    eza
    bat
    neovim
    tmux
    starship
    htop
    tree
    python
    node
    pnpm
)

CASKS=(
    1password
    alfred
    arc
    discord
    docker
    figma
    firefox
    google-chrome
    iterm2
    linear-linear
    obsidian
    slack
    spotify
    visual-studio-code
    zoom
)

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
        ensure_python

        install_formulas "${FORMULAE[@]}"

        log_info "Installing commonly used casks..."
        install_cask_with_fallback amphetamine amphetamine-beta
        install_casks "${CASKS[@]}"
    else
        log_warn "Homebrew not available; skipping brew installs."
    fi

    deploy_hammerspoon
    configure_shell_env

    deploy_fish
    deploy_git
    deploy_misc

    if command -v mas >/dev/null 2>&1; then
        mas_install "Xcode" 497799835
    fi

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
