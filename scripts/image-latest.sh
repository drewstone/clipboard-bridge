#!/usr/bin/env bash
#
# image-latest.sh - Insert path of most recent clipboard image into active tmux pane
#
# Usage: image-latest.sh [image-directory]

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

IMAGE_DIR="${1:-$HOME/.tmux/clipboard/images}"

if [ ! -d "$IMAGE_DIR" ]; then
    tcb_display_message "tcb: no image directory at $IMAGE_DIR"
    exit 1
fi

latest="$(find "$IMAGE_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \
       -o -iname '*.tiff' -o -iname '*.svg' \) \
    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"

if [ -z "$latest" ]; then
    tcb_display_message "tcb: no images in $IMAGE_DIR — use 'tcb push' from local machine"
    exit 0
fi

fname="$(basename "$latest")"
tmux send-keys -l "$latest"
tcb_display_message "tcb: inserted $fname"
