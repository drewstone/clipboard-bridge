#!/usr/bin/env bash
# helpers.sh - Shared helper functions for tmux-clipboard-bridge

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local option_value
    option_value="$(tmux show-option -gqv "$option")"
    if [ -z "$option_value" ]; then
        echo "$default_value"
    else
        echo "$option_value"
    fi
}

# Display a tmux message with a custom duration, restoring the original after.
tcb_display_message() {
    local message="$1"
    local duration="${2:-5000}"
    local saved_display_time
    saved_display_time="$(get_tmux_option "display-time" "750")"
    tmux set-option -gq display-time "$duration"
    tmux display-message "$message"
    tmux set-option -gq display-time "$saved_display_time"
}
