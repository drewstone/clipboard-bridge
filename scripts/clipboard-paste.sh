#!/usr/bin/env bash
#
# clipboard-paste.sh — Smart clipboard paste via SSH reverse tunnel
#
# Connects to tcb-server on the local machine (via reverse tunnel),
# fetches clipboard content (text or image), and pastes accordingly:
#   - Text: types it into the active tmux pane
#   - Image: saves to clipboard dir, types the file path
#
# Falls back to tmux paste-buffer if the tunnel is unavailable.
#
# Usage: clipboard-paste.sh [port] [image-dir]

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

PORT="${1:-19988}"
IMAGE_DIR="${2:-$HOME/.tmux/clipboard/images}"

mkdir -p "$IMAGE_DIR"

# ── Connect to tcb-server via reverse tunnel ───────────────────────────────
fetch_clipboard() {
    local response=""
    local length=""

    # Connect and read length-prefixed response
    # Use timeout to avoid hanging if tunnel is down
    response="$(echo "" | nc -w 2 localhost "$PORT" 2>/dev/null)" || return 1

    if [ -z "$response" ]; then
        return 1
    fi

    # Response is: <length>\n<json>
    # Extract the JSON part (everything after first newline)
    local json_data
    json_data="$(echo "$response" | tail -n +2)"

    if [ -z "$json_data" ]; then
        # Maybe no length prefix, try whole response as JSON
        json_data="$response"
    fi

    echo "$json_data"
}

# ── Parse JSON without jq (use python3 which is available on most systems) ─
json_get() {
    local json="$1"
    local key="$2"
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('$key',''))" <<< "$json"
}

# ── Main ───────────────────────────────────────────────────────────────────
clipboard_json="$(fetch_clipboard)" || {
    # Tunnel unavailable — fall back to tmux paste buffer
    tmux paste-buffer -p 2>/dev/null || \
        tcb_display_message "tcb: tunnel unavailable. Start tcb-server on your Mac and SSH with -R ${PORT}:localhost:${PORT}"
    exit 0
}

cb_type="$(json_get "$clipboard_json" "type")"

case "$cb_type" in
    text)
        data="$(json_get "$clipboard_json" "data")"
        if [ -n "$data" ]; then
            # Use tmux load-buffer + paste-buffer for proper handling of
            # multiline text, special characters, etc.
            printf '%s' "$data" | tmux load-buffer -
            tmux paste-buffer -p
        else
            tcb_display_message "tcb: clipboard is empty"
        fi
        ;;

    image)
        data="$(json_get "$clipboard_json" "data")"
        if [ -z "$data" ]; then
            tcb_display_message "tcb: failed to read clipboard image"
            exit 1
        fi

        timestamp="$(date '+%Y%m%dT%H%M%S')"
        img_path="${IMAGE_DIR}/${timestamp}.png"

        # Decode base64 image and save
        printf '%s' "$data" | base64 -d > "$img_path" 2>/dev/null

        if [ ! -s "$img_path" ]; then
            rm -f "$img_path"
            tcb_display_message "tcb: failed to decode clipboard image"
            exit 1
        fi

        size_kb="$(( $(stat -c '%s' "$img_path") / 1024 ))"

        # Type the path into the active pane
        tmux send-keys -l "$img_path"
        tcb_display_message "tcb: pasted image (${size_kb}KB) → ${img_path}"

        # Clean old images (keep last 50)
        find "$IMAGE_DIR" -maxdepth 1 -type f -name '*.png' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | tail -n +51 | cut -d' ' -f2- | xargs -r rm -f
        ;;

    error)
        msg="$(json_get "$clipboard_json" "data")"
        tcb_display_message "tcb: server error: $msg"
        ;;

    *)
        tcb_display_message "tcb: unknown clipboard type: $cb_type"
        ;;
esac
