#!/usr/bin/env bash
#
# osc52-copy.sh - Copy stdin to system clipboard via OSC 52 escape sequence
#
# When running inside tmux, writes the OSC 52 sequence to the attached client
# tty. Writing to the pane tty sends bytes to the foreground application.
#
# Used as @override_copy_command for tmux-yank and as the pipe target
# for MouseDragEnd1Pane bindings.
#
# OSC 52 format:     ESC ] 52 ; c ; <base64> BEL

set -euo pipefail

buf="$(cat)"

if [ -z "$buf" ]; then
    exit 0
fi

if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    # tmux can report success even when the outer SSH client or terminal
    # ignores the clipboard write, so still emit the OSC 52 fallback below.
    printf '%s' "$buf" | tmux load-buffer -w - 2>/dev/null || true
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

# Determine output target. copy-pipe runs outside the pane, so the escape
# sequence must go to the attached terminal client.
target_tty=""
if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    target_tty="$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)"
    if [ -z "$target_tty" ] || [ ! -w "$target_tty" ]; then
        target_tty="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n 1 || true)"
    fi
else
    target_tty="/dev/tty"
fi

if [ -n "$target_tty" ] && [ -w "$target_tty" ]; then
    # Emit OSC 52 - "c" = clipboard selection
    printf '\033]52;c;%s\a' "$b64" > "$target_tty"
fi
