#!/bin/bash
# Author: Isaaclins
#
# setup.sh
# Usage: 
#   ./setup.sh 
# thats it. it should install everything like I want. not like you want.

# IMPORTANT STUFF:
# - $DOTFILES_DIR is set to the path to your dotfiles directory


# PROCESS:
# 1. Ask for the path to your dotfiles directory
# -> set $DOTFILES_DIR
# 2. Install Homebrew
# 3. Install fish using Homebrew
# 4. Install Ghostty using Homebrew
# 5. Install Cursor using Homebrew
#
#
#
#


set -e  # Exit on any error

echo "🚀 Starting dotfiles setup..."

read -rp "Enter the path to your dotfiles directory: " DOTFILES_DIR

launchctl setenv DOTFILES_DIR "$DOTFILES_DIR"
echo "DOTFILES_DIR is set to $(launchctl getenv DOTFILES_DIR)"

# Function to ask user for installation confirmation
ask_install() {
    local app_name="$1"
    local install_command="$2"
    
    if command -v "$app_name" &> /dev/null; then
        echo "✅ $app_name is already installed."
        return 0
    fi
    
    while true; do
        read -rp "Do you want to install $app_name? (y/n): " yn
        case $yn in
            [Yy]* ) 
                echo "Installing $app_name..."
                eval "$install_command"
                break
                ;;
            [Nn]* ) 
                echo "Skipping $app_name installation."
                break
                ;;
            * ) 
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

# check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    ask_install "Homebrew" "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
else
    echo "✅ Homebrew is already installed."
fi

# check if fish is installed
ask_install "fish" "brew install fish"

# check if Ghostty is installed
ask_install "ghostty" "brew install ghostty"

# check if Cursor is installed
ask_install "cursor" "brew install cursor"