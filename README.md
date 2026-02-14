# codex-ultimate-hud

> **OpenAI Codex CLI** 전용 실시간 HUD (Head-Up Display)
>
> Claude Code의 [claude-ultimate-hud](https://github.com/anthropics/claude-code)에서 영감받아 제작

Made by **AI영끌맨** | [@AI-ynggul](https://github.com/AI-ynggul)

---

## Preview

```
🤖 gpt-5.3-codex-spark xhigh │ █████░░░░░ 75K/128K 58% │ 90K tok │ main │ 33m │ e21 p5 c3
```

| Segment | Description |
|---------|-------------|
| `🤖 model reasoning` | Current model & reasoning effort |
| `█████░░░░░ 75K/128K 58%` | Context window usage (bar + used/total + %) |
| `90K tok` | Total tokens consumed this session |
| `main` | Current git branch |
| `33m` | Session elapsed time |
| `e21 p5 c3` | Tool calls: **e**xec, **p**atch, **s**hell, **m**cp, **c**ompact |

Color-coded context bar:
- **Green** < 50% — plenty of room
- **Yellow** 50-80% — getting full
- **Red** > 80% — near limit, expect auto-compact

---

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/hadamyeedady12-dev/codex-ultimate-hud/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/hadamyeedady12-dev/codex-ultimate-hud.git
cd codex-ultimate-hud
mkdir -p ~/.codex/hud
cp status.sh tmux.conf launch.sh ~/.codex/hud/
chmod +x ~/.codex/hud/status.sh ~/.codex/hud/launch.sh
echo 'alias cxh="~/.codex/hud/launch.sh"' >> ~/.zshrc
source ~/.zshrc
```

---

## Usage

```bash
cxh                    # Launch Codex with HUD
cxh -m gpt-5.3        # Pass any codex args
cxh -q "fix the bug"  # Start with a prompt
```

The HUD appears as a tmux status bar at the bottom. It refreshes every 5 seconds by parsing Codex's log file.

---

## Requirements

- **macOS** or **Linux**
- [OpenAI Codex CLI](https://github.com/openai/codex) installed
- [tmux](https://github.com/tmux/tmux) (`brew install tmux`)
- bash 4+

---

## How it works

```
┌─────────────────────────────────────────────┐
│  Codex TUI (full screen)                    │
│                                             │
│                                             │
├─────────────────────────────────────────────┤
│ 🤖 model │ ████░░ 75K/128K │ 90K tok │ ... │  ← tmux status bar
└─────────────────────────────────────────────┘
```

- `launch.sh` — Wraps Codex in a tmux session with HUD config
- `status.sh` — Parses `~/.codex/log/codex-tui.log` for live metrics
- `tmux.conf` — Styles the status bar with 256-color formatting
- Uses **mtime-based caching** to avoid re-parsing unchanged logs
- macOS `nawk` compatible (no gawk required)

---

## Customization

Edit `~/.codex/hud/status.sh`:

```bash
MAX_MODEL=22    # Max chars for model name
MAX_BRANCH=16   # Max chars for branch name
```

Edit `~/.codex/hud/tmux.conf`:

```bash
set -g status-interval 5    # Refresh rate (seconds)
set -g status-position bottom  # or 'top'
```

---

## License

MIT

---

> *"AI 도구는 끝까지 영끌해야 제맛"* — AI영끌맨
