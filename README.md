# clipboard-bridge

Fix clipboard (text + images) in SSH and tmux sessions. Ctrl+V that actually works over SSH.

Built for developers who use AI coding agents (Claude Code, Codex, etc.) on remote servers.

## The problem

When you SSH into a remote server:
- **Ctrl+V with text** works (terminal sends text bytes through SSH)
- **Ctrl+V with an image** does nothing (terminals can't send image bytes through SSH)
- **In tmux**, even text clipboard breaks without OSC 52 passthrough

## The solution

Two components working together:

1. **`tcb-server`** runs on your Mac — serves your clipboard (text + images) over a local port
2. **SSH reverse tunnel** connects that port back to the remote server
3. **tmux plugin** — `Ctrl+V` / `prefix+v` fetches clipboard through the tunnel

```
┌─ Your Mac ─────────────────────┐     ┌─ Remote Server ──────────────┐
│                                │     │                              │
│  tcb-server (:19988)           │◄────│  SSH reverse tunnel          │
│    clipboard has text? → send  │     │    ↓                         │
│    clipboard has image? → send │     │  Ctrl+V / prefix+v:          │
│                                │     │    text → paste into pane    │
│                                │     │    image → save file, type   │
│                                │     │           path into pane     │
└────────────────────────────────┘     └──────────────────────────────┘
```

## Quick start

### 1. Install on your Mac

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb \
  -o ~/.local/bin/tcb && chmod +x ~/.local/bin/tcb
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb-server \
  -o ~/.local/bin/tcb-server && chmod +x ~/.local/bin/tcb-server
```

### 2. SSH with clipboard bridge

```bash
# One command — starts server + SSH with reverse tunnel:
tcb ssh user@your-server
```

### 3. Install tmux plugin on the remote (optional, for tmux features)

Add to your remote `~/.tmux.conf` **before** tmux-yank:

```tmux
set -g @plugin 'drewstone/clipboard-bridge'
set -g @plugin 'tmux-plugins/tmux-yank'
```

Press `prefix + I` to install.

### 4. Use it

- **`Ctrl+V`** — pastes text or image from your Mac clipboard (auto-detects)
- **`prefix + v`** — same thing, if you prefer a prefixed binding
- **`prefix + P`** — insert latest image path
- **`prefix + M-p`** — fzf picker for all uploaded images
- Mouse selection — highlight persists (doesn't vanish on release)

## How it works

### Text clipboard

Two mechanisms for maximum compatibility:

1. **OSC 52** — tmux sends clipboard data via escape sequences through SSH to your terminal (handles mouse selection and `y` yank automatically)
2. **Reverse tunnel** — `Ctrl+V` fetches text from your Mac's clipboard through the tunnel and pastes it

### Image clipboard

1. You copy/screenshot an image on your Mac
2. Press `Ctrl+V` (or `prefix+v`) in the remote tmux session
3. The plugin connects to `tcb-server` via the reverse tunnel
4. Server extracts the image from your Mac clipboard, sends it as base64
5. Remote script decodes it, saves to `~/.tmux/clipboard/images/`, types the path

For Claude Code / Codex: the image path gets typed into the pane, and the AI agent can read the file.

## Commands

### Local (on your Mac)

```
tcb server [--port N]            Start clipboard server (default: 19988)
tcb ssh <user@host> [--port N]   SSH with reverse tunnel (auto-starts server)
tcb push <user@host> [--type]    One-shot: push clipboard image via SCP
tcb clean <user@host> [N]        Remove old images, keep last N (default: 50)
tcb setup                        Show full setup guide
```

### Remote (tmux bindings)

| Binding | Action |
|---|---|
| `Ctrl+V` | Smart paste — text or image from Mac clipboard |
| `prefix + v` | Same as Ctrl+V (prefixed version) |
| `prefix + P` | Insert latest image path |
| `prefix + M-p` | fzf picker for uploaded images |
| Mouse drag | Select + copy (highlight persists) |
| Double-click | Select word |
| Triple-click | Select line |

## Configuration

```tmux
# Tmux options (all optional, showing defaults)
set -g @tcb_server_port "19988"                   # Reverse tunnel port
set -g @tcb_paste_key "v"                         # prefix + ? for smart paste
set -g @tcb_image_latest_key "P"                  # prefix + ? for latest image
set -g @tcb_image_pick_key "M-p"                  # prefix + ? for fzf picker
set -g @tcb_ctrl_v "on"                           # Bind bare Ctrl+V (off to disable)
set -g @tcb_passthrough "on"                      # OSC 52 passthrough mode
set -g @tcb_yank_action "copy-pipe-no-clear"      # Selection persistence
set -g @tcb_image_dir "$HOME/.tmux/clipboard/images"
```

## Requirements

- **Remote:** tmux 3.3+ (for `allow-passthrough`), Python 3 (for JSON parsing)
- **Local (Mac):** Python 3, `osascript` (built-in), optionally `pngpaste` (`brew install pngpaste`)
- **Terminal:** Any terminal supporting OSC 52 — Warp, iTerm2, Ghostty, Kitty, Alacritty

## Advanced setup

### Auto-start server on Mac login

Run `tcb setup` for LaunchAgent instructions.

### SSH config with permanent tunnel

Add to `~/.ssh/config` on your Mac:

```
Host myserver
    HostName your-server.example.com
    User your-username
    RemoteForward 19988 localhost:19988
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600
```

Then just `ssh myserver` — the tunnel is always there. Run `tcb server` once and forget about it.

### Ctrl+V and vim

The `Ctrl+V` binding detects vim/nvim/vi and passes through. To disable bare Ctrl+V:

```tmux
set -g @tcb_ctrl_v "off"
```

## License

MIT
