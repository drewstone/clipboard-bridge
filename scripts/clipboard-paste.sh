#!/usr/bin/env bash
#
# clipboard-paste.sh — Smart clipboard paste via SSH reverse tunnel
#
# Connects to tcb-server, fetches clipboard (text or image), pastes.
# Falls back to tmux paste-buffer if tunnel unavailable.
#
# Usage: clipboard-paste.sh [port] [image-dir] [stack-size]

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

PORT="${1:-19988}"
IMAGE_DIR="${2:-$HOME/.tmux/clipboard/images}"
STACK_SIZE="${3:-20}"
mkdir -p "$IMAGE_DIR"

python3 - "$PORT" "$IMAGE_DIR" "$STACK_SIZE" "${CURRENT_DIR}/update-image-stack.py" <<'PYTHON'
import base64
import json
import os
import socket
import subprocess
import sys
import time

port = int(sys.argv[1])
image_dir = sys.argv[2]
stack_size = int(sys.argv[3])
stack_helper = sys.argv[4]


def fetch_clipboard():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    try:
        sock.connect(('127.0.0.1', port))
        sock.sendall(b'\n')
        header = b''
        while b'\n' not in header:
            chunk = sock.recv(1024)
            if not chunk:
                return None
            header += chunk
        length_str, _, rest = header.partition(b'\n')
        expected = int(length_str)
        data = rest
        while len(data) < expected:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
        return json.loads(data[:expected].decode('utf-8'))
    except Exception:
        return None
    finally:
        sock.close()


def tmux_msg(msg, duration=5000):
    try:
        saved = subprocess.run(
            ['tmux', 'show-option', '-gqv', 'display-time'],
            capture_output=True,
            text=True,
        ).stdout.strip() or '750'
        subprocess.run(['tmux', 'set-option', '-gq', 'display-time', str(duration)])
        subprocess.run(['tmux', 'display-message', msg])
        subprocess.run(['tmux', 'set-option', '-gq', 'display-time', saved])
    except Exception:
        pass


cb = fetch_clipboard()

if cb is None:
    result = subprocess.run(['tmux', 'paste-buffer', '-p'], capture_output=True)
    if result.returncode != 0:
        tmux_msg(f'tcb: tunnel unavailable. Run tcb-server + SSH with RemoteForward {port}')
    sys.exit(0)

cb_type = cb.get('type', '')

if cb_type == 'text':
    text = cb.get('data', '')
    if text:
        subprocess.run(['tmux', 'load-buffer', '-'], input=text.encode(), capture_output=True)
        subprocess.run(['tmux', 'paste-buffer', '-p'])
    else:
        tmux_msg('tcb: clipboard is empty')
elif cb_type == 'image':
    img_b64 = cb.get('data', '')
    if not img_b64:
        tmux_msg('tcb: failed to read clipboard image')
        sys.exit(1)

    img_data = base64.b64decode(img_b64)
    timestamp = time.strftime('%Y%m%dT%H%M%S')
    img_path = os.path.join(image_dir, f'{timestamp}.png')

    with open(img_path, 'wb') as handle:
        handle.write(img_data)

    subprocess.run([stack_helper, image_dir, img_path, str(stack_size)], check=False)

    size_kb = len(img_data) // 1024
    subprocess.run(['tmux', 'send-keys', '-l', img_path])
    tmux_msg(f'tcb: pasted image ({size_kb}KB) -> {img_path}')
elif cb_type == 'error':
    tmux_msg(f"tcb: server error: {cb.get('data', 'unknown')}")
else:
    tmux_msg(f'tcb: unknown clipboard type: {cb_type}')
PYTHON

if [ $? -ne 0 ]; then
    tmux paste-buffer -p 2>/dev/null || \
        tcb_display_message 'tcb: paste failed (is tcb-server running?)'
fi
