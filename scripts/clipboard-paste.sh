#!/usr/bin/env bash
#
# clipboard-paste.sh — Smart clipboard paste via SSH reverse tunnel
#
# Connects to tcb-server, fetches clipboard (text or image), pastes.
# Falls back to tmux paste-buffer if tunnel unavailable.
#
# Usage: clipboard-paste.sh [port] [image-dir]

set -euo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

PORT="${1:-19988}"
IMAGE_DIR="${2:-$HOME/.tmux/clipboard/images}"
mkdir -p "$IMAGE_DIR"

# Use Python for reliable TCP read of large payloads (nc truncates)
python3 - "$PORT" "$IMAGE_DIR" <<'PYTHON'
import socket, json, base64, sys, os, time, subprocess

port = int(sys.argv[1])
image_dir = sys.argv[2]

def fetch_clipboard():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    try:
        sock.connect(("127.0.0.1", port))
        sock.sendall(b"\n")
        header = b""
        while b"\n" not in header:
            chunk = sock.recv(1024)
            if not chunk:
                return None
            header += chunk
        length_str, _, rest = header.partition(b"\n")
        expected = int(length_str)
        data = rest
        while len(data) < expected:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
        return json.loads(data[:expected].decode("utf-8"))
    except Exception:
        return None
    finally:
        sock.close()

def tmux_msg(msg, duration=5000):
    try:
        saved = subprocess.run(
            ["tmux", "show-option", "-gqv", "display-time"],
            capture_output=True, text=True
        ).stdout.strip() or "750"
        subprocess.run(["tmux", "set-option", "-gq", "display-time", str(duration)])
        subprocess.run(["tmux", "display-message", msg])
        subprocess.run(["tmux", "set-option", "-gq", "display-time", saved])
    except Exception:
        pass

cb = fetch_clipboard()

if cb is None:
    result = subprocess.run(["tmux", "paste-buffer", "-p"], capture_output=True)
    if result.returncode != 0:
        tmux_msg(f"tcb: tunnel unavailable. Run tcb-server + SSH with RemoteForward {port}")
    sys.exit(0)

cb_type = cb.get("type", "")

if cb_type == "text":
    text = cb.get("data", "")
    if text:
        subprocess.run(["tmux", "load-buffer", "-"], input=text.encode(), capture_output=True)
        subprocess.run(["tmux", "paste-buffer", "-p"])
    else:
        tmux_msg("tcb: clipboard is empty")

elif cb_type == "image":
    img_b64 = cb.get("data", "")
    if not img_b64:
        tmux_msg("tcb: failed to read clipboard image")
        sys.exit(1)

    img_data = base64.b64decode(img_b64)
    timestamp = time.strftime("%Y%m%dT%H%M%S")
    img_path = os.path.join(image_dir, f"{timestamp}.png")

    with open(img_path, "wb") as f:
        f.write(img_data)

    latest = os.path.join(image_dir, "latest.png")
    if os.path.islink(latest) or os.path.exists(latest):
        os.unlink(latest)
    os.symlink(img_path, latest)

    size_kb = len(img_data) // 1024
    subprocess.run(["tmux", "send-keys", "-l", img_path])
    tmux_msg(f"tcb: pasted image ({size_kb}KB) -> {img_path}")

elif cb_type == "error":
    tmux_msg(f"tcb: server error: {cb.get('data', 'unknown')}")
else:
    tmux_msg(f"tcb: unknown clipboard type: {cb_type}")
PYTHON

if [ $? -ne 0 ]; then
    tmux paste-buffer -p 2>/dev/null || \
        tcb_display_message "tcb: paste failed (is tcb-server running?)"
fi
