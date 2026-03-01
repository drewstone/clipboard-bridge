# tmux-clipboard-bridge

Fix clipboard and image pasting in tmux over SSH. Built for developers who use AI coding agents (Claude Code, Codex, etc.) in remote tmux sessions.

## What it solves

| Problem | Fix |
|---|---|
| Mouse selection vanishes on release | Uses `copy-pipe-no-clear` — highlight persists until you press `q`/`Esc` |
| Text clipboard doesn't sync over SSH | OSC 52 escape sequences with `allow-passthrough` enabled |
| Can't paste images from local machine | Local CLI (`tcb`) pushes clipboard images via SCP + tmux keybindings insert the path |

## Requirements

- tmux 3.3+ (for `allow-passthrough`)
- [TPM](https://github.com/tmux-plugins/tpm) (Tmux Plugin Manager)
- [tmux-yank](https://github.com/tmux-plugins/tmux-yank) (this plugin configures it, not replaces it)
- A terminal that supports OSC 52: Warp, iTerm2, Ghostty, Kitty, Alacritty, Windows Terminal

## Install

### 1. Add to `tmux.conf`

**Important:** Add this plugin **before** tmux-yank in your config:

```tmux
# ... other plugins ...
set -g @plugin 'drewstone/tmux-clipboard-bridge'
set -g @plugin 'tmux-plugins/tmux-yank'
# ... rest of config ...
```

### 2. Install via TPM

Press `prefix + I` to install.

### 3. (Optional) Install local CLI for image support

On your **local macOS machine**:

```bash
# Option A: Direct download
curl -fsSL https://raw.githubusercontent.com/drewstone/tmux-clipboard-bridge/main/local/tcb \
  -o ~/.local/bin/tcb && chmod +x ~/.local/bin/tcb

# Option B: Clone and symlink
git clone https://github.com/drewstone/tmux-clipboard-bridge.git ~/tmux-clipboard-bridge
ln -s ~/tmux-clipboard-bridge/local/tcb ~/.local/bin/tcb
```

## Usage

### Text clipboard (automatic)

Just select text normally — it syncs to your local clipboard via OSC 52:

- **Mouse drag** — select text, release, it's in your clipboard (highlight stays visible)
- **Double-click** — select word
- **Triple-click** — select line
- **Vi copy-mode** — `prefix + [`, select with `v`, yank with `y`

Press `q` or `Esc` to exit copy-mode and clear the highlight.

### Image clipboard (via `tcb` CLI)

From your **local Mac**:

```bash
# Copy/screenshot an image, then:
tcb push user@your-server           # upload image
tcb push user@your-server --type    # upload + type path into tmux pane
```

From your **remote tmux session**:

| Binding | Action |
|---|---|
| `prefix + P` | Insert latest image path into pane |
| `prefix + M-p` | Open fzf picker to choose from uploaded images |

### Typical workflow with Claude Code

1. Screenshot something on your Mac
2. `tcb push drew@server --type`
3. Image path appears in the tmux pane where Claude Code is running
4. Claude Code reads the image file

### `tcb` commands

```
tcb push <user@host> [--type]    Push clipboard image to remote
tcb clean <user@host> [N]        Clean old images, keep last N (default: 50)
tcb setup                        Show SSH ControlMaster setup guide
tcb help                         Show help
```

## Configuration

All options use the `@tcb_` prefix:

```tmux
# Image storage directory (default: ~/.tmux/clipboard/images)
set -g @tcb_image_dir "$HOME/.tmux/clipboard/images"

# Key bindings (default: P and M-p)
set -g @tcb_image_latest_key "P"
set -g @tcb_image_pick_key "M-p"

# Passthrough mode: "on" (default), "all", or "off"
set -g @tcb_passthrough "on"

# Yank action: "copy-pipe-no-clear" (default) or "copy-pipe-and-cancel"
set -g @tcb_yank_action "copy-pipe-no-clear"
```

## How it works

### Text clipboard

1. Plugin enables `allow-passthrough on` in tmux
2. Sets `@override_copy_command` to an OSC 52 script (so tmux-yank works without xclip/xsel on headless servers)
3. Sets `@yank_action` to `copy-pipe-no-clear` (selection persists)
4. When you copy text, it's base64-encoded and sent via OSC 52 through tmux's DCS passthrough to your terminal, which puts it in your system clipboard

### Image clipboard

There's no terminal standard for pasting images over SSH. The `tcb` CLI bridges this gap:

1. Grabs the image from your macOS clipboard (via `pngpaste` or `osascript`)
2. SCPs it to `~/.tmux/clipboard/images/` on the remote server
3. Optionally types the file path into the active tmux pane

## Tips

- **SSH ControlMaster** makes `tcb push` nearly instant after the first connection. Run `tcb setup` for configuration help.
- **Install `pngpaste`** on your Mac (`brew install pngpaste`) for faster clipboard extraction.
- **Set up an alias** for quick access:
  ```bash
  alias tp='tcb push drew@myserver --type'
  ```

## License

MIT
