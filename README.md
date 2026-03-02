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

1. **`tcb-server`** runs on your local machine — serves your clipboard (text + images) over a local port
2. **SSH reverse tunnel** connects that port back to the remote server
3. **tmux plugin** — `Ctrl+V` / `prefix+v` fetches clipboard through the tunnel

```
┌─ Local Machine ────────────────┐     ┌─ Remote Server ──────────────┐
│                                │     │                              │
│  tcb-server (:19988)           │◄────│  SSH reverse tunnel          │
│    clipboard has text? → send  │     │    ↓                         │
│    clipboard has image? → send │     │  Ctrl+V / prefix+v:          │
│                                │     │    text → paste into pane    │
│                                │     │    image → save file, type   │
│                                │     │           path into pane     │
└────────────────────────────────┘     └──────────────────────────────┘
```

## Install

<details>
<summary><b>macOS</b> (Warp, iTerm2, Ghostty, Kitty, Alacritty)</summary>

### 1. Download the CLI tools

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb -o ~/.local/bin/tcb && chmod +x ~/.local/bin/tcb
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb-server -o ~/.local/bin/tcb-server && chmod +x ~/.local/bin/tcb-server
```

Make sure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

### 2. One-command setup

```bash
tcb install user@your-server
```

This does three things:
- Adds `RemoteForward 19988 localhost:19988` to your `~/.ssh/config`
- Installs a LaunchAgent so `tcb-server` starts automatically on login
- Starts `tcb-server` immediately

After this, just `ssh user@your-server` normally — the clipboard tunnel is always there.

### 3. Install tmux plugin on the remote server

SSH into your server and add to `~/.tmux.conf` **before** tmux-yank:

```tmux
set -g @plugin 'drewstone/clipboard-bridge'
set -g @plugin 'tmux-plugins/tmux-yank'
```

Then press `prefix + I` to install via TPM.

### Requirements
- Python 3 (pre-installed on macOS)
- `osascript` (built-in) — or `brew install pngpaste` for faster image extraction
- SSH key auth to your server (`ssh-copy-id user@server`)

### Uninstall
```bash
tcb uninstall
```

</details>

<details>
<summary><b>Linux</b> (X11 or Wayland)</summary>

### 1. Download the CLI tools

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb -o ~/.local/bin/tcb && chmod +x ~/.local/bin/tcb
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb-server -o ~/.local/bin/tcb-server && chmod +x ~/.local/bin/tcb-server
```

### 2. Install clipboard dependencies

```bash
# X11
sudo apt install xclip

# Wayland
sudo apt install wl-clipboard
```

### 3. SSH config

Add to `~/.ssh/config`:

```
Host your-server
    HostName your-server.example.com
    User your-username
    RemoteForward 19988 localhost:19988
```

### 4. Auto-start tcb-server with systemd

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/tcb-server.service <<EOF
[Unit]
Description=clipboard-bridge server
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 %h/.local/bin/tcb-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now tcb-server
```

### 5. Install tmux plugin on the remote server

Add to `~/.tmux.conf` **before** tmux-yank:

```tmux
set -g @plugin 'drewstone/clipboard-bridge'
set -g @plugin 'tmux-plugins/tmux-yank'
```

Press `prefix + I` to install.

### Requirements
- Python 3
- `xclip` (X11) or `wl-clipboard` (Wayland)
- SSH key auth

### Note on tcb-server (Linux)

The `tcb-server` clipboard detection currently uses `osascript` (macOS). On Linux, you'll need to modify `tcb-server` to use `xclip` / `wl-paste` instead. A cross-platform version is planned — contributions welcome.

</details>

<details>
<summary><b>Windows</b> (Windows Terminal, WSL)</summary>

### 1. Install in WSL

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb -o ~/.local/bin/tcb && chmod +x ~/.local/bin/tcb
curl -fsSL https://raw.githubusercontent.com/drewstone/clipboard-bridge/main/local/tcb-server -o ~/.local/bin/tcb-server && chmod +x ~/.local/bin/tcb-server
```

### 2. SSH config

Add to `~/.ssh/config` inside WSL:

```
Host your-server
    HostName your-server.example.com
    User your-username
    RemoteForward 19988 localhost:19988
```

### 3. Start tcb-server

```bash
tcb server &
```

Or add to your `.bashrc`:

```bash
# Auto-start tcb-server
if ! nc -z localhost 19988 2>/dev/null; then
    nohup python3 ~/.local/bin/tcb-server > /dev/null 2>&1 &
fi
```

### 4. Install tmux plugin on the remote server

Add to `~/.tmux.conf` **before** tmux-yank:

```tmux
set -g @plugin 'drewstone/clipboard-bridge'
set -g @plugin 'tmux-plugins/tmux-yank'
```

Press `prefix + I` to install.

### Requirements
- WSL 2
- Python 3
- Windows Terminal (supports OSC 52)
- SSH key auth

### Note on tcb-server (Windows/WSL)

The `tcb-server` clipboard detection currently uses `osascript` (macOS). On WSL, you'll need to modify `tcb-server` to use `powershell.exe Get-Clipboard` or `win32clipboard`. A cross-platform version is planned — contributions welcome.

</details>

## Usage

Once installed, `Ctrl+V` works in remote tmux sessions for both text and images:

- **`Ctrl+V`** — pastes text or image from your local clipboard
- **`prefix + v`** — same thing (prefixed version)
- **`prefix + P`** — insert latest image path
- **`prefix + M-p`** — fzf picker for all uploaded images
- **Mouse drag** — select + copy to local clipboard (highlight persists)
- **Double-click** — select word
- **Triple-click** — select line

### Image workflow with Claude Code / Codex

1. Screenshot something on your local machine
2. Press `Ctrl+V` in the remote tmux pane running Claude Code
3. Image path appears (e.g., `~/.tmux/clipboard/images/20260301T143022.png`)
4. Claude Code reads the image file

## How it works

### Text clipboard

Two mechanisms for maximum compatibility:

1. **OSC 52** — tmux sends clipboard data via escape sequences through SSH to your terminal (handles mouse selection and `y` yank automatically)
2. **Reverse tunnel** — `Ctrl+V` fetches text from your local clipboard through the tunnel and pastes it

### Image clipboard

1. You copy/screenshot an image locally
2. Press `Ctrl+V` (or `prefix+v`) in the remote tmux session
3. The plugin connects to `tcb-server` via the reverse tunnel
4. Server extracts the image from your clipboard, sends it as base64
5. Remote script decodes it, saves to `~/.tmux/clipboard/images/`, types the path

## Commands

### Local CLI (`tcb`)

```
tcb install <user@host>          One-time setup (SSH config + auto-start server)
tcb uninstall                    Remove LaunchAgent / service
tcb server [--port N]            Start clipboard server (default: 19988)
tcb ssh <user@host> [--port N]   SSH with reverse tunnel (auto-starts server)
tcb push <user@host> [--type]    One-shot: push clipboard image via SCP
tcb clean <user@host> [N]        Remove old images, keep last N (default: 50)
tcb setup                        Show full setup guide
```

### Remote (tmux bindings)

| Binding | Action |
|---|---|
| `Ctrl+V` | Smart paste — text or image from local clipboard |
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

### Ctrl+V and vim

The `Ctrl+V` binding detects vim/nvim/vi as the active pane command and passes through automatically. To disable bare Ctrl+V entirely:

```tmux
set -g @tcb_ctrl_v "off"
```

## Requirements

- **Remote:** tmux 3.3+ (for `allow-passthrough`), Python 3 (for JSON parsing)
- **Local:** Python 3, platform clipboard tools (see install sections above)
- **Terminal:** Any terminal supporting OSC 52 — Warp, iTerm2, Ghostty, Kitty, Alacritty, Windows Terminal

## License

MIT
