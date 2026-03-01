#!/usr/bin/env bash
#
# clipboard-bridge.tmux - TPM plugin entry point
#
# Fixes clipboard for SSH+tmux workflows:
#   1. Mouse selection persists after release (copy-pipe-no-clear)
#   2. Text clipboard syncs to local machine (OSC 52 via passthrough)
#   3. Image clipboard bridging (via local/tcb helper + key bindings)
#
# IMPORTANT: List this plugin BEFORE tmux-yank in tmux.conf so that
# @override_copy_command and @yank_action are set before tmux-yank reads them.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${CURRENT_DIR}/scripts"

source "${SCRIPTS_DIR}/helpers.sh"

# ── User-configurable options (@tcb_ namespace) ───────────────────────────
TCB_IMAGE_DIR="$(get_tmux_option "@tcb_image_dir" "$HOME/.tmux/clipboard/images")"
TCB_IMAGE_LATEST_KEY="$(get_tmux_option "@tcb_image_latest_key" "P")"
TCB_IMAGE_PICK_KEY="$(get_tmux_option "@tcb_image_pick_key" "M-p")"
TCB_PASSTHROUGH="$(get_tmux_option "@tcb_passthrough" "on")"
TCB_YANK_ACTION="$(get_tmux_option "@tcb_yank_action" "copy-pipe-no-clear")"

# ── 1. Enable allow-passthrough for OSC 52 ────────────────────────────────
if [ "$TCB_PASSTHROUGH" != "off" ]; then
    tmux set-option -g allow-passthrough "$TCB_PASSTHROUGH"
fi

# ── 2. Configure tmux-yank to use our OSC 52 copy command ─────────────────
# tmux-yank checks @override_copy_command first (helpers.sh line 141).
# This makes tmux-yank work on headless servers without xclip/xsel.
tmux set-option -g @override_copy_command "${SCRIPTS_DIR}/osc52-copy.sh"

# ── 3. Set yank action to preserve selection ───────────────────────────────
# copy-pipe-no-clear copies + pipes but keeps the selection highlighted.
tmux set-option -g @yank_action "$TCB_YANK_ACTION"

# ── 4. Override mouse drag to preserve selection ───────────────────────────
# Default copy-pipe-and-cancel exits copy-mode immediately (highlight vanishes).
tmux bind-key -T copy-mode-vi MouseDragEnd1Pane \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"
tmux bind-key -T copy-mode MouseDragEnd1Pane \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"

# Double-click: select word
tmux bind-key -T copy-mode-vi DoubleClick1Pane \
    select-pane \; \
    send-keys -X select-word \; \
    run-shell -d 0.3 "" \; \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"
tmux bind-key -T copy-mode DoubleClick1Pane \
    select-pane \; \
    send-keys -X select-word \; \
    run-shell -d 0.3 "" \; \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"

# Triple-click: select line
tmux bind-key -T copy-mode-vi TripleClick1Pane \
    select-pane \; \
    send-keys -X select-line \; \
    run-shell -d 0.3 "" \; \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"
tmux bind-key -T copy-mode TripleClick1Pane \
    select-pane \; \
    send-keys -X select-line \; \
    run-shell -d 0.3 "" \; \
    send-keys -X "$TCB_YANK_ACTION" "${SCRIPTS_DIR}/osc52-copy.sh"

# ── 5. Create image clipboard directory ────────────────────────────────────
mkdir -p "$TCB_IMAGE_DIR"

# ── 6. Key bindings for image insertion ────────────────────────────────────
# prefix + P: insert latest image path into active pane
tmux bind-key "$TCB_IMAGE_LATEST_KEY" \
    run-shell "${SCRIPTS_DIR}/image-latest.sh '${TCB_IMAGE_DIR}'"

# prefix + M-p: fzf picker for clipboard images
tmux bind-key "$TCB_IMAGE_PICK_KEY" \
    run-shell -b "${SCRIPTS_DIR}/image-pick.sh '${TCB_IMAGE_DIR}'"
