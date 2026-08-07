#!/usr/bin/env bash
# Setup tmux keybind for the LLM session dashboard.
# Adds 'prefix M-l' (Alt-l) binding to open the dashboard in a new tmux window.
#
# Usage:
#   ./scripts/setup-tmux-keybind.sh          # adds to ~/.tmux.conf + live-binds
#   ./scripts/setup-tmux-keybind.sh --remove  # removes the binding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$SCRIPT_DIR/llm-dashboard.py"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
BIND_KEY="${LLM_DASH_KEY:-M-l}"
BIND_LINE="bind $BIND_KEY new-window -n \"llm-dash\" \"python3 $DASHBOARD\""

if [[ "${1:-}" == "--remove" ]]; then
    if grep -qF "llm-dashboard" "$TMUX_CONF" 2>/dev/null; then
        sed -i '/llm-dashboard/d' "$TMUX_CONF"
        tmux unbind -T prefix "$BIND_KEY" 2>/dev/null || true
        echo "✓ Removed LLM dashboard keybind from $TMUX_CONF"
    else
        echo "Nothing to remove — no llm-dashboard binding found in $TMUX_CONF"
    fi
    exit 0
fi

# Check dashboard exists
if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: Dashboard not found at $DASHBOARD" >&2
    exit 1
fi

# Add to tmux.conf if not already present
if grep -qF "llm-dashboard" "$TMUX_CONF" 2>/dev/null; then
    echo "⏭ Keybind already in $TMUX_CONF — skipping"
else
    echo "" >> "$TMUX_CONF"
    echo "# LLM session dashboard (prefix + Alt-l)" >> "$TMUX_CONF"
    echo "$BIND_LINE" >> "$TMUX_CONF"
    echo "✓ Added to $TMUX_CONF: $BIND_LINE"
fi

# Live-bind in current tmux server (no reload needed)
if [[ -n "${TMUX:-}" ]]; then
    tmux bind -T prefix "$BIND_KEY" new-window -n "llm-dash" "python3 $DASHBOARD"
    echo "✓ Live-bound: prefix + $BIND_KEY → llm-dashboard"
    echo ""
    echo "Try it now: press your tmux prefix then Alt-l"
else
    echo ""
    echo "Not inside tmux — run 'tmux source $TMUX_CONF' to activate,"
    echo "or re-run this script from within a tmux session for live binding."
fi
