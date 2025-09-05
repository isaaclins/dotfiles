#!/bin/bash
# Author: @isaaclins
# Date: 2025-06-05
# Version: 1.0.0
# Description: Convert text to binary and vice-versa.
# Usage: echo 'text' | binary OR binary 'text'
# Flags:
#   -e: Encode text to binary.
#   -d: Decode binary to text.
# Supports explicit encoding (-e), decoding (-d), or auto-detection.

encode_to_binary() {
    local text_input="$1"
    if [ -z "$text_input" ]; then
        echo # Output a blank line for empty input
        return 0
    fi
    local encoded_output
    encoded_output=$(echo -n "$text_input" | xxd -b -c 1 | awk '{printf "%s%s", (NR==1 ? "" : " "), $2}')
    echo "$encoded_output"
    return 0
}

decode_from_binary() {
    local binary_input="$1"
    local binary_input_no_spaces
    # Remove all whitespace (spaces, tabs, newlines)
    binary_input_no_spaces=$(echo "$binary_input" | tr -d '[:space:]')

    if [ -z "$binary_input_no_spaces" ]; then
        echo # Output a blank line for empty binary input
        return 0
    fi

    if ! [[ "$binary_input_no_spaces" =~ ^[01]+$ ]] || (( ${#binary_input_no_spaces} % 8 != 0 )); then
        echo "Error: Invalid binary string for decoding. Must contain only 0s and 1s, and its length (without spaces) must be a multiple of 8." >&2
        return 1 # Indicate failure
    fi

    local decoded_text=""
    for (( i=0; i<${#binary_input_no_spaces}; i+=8 )); do
        local byte_bin=${binary_input_no_spaces:i:8}
        local dec_val=$((2#$byte_bin))
        printf -v char_val "\\$(printf '%03o' "$dec_val")"
        decoded_text+="$char_val"
    done
    echo "$decoded_text"
    return 0
}

ACTION="" 

OPTIND=1 
while getopts ":de" opt; do
    case $opt in
        d)
            ACTION="decode"
            ;;
        e)
            ACTION="encode"
            ;;
        \\?)
            echo "Error: Invalid option -$OPTARG" >&2
            echo "Usage: $(basename "$0") [-d|-e] 'input string' OR echo 'input string' | $(basename "$0") [-d|-e]"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

INPUT_STRING=""
if [ -p /dev/stdin ]; then
    INPUT_STRING=$(cat)
    if [ $# -gt 0 ]; then 
        echo "Error: Received input from both pipe and arguments. Please provide input one way only." >&2
        echo "Usage: $(basename "$0") [-d|-e] 'input string' OR echo 'input string' | $(basename "$0") [-d|-e]"
        exit 1
    fi
elif [ $# -gt 0 ]; then 
    INPUT_STRING="$*"
else
    echo "Usage: $(basename "$0") [-d|-e] 'input string' OR echo 'input string' | $(basename "$0") [-d|-e]"
    echo "Flags:"
    echo "  -e: Encode text to binary."
    echo "  -d: Decode binary to text."
    echo "If no flags are given, the script attempts to auto-detect if the input is binary or text."
    exit 1
fi


if [ "$ACTION" == "encode" ]; then
    encode_to_binary "$INPUT_STRING"
elif [ "$ACTION" == "decode" ]; then
    if ! decode_from_binary "$INPUT_STRING"; then
        exit 1
    fi
else
    if [ -z "$INPUT_STRING" ]; then
        encode_to_binary "$INPUT_STRING"
        exit 0
    fi

    temp_input_for_check=$(echo "$INPUT_STRING" | tr -d '[:space:]')
    is_potentially_binary=false
    if [ -n "$temp_input_for_check" ] && \
       [[ "$temp_input_for_check" =~ ^[01]+$ ]] && \
       (( ${#temp_input_for_check} % 8 == 0 )); then
        is_potentially_binary=true
    fi

    if $is_potentially_binary; then
        if ! decode_from_binary "$INPUT_STRING"; then
            exit 1
        fi
    else
        encode_to_binary "$INPUT_STRING"
    fi
fi

exit 0


