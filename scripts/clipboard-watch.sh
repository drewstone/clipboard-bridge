#!/usr/bin/env bash
#
# clipboard-watch.sh — Background clipboard watcher
#
# Polls tcb-server via the reverse tunnel. When the clipboard changes
# to an image, auto-saves it and updates the image stack symlinks.
#
# Usage: clipboard-watch.sh [port] [image-dir] [interval-seconds] [cleanup-age-seconds] [stack-size]

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

PORT="${1:-19988}"
IMAGE_DIR="${2:-$HOME/.tmux/clipboard/images}"
INTERVAL="${3:-3}"
CLEANUP_AGE="${4:-3600}"
STACK_SIZE="${5:-20}"

mkdir -p "$IMAGE_DIR"

echo $$ > "$IMAGE_DIR/.watcher.pid"
trap 'rm -f "$IMAGE_DIR/.watcher.pid"' EXIT

exec python3 - "$PORT" "$IMAGE_DIR" "$INTERVAL" "$CLEANUP_AGE" "$STACK_SIZE" "${CURRENT_DIR}/update-image-stack.py" <<'PYTHON'
import base64
import hashlib
import json
import os
import socket
import subprocess
import sys
import time

port = int(sys.argv[1])
image_dir = sys.argv[2]
interval = int(sys.argv[3])
cleanup_age = int(sys.argv[4])
stack_size = int(sys.argv[5])
stack_helper = sys.argv[6]
last_hash = ''


def fetch_clipboard(port):
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


def tmux_message(msg, duration=3000):
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


while True:
    time.sleep(interval)
    try:
        test_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test_sock.settimeout(1)
        result = test_sock.connect_ex(('127.0.0.1', port))
        test_sock.close()
        if result != 0:
            continue

        cb = fetch_clipboard(port)
        if not cb or cb.get('type') != 'image':
            continue

        snippet = cb.get('data', '')[:200]
        current_hash = hashlib.md5(snippet.encode()).hexdigest()
        if current_hash == last_hash:
            continue
        last_hash = current_hash

        img_data = base64.b64decode(cb['data'])
        if not img_data:
            continue

        timestamp = time.strftime('%Y%m%dT%H%M%S')
        img_path = os.path.join(image_dir, f'{timestamp}.png')
        with open(img_path, 'wb') as handle:
            handle.write(img_data)

        subprocess.run([stack_helper, image_dir, img_path, str(stack_size)], check=False)

        size_kb = len(img_data) // 1024
        tmux_message(f'tcb: image synced ({size_kb}KB) -> {img_path}')

        now = time.time()
        for name in os.listdir(image_dir):
            if name.startswith('.') or name.startswith('latest') or not name.endswith('.png'):
                continue
            path = os.path.join(image_dir, name)
            if path == img_path:
                continue
            try:
                if now - os.path.getmtime(path) > cleanup_age:
                    os.unlink(path)
            except OSError:
                pass
    except Exception:
        continue
PYTHON
