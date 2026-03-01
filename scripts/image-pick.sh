#!/usr/bin/env bash
#
# image-pick.sh - fzf-based image file picker for tmux-clipboard-bridge
#
# Lists images in the clipboard directory sorted by date (newest first),
# lets the user pick one, and types the path into the active tmux pane.
#
# Usage: image-pick.sh [image-directory]

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

IMAGE_DIR="${1:-$HOME/.tmux/clipboard/images}"

if ! command -v fzf >/dev/null 2>&1; then
    tcb_display_message "tcb: fzf not installed — run: sudo apt install fzf"
    exit 1
fi

if [ ! -d "$IMAGE_DIR" ]; then
    tcb_display_message "tcb: no image directory at $IMAGE_DIR"
    exit 1
fi

# List images sorted newest-first with modification dates
image_list="$(find "$IMAGE_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \
       -o -iname '*.tiff' -o -iname '*.svg' \) \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)"

if [ -z "$image_list" ]; then
    tcb_display_message "tcb: no images in $IMAGE_DIR — use 'tcb push' from local machine"
    exit 0
fi

image_count="$(echo "$image_list" | wc -l)"

# Build display list: "date  |  /full/path"
display_list="$(echo "$image_list" | while IFS= read -r filepath; do
    mod_date="$(stat -c '%y' "$filepath" 2>/dev/null | cut -d. -f1)"
    size="$(stat -c '%s' "$filepath" 2>/dev/null)"
    size_kb="$(( size / 1024 ))KB"
    printf '%s  %s  |  %s\n' "$mod_date" "$size_kb" "$filepath"
done)"

# Run fzf and extract the path from the selected line
selected="$(echo "$display_list" | fzf --height=40% --reverse --no-sort \
    --header="Select image ($image_count available) — ESC to cancel" \
    --delimiter='|' \
    --with-nth=1 | sed 's/.*|  //' | xargs)"

if [ -z "$selected" ]; then
    exit 0
fi

# Type selected path into active pane (literal, no Enter)
tmux send-keys -l "$selected"
