#!/usr/bin/env bash
set -euo pipefail

# codex-ultimate-hud installer
# One-liner: curl -fsSL https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main/install.sh | bash

HUD_DIR="$HOME/.codex/hud"
REPO="https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main"

echo "==> Installing codex-ultimate-hud..."

# Dependencies
for cmd in tmux codex; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: '$cmd' not found. Please install it first." >&2
        [[ "$cmd" == "tmux" ]] && echo "  brew install tmux  (macOS)" >&2
        [[ "$cmd" == "codex" ]] && echo "  npm install -g @openai/codex  (https://github.com/openai/codex)" >&2
        exit 1
    fi
done

mkdir -p "$HUD_DIR"

echo "==> Downloading HUD files..."
curl -fsSL "$REPO/status.sh"   -o "$HUD_DIR/status.sh"
curl -fsSL "$REPO/tmux.conf"   -o "$HUD_DIR/tmux.conf"
curl -fsSL "$REPO/launch.sh"   -o "$HUD_DIR/launch.sh"

chmod +x "$HUD_DIR/status.sh" "$HUD_DIR/launch.sh"

# Add alias if not exists
SHELL_RC="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.bashrc"

if ! grep -q 'alias cxh=' "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo '# codex-ultimate-hud: one-command launcher' >> "$SHELL_RC"
    echo "alias cxh=\"$HUD_DIR/launch.sh\"" >> "$SHELL_RC"
    echo "==> Added 'cxh' alias to $SHELL_RC"
else
    echo "==> 'cxh' alias already exists in $SHELL_RC"
fi

echo ""
echo "  Done! Restart your shell or run: source $SHELL_RC"
echo ""
echo "  Usage:"
echo "    cxh              # Launch Codex with HUD"
echo "    cxh -m gpt-5.3   # Pass args to codex"
echo ""
echo "  Made by AI-ynggul (AI영끌맨)"
