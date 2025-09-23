#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title generate_password
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.description generates a 24 char, upper/lower case with symbols password, copies it to clip and force pastes it at the same time.
# @raycast.author isaaclins
# @raycast.authorURL https://raycast.com/isaaclins

set -eu

# Generate a password that contains at least 2 of each: lowercase, uppercase, digits, and symbols.
while true; do
    password=$(LC_ALL=C tr -dc 'A-Za-z0-9+*@#=' < /dev/urandom | head -c 24)
    # Ensure the password is 24 characters long to avoid issues with EOF from /dev/urandom
    if [[ ${#password} -ne 24 ]]; then
        continue
    fi

    symbols=0
    capitals=0
    lowers=0
    numbers=0
    for (( i=0; i<${#password}; i++ )); do
        char="${password:$i:1}"
        case "$char" in
            [a-z]) ((lowers++)) ;;
            [A-Z]) ((capitals++)) ;;
            [0-9]) ((numbers++)) ;;
            [+*@#=]) ((symbols++)) ;;
        esac
    done

    if [[ $symbols -ge 2 && $capitals -ge 2 && $lowers -ge 2 && $numbers -ge 2 ]]; then
        break
    fi
done

# Copy to clipboard without a trailing newline
printf "%s" "$password" | pbcopy

# Small delay to ensure clipboard is updated
sleep 0.1

# Force paste into the frontmost application (requires Accessibility permissions for Terminal/Raycast)
osascript -e 'tell application "System Events" to keystroke "v" using {command down}'

# Also print to stdout in case this is run outside Raycast
printf "%s\n" "$password"

