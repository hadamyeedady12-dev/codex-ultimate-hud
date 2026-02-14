#!/usr/bin/env bash
set -uo pipefail
# Codex + HUD: one-command launcher
# Usage: cxh [codex args...]
#
# Set CXH_FULL_AUTO=1 to add --dangerously-bypass-approvals-and-sandbox

CODEX_BIN="${CODEX_BIN:-codex}"
TMUX_CONF="$HOME/.codex/hud/tmux.conf"

# --- Bash version check ---
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "error: bash 4+ required (current: $BASH_VERSION)" >&2
    echo "  brew install bash   (macOS ships bash 3.2)" >&2
    exit 1
fi

# --- Session name: directory + path hash to avoid collision ---
DIR_NAME=$(basename "$PWD")
PATH_HASH=$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-6)
CODER_SESSION_BASE="codex-hud-${DIR_NAME}-${PATH_HASH}"
SESSION="${OMX_SESSION:-$CODER_SESSION_BASE}"
SESSION="${SESSION//[^a-zA-Z0-9._-]/-}"
SESSION="${SESSION//--/-}"
SESSION="${SESSION:-codex-hud-session}"

# --- Dependency check ---
if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "error: $CODEX_BIN not found in PATH" >&2
    exit 1
fi

# --- Build codex command ---
CODEX_ARGS=()
if [[ "${CXH_FULL_AUTO:-0}" == "1" ]]; then
    CODEX_ARGS+=("--dangerously-bypass-approvals-and-sandbox")
fi
CODEX_ARGS+=("$@")

CODEX_CMD=("$CODEX_BIN" "${CODEX_ARGS[@]}")

if ! command -v tmux &>/dev/null; then
    echo "warning: tmux not found, running codex without HUD" >&2
    exec "${CODEX_CMD[@]}"
fi

printf -v CODEX_CMD_STR '%q ' "${CODEX_CMD[@]}"
CODEX_CMD_STR=${CODEX_CMD_STR% }

# If already inside this tmux session, just run codex
if [[ -n "${TMUX-}" ]] && tmux display-message -p '#S' 2>/dev/null | grep -qx "$SESSION"; then
    exec "${CODEX_CMD[@]}"
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
