#!/bin/bash
set -uo pipefail

# Codex HUD Status Bar Generator for tmux
# Called by tmux every status-interval seconds

CONFIG="$HOME/.codex/config.toml"
LOG="$HOME/.codex/log/codex-tui.log"
CACHE="$HOME/.codex/hud/.cache"
SESS_DIR="$HOME/.codex/sessions"

# Segment budget
MAX_MODEL=22
MAX_BRANCH=16

# --- Dependency fallbacks ---
_git()  { command -v git  >/dev/null 2>&1 && git "$@" 2>/dev/null || echo "?"; }
_date() { command -v date >/dev/null 2>&1 && date "$@" 2>/dev/null || echo "0"; }
_stat() { command -v stat >/dev/null 2>&1 && stat "$@" 2>/dev/null || echo "0"; }

_log_mtime() {
    local file="$1"
    local mtime
    mtime=$(_stat -c %Y "$file")
    if [[ -z "${mtime:-}" || "$mtime" == "0" ]]; then
        mtime=$(_stat -f %m "$file")
    fi
    printf '%s' "${mtime:-0}"
}

trunc() {
    local s="$1" n="$2"
    [[ ${#s} -gt "$n" ]] && printf '%s~' "${s:0:$((n-1))}" || printf '%s' "$s"
}

tmux_safe() {
    local s="${1-}"
    s=${s//\\/\\\\}
    s=${s//#/##}
    s=${s//%/%%}
    s=${s//,/\\,}
    s=${s//!/!!}
    printf '%s' "$s"
}

parse_config_value() {
    local key="$1"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            line=$0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            gsub(/^"/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$CONFIG" 2>/dev/null || true
}

MODEL=$(parse_config_value model)
EFFORT=$(parse_config_value model_reasoning_effort)
MODEL=$(trunc "${MODEL:-?}" "$MAX_MODEL")

mkdir -p "$(dirname "$CACHE")"
LOG_MTIME=0
[[ -f "$LOG" ]] && LOG_MTIME=$(_log_mtime "$LOG")

CACHE_HIT=false
CACHED_LINE=""
if [[ -f "$CACHE" ]]; then
    CACHED_MTIME="$(head -n 1 "$CACHE" 2>/dev/null || true)"
    if [[ -n "$CACHED_MTIME" && "$LOG_MTIME" == "$CACHED_MTIME" ]]; then
        CACHED_LINE="$(sed -n '2p' "$CACHE" 2>/dev/null || true)"
        CACHE_HIT=true
    fi
fi

if $CACHE_HIT; then
    IFS='|' read -r TOTAL_TOKENS EST_TOKENS COMPACT_LIMIT EXEC_N PATCH_N SHELL_N MCP_N COMPACT_CNT <<< "${CACHED_LINE:-0|0|244800|0|0|0|0|0}"
else
    TOTAL_TOKENS=0
    EST_TOKENS=0
    COMPACT_LIMIT=244800
    EXEC_N=0
    PATCH_N=0
    SHELL_N=0
    MCP_N=0
    COMPACT_CNT=0

    if [[ -f "$LOG" ]]; then
        # Pre-extract latest thread_id (needed for per-session tool counts)
        LAST_TID=$(tail -n 500 "$LOG" | grep -oE 'thread_id=[0-9a-f-]+' | tail -1 | cut -d= -f2)
        LAST_TID=${LAST_TID:-__none__}

        read -r TOTAL_TOKENS EST_TOKENS COMPACT_LIMIT EXEC_N PATCH_N SHELL_N MCP_N COMPACT_CNT < <(
            tail -n 5000 "$LOG" | awk -v tid="$LAST_TID" '
                /total_usage_tokens=/ {
                    ln = $0
                    if (match(ln, /total_usage_tokens=[0-9]+/))
                        { v = substr(ln, RSTART, RLENGTH); sub(/.*=/, "", v); total = v + 0 }
                    if (match(ln, /estimated_token_count=Some\([0-9]+\)/))
                        { v = substr(ln, RSTART, RLENGTH); gsub(/[^0-9]/, "", v); est = v + 0 }
                    if (match(ln, /auto_compact_limit=[0-9]+/))
                        { v = substr(ln, RSTART, RLENGTH); sub(/.*=/, "", v); cl = v + 0 }
                }
                /ContextCompacted/ { compact_cnt++ }
                $0 ~ tid && /ToolCall:/ {
                    if (/ToolCall:[ ]*exec_command/) e++
                    else if (/ToolCall:[ ]*apply_patch/) p++
                    else if (/ToolCall:[ ]*shell_command/) sh++
                    else if (/ToolCall:[ ]*mcp_/ || /ToolCall:[ ]*omx_/) m++
                }
                END {
                    if (cl <= 0) cl = 244800
                    printf "%d %d %d %d %d %d %d %d",
                        total+0, est+0, cl+0, e+0, p+0, sh+0, m+0, compact_cnt+0
                }
            '
        )
    fi

    printf '%s\n' "$LOG_MTIME" > "$CACHE"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "${TOTAL_TOKENS:-0}" "${EST_TOKENS:-0}" "${COMPACT_LIMIT:-244800}" \
        "${EXEC_N:-0}" "${PATCH_N:-0}" "${SHELL_N:-0}" "${MCP_N:-0}" \
        "${COMPACT_CNT:-0}" >> "$CACHE"
fi

TOTAL_TOKENS=${TOTAL_TOKENS:-0}
EST_TOKENS=${EST_TOKENS:-0}
COMPACT_LIMIT=${COMPACT_LIMIT:-244800}
EXEC_N=${EXEC_N:-0}
PATCH_N=${PATCH_N:-0}
SHELL_N=${SHELL_N:-0}
MCP_N=${MCP_N:-0}
COMPACT_CNT=${COMPACT_CNT:-0}

if (( TOTAL_TOKENS >= 1000000 )); then
    TOKEN_FMT="$(awk -v n="$TOTAL_TOKENS" 'BEGIN{printf "%.1fM", (n / 1000000)}')"
elif (( TOTAL_TOKENS >= 1000 )); then
    TOKEN_FMT="$((TOTAL_TOKENS / 1000))K"
elif (( TOTAL_TOKENS > 0 )); then
    TOKEN_FMT="$TOTAL_TOKENS"
else
    TOKEN_FMT="--"
fi

# Context: format as K or M
_fmt_k() {
    local n=$1
    if (( n >= 1000000 )); then
        awk -v n="$n" 'BEGIN{printf "%.1fM", (n / 1000000)}'
    elif (( n >= 1000 )); then
        echo "$((n / 1000))K"
    elif (( n > 0 )); then
        echo "$n"
    else
        echo "0"
    fi
}
CTX_USED=$(_fmt_k "$EST_TOKENS")
# auto_compact_limit ≈ 90% of actual context window; estimate full window
CTX_WINDOW=$(( COMPACT_LIMIT * 10 / 9 ))
CTX_LIMIT=$(_fmt_k "$CTX_WINDOW")

if (( CTX_WINDOW > 0 )); then
    CTX_PCT=$((EST_TOKENS * 100 / CTX_WINDOW))
else
    CTX_PCT=0
fi
(( CTX_PCT > 100 )) && CTX_PCT=100

if (( CTX_PCT < 50 )); then
    C="green"
elif (( CTX_PCT < 80 )); then
    C="yellow"
else
    C="red"
fi

W=10
F=$((CTX_PCT * W / 100))
(( CTX_PCT > 0 && F == 0 )) && F=1
E=$((W - F))

FILLED=""
EMPTY=""
for ((i=0; i<F; i++)); do FILLED+="█"; done
for ((i=0; i<E; i++)); do EMPTY+="░"; done

BAR="#[fg=colour240]░░░░░░░░░░"
[[ -n "$FILLED" ]] && BAR="#[fg=$C]$FILLED"
[[ -n "$EMPTY" ]] && BAR+="#[fg=colour240]$EMPTY"

BRANCH=$(_git branch --show-current)
BRANCH=$(trunc "${BRANCH:-?}" "$MAX_BRANCH")

DUR="--"
LATEST=$(ls -t "$SESS_DIR"/*/*/*/rollout*.jsonl 2>/dev/null | head -n 1)
if [[ -n "$LATEST" ]]; then
    FNAME=$(basename "$LATEST")
    TS=$(echo "$FNAME" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}')
    if [[ -n "$TS" ]]; then
        TS_DATE=${TS%%T*}
        TS_TIME=${TS#*T}
        TS_TIME=${TS_TIME/-/:}
        TS_TIME=${TS_TIME/-/:}
        DT="${TS_DATE} ${TS_TIME}"
        START=$(_date -j -f "%Y-%m-%d %H:%M:%S" "$DT" +%s 2>/dev/null || true)
        [[ -z "$START" || "$START" == "0" ]] && START=$(_date -d "$DT" +%s 2>/dev/null || true)
    fi
    [[ -z "${START:-}" || "$START" == "0" ]] && START=$(_stat -c %W "$LATEST" 2>/dev/null || true)
    [[ -z "${START:-}" || "$START" == "0" ]] && START=$(_stat -f %B "$LATEST")
    [[ -z "${START:-}" || "$START" == "0" ]] && START=$(_stat -f %m "$LATEST")

    if [[ -n "$START" && "$START" != "0" ]]; then
        NOW=$(_date +%s)
        EL=$((NOW - START))
        if (( EL < 60 )); then
            DUR="<1m"
        elif (( EL < 3600 )); then
            DUR="$((EL/60))m"
        else
            DUR="$((EL/3600))h$((EL%3600/60))m"
        fi
    fi
fi

TOOL_TOTAL=$((EXEC_N + PATCH_N + SHELL_N + MCP_N))
TOOLS=""
if (( TOOL_TOTAL > 0 )); then
    PARTS=()
    (( EXEC_N > 0 ))  && PARTS+=("#[fg=green]e#[fg=colour250]${EXEC_N}")
    (( PATCH_N > 0 )) && PARTS+=("#[fg=green]p#[fg=colour250]${PATCH_N}")
    (( SHELL_N > 0 )) && PARTS+=("#[fg=green]s#[fg=colour250]${SHELL_N}")
    (( MCP_N > 0 ))   && PARTS+=("#[fg=green]m#[fg=colour250]${MCP_N}")
    TOOLS=$(IFS=' '; echo "${PARTS[*]}")
    (( COMPACT_CNT > 0 )) && TOOLS+=" #[fg=yellow]c${COMPACT_CNT}"
fi

SEP="#[fg=colour240] │ #[default]"

echo -n "#[fg=cyan,bold]🤖 $(tmux_safe "$MODEL")#[default]"
[[ -n "$EFFORT" ]] && echo -n " #[fg=colour245]$(tmux_safe "$EFFORT")#[default]"
echo -n "${SEP}${BAR} #[fg=${C}]${CTX_USED}#[fg=colour240]/#[fg=colour245]${CTX_LIMIT} #[fg=${C}]${CTX_PCT}%#[default]"
echo -n "${SEP}#[fg=yellow,bold]${TOKEN_FMT}#[default] #[fg=colour240]tok#[default]"
echo -n "${SEP}#[fg=magenta]$(tmux_safe "$BRANCH")#[default]"
echo -n "${SEP}#[fg=colour245]${DUR}#[default]"
[[ -n "$TOOLS" ]] && echo -n "${SEP}${TOOLS}"
