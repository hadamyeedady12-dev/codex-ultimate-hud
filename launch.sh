#!/usr/bin/env bash
set -uo pipefail
# Codex + HUD: one-command launcher
# Usage: cxh [codex args...]

CODEX_BIN="${CODEX_BIN:-codex}"
TMUX_CONF="$HOME/.codex/hud/tmux.conf"
CODER_SESSION_BASE="codex-hud-$(basename "$PWD")"
SESSION="${OMX_SESSION:-$CODER_SESSION_BASE}"
SESSION="${SESSION//[^a-zA-Z0-9._-]/-}"
SESSION="${SESSION//--/-}"
SESSION="${SESSION:-codex-hud-session}"

# --- Dependency check ---
if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "error: $CODEX_BIN not found in PATH" >&2
    exit 1
fi

if ! command -v tmux &>/dev/null; then
    echo "warning: tmux not found, running codex without HUD" >&2
    exec "$CODEX_BIN" --dangerously-bypass-approvals-and-sandbox "$@"
fi

# Build a safely shell-escaped command for tmux shell execution
CODEX_CMD=("$CODEX_BIN" "--dangerously-bypass-approvals-and-sandbox" "$@")
printf -v CODEX_CMD_STR '%q ' "${CODEX_CMD[@]}"
CODEX_CMD_STR=${CODEX_CMD_STR% }

# If already inside this tmux session, just run codex
if [[ -n "${TMUX-}" ]] && tmux display-message -p '#S' 2>/dev/null | grep -qx "$SESSION"; then
    exec "$CODEX_BIN" --dangerously-bypass-approvals-and-sandbox "$@"
fi

# Reuse existing detached session, or kill stale one
if tmux has-session -t "$SESSION" 2>/dev/null; then
    CLIENTS="$(tmux list-clients -t "$SESSION" 2>/dev/null | awk 'END{print NR}')"
    if [[ "$CLIENTS" == "0" ]]; then
        tmux kill-session -t "$SESSION" 2>/dev/null
    else
        exec tmux attach-session -t "$SESSION"
    fi
fi

# Clear HUD cache so new session starts fresh
rm -f "$HOME/.codex/hud/.cache"

# Launch new session: load HUD config, run codex, print exit code
TMUX_HUD_CMD="tmux source-file '$TMUX_CONF' 2>/dev/null; ${CODEX_CMD_STR}; RC=\$?; echo; echo \"[codex exited (rc=\$RC)]\"; read"
exec tmux new-session -s "$SESSION" -e "TERM=xterm-256color" "$TMUX_HUD_CMD"
