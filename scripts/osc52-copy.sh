#!/usr/bin/env bash
#
# osc52-copy.sh - Copy stdin to system clipboard via OSC 52 escape sequence
#
# When running inside tmux with allow-passthrough=on, wraps the OSC 52
# sequence in DCS passthrough so it reaches the outer terminal emulator.
#
# Used as @override_copy_command for tmux-yank and as the pipe target
# for MouseDragEnd1Pane bindings.
#
# OSC 52 format:     ESC ] 52 ; c ; <base64> BEL
# DCS passthrough:   ESC P tmux ; ESC <inner-sequence> ESC \

set -euo pipefail

buf="$(cat)"

if [ -z "$buf" ]; then
    exit 0
fi

# Base64 encode without line wrapping.
# GNU base64 needs -w0; BSD base64 doesn't wrap by default.
if base64 -w0 </dev/null 2>/dev/null; then
    b64="$(printf '%s' "$buf" | base64 -w0)"
else
    b64="$(printf '%s' "$buf" | base64 | tr -d '\n')"
fi

# Warn on large payloads (most terminals cap at ~100KB base64)
max_bytes=74994
if [ "${#b64}" -gt "$max_bytes" ]; then
    if [ -n "${TMUX:-}" ]; then
        tmux display-message \
            "tcb: clipboard data large (${#b64}B base64), may be truncated by terminal"
    fi
fi

# Determine output target - write to pane tty so tmux can forward via passthrough
if [ -n "${TMUX:-}" ]; then
    pane_tty="$(tmux display-message -p '#{pane_tty}' 2>/dev/null || true)"
    if [ -z "$pane_tty" ] || [ ! -w "$pane_tty" ]; then
        pane_tty="/dev/tty"
    fi
else
    pane_tty="/dev/tty"
fi

# Emit OSC 52 - "c" = clipboard selection
if [ -n "${TMUX:-}" ]; then
    # Inside tmux: wrap in DCS passthrough (double the inner ESC)
    printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$b64" > "$pane_tty"
else
    # Outside tmux: emit directly
    printf '\033]52;c;%s\a' "$b64" > "$pane_tty"
fi
