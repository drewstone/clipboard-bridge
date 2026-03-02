#!/usr/bin/env bash
#
# clipboard-watch.sh — Background clipboard watcher
#
# Polls tcb-server via the reverse tunnel. When the clipboard changes
# to an image, auto-saves it and updates a "latest.png" symlink.
#
# Usage: clipboard-watch.sh [port] [image-dir] [interval-seconds]

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"

PORT="${1:-19988}"
IMAGE_DIR="${2:-$HOME/.tmux/clipboard/images}"
INTERVAL="${3:-3}"

mkdir -p "$IMAGE_DIR"

echo $$ > "$IMAGE_DIR/.watcher.pid"
trap 'rm -f "$IMAGE_DIR/.watcher.pid"' EXIT

exec python3 - "$PORT" "$IMAGE_DIR" "$INTERVAL" <<'PYTHON'
import socket, json, base64, sys, os, time, hashlib, subprocess

port = int(sys.argv[1])
image_dir = sys.argv[2]
interval = int(sys.argv[3])
last_hash = ""

def fetch_clipboard(port):
    """Connect to tcb-server and read the full response."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    try:
        sock.connect(("127.0.0.1", port))
        sock.sendall(b"\n")
        # Read length header
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

def tmux_message(msg, duration=3000):
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

while True:
    time.sleep(interval)
    try:
        # Quick port check
        test_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        test_sock.settimeout(1)
        result = test_sock.connect_ex(("127.0.0.1", port))
        test_sock.close()
        if result != 0:
            continue

        cb = fetch_clipboard(port)
        if not cb or cb.get("type") != "image":
            continue

        # Hash first 200 chars of data to detect changes
        snippet = cb.get("data", "")[:200]
        current_hash = hashlib.md5(snippet.encode()).hexdigest()
        if current_hash == last_hash:
            continue
        last_hash = current_hash

        # Decode and save
        img_data = base64.b64decode(cb["data"])
        if not img_data:
            continue

        timestamp = time.strftime("%Y%m%dT%H%M%S")
        img_path = os.path.join(image_dir, f"{timestamp}.png")
        with open(img_path, "wb") as f:
            f.write(img_data)

        # Update latest symlink
        latest = os.path.join(image_dir, "latest.png")
        if os.path.islink(latest) or os.path.exists(latest):
            os.unlink(latest)
        os.symlink(img_path, latest)

        size_kb = len(img_data) // 1024
        tmux_message(f"tcb: image synced ({size_kb}KB) -> {latest}")

        # Cleanup old images (keep 50)
        pngs = sorted(
            [os.path.join(image_dir, f) for f in os.listdir(image_dir)
             if f.endswith(".png") and f != "latest.png" and not f.startswith(".")],
            key=os.path.getmtime, reverse=True
        )
        for old in pngs[50:]:
            os.unlink(old)

    except Exception:
        continue
PYTHON
