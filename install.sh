#!/usr/bin/env bash
set -euo pipefail

# codex-ultimate-hud installer
# One-liner: curl -fsSL https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main/install.sh | bash

HUD_DIR="$HOME/.codex/hud"
REPO="https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main"

echo "==> Installing codex-ultimate-hud..."
echo ""

# --- Bash version check ---
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "error: bash 4+ required (current: $BASH_VERSION)" >&2
    echo "  brew install bash   (macOS ships bash 3.2)" >&2
    exit 1
fi

# --- Dependency check ---
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

# --- Checksum verification ---
EXPECTED_SUMS_URL="$REPO/sha256sums.txt"
if curl -fsSL "$EXPECTED_SUMS_URL" -o /tmp/codex-hud-sums.txt 2>/dev/null; then
    echo "==> Verifying file integrity..."
    FAIL=false
    while IFS='  ' read -r expected_sum fname; do
        actual_sum=$(shasum -a 256 "$HUD_DIR/$fname" 2>/dev/null | awk '{print $1}')
        if [[ "$actual_sum" != "$expected_sum" ]]; then
            echo "error: checksum mismatch for $fname" >&2
            FAIL=true
        fi
    done < /tmp/codex-hud-sums.txt
    rm -f /tmp/codex-hud-sums.txt
    if $FAIL; then
        echo "error: integrity check failed. Files may have been tampered with." >&2
        rm -f "$HUD_DIR/status.sh" "$HUD_DIR/tmux.conf" "$HUD_DIR/launch.sh"
        exit 1
    fi
    echo "    checksums OK"
else
    echo "warning: could not fetch checksums, skipping verification" >&2
fi

chmod +x "$HUD_DIR/status.sh" "$HUD_DIR/launch.sh"

# --- Add alias (exact match only) ---
SHELL_RC="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.bashrc"

if grep -qx 'alias cxh=.*' "$SHELL_RC" 2>/dev/null; then
    echo "==> 'cxh' alias already exists in $SHELL_RC (not modified)"
else
    echo "" >> "$SHELL_RC"
    echo '# codex-ultimate-hud: one-command launcher' >> "$SHELL_RC"
    echo "alias cxh=\"$HUD_DIR/launch.sh\"" >> "$SHELL_RC"
    echo "==> Added 'cxh' alias to $SHELL_RC"
fi

echo ""
echo "  Done! Restart your shell or run: source $SHELL_RC"
echo ""
echo "  Usage:"
echo "    cxh                # Launch Codex with HUD"
echo "    cxh -m gpt-5.3    # Pass any codex args"
echo "    CXH_FULL_AUTO=1 cxh   # Enable --dangerously-bypass-approvals-and-sandbox"
echo ""
echo "  Made by AI영끌맨"
