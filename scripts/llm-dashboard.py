#!/usr/bin/env python3
"""LLM Session Dashboard — watches ~/.local/share/vim-llm-assistant/logs/ for .status files.

Displays a live-updating curses TUI showing all active and recent LLM sessions,
their status, model, elapsed time, tmux window, and prompt.

Usage:
    python3 llm-dashboard.py [--days N] [--stale-threshold MINUTES]

Keys:
    q/Q  - Quit
    r    - Force refresh
    d    - Cycle days shown (today, +yesterday, +2 days ago, ...)
    s    - Toggle stale session visibility
"""

import argparse
import curses
import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

LOG_DIR = Path(os.environ.get("LLM_LOG_DIR",
    os.path.expanduser("~/.local/share/vim-llm-assistant/logs")))
REFRESH_INTERVAL = 1.0  # seconds
DEFAULT_STALE_THRESHOLD = 30  # minutes
DEFAULT_DAYS = 2  # today + yesterday


def parse_args():
    parser = argparse.ArgumentParser(description="LLM Session Dashboard")
    parser.add_argument("--days", type=int, default=DEFAULT_DAYS,
                        help=f"Number of days to scan (default: {DEFAULT_DAYS})")
    parser.add_argument("--stale-threshold", type=int, default=DEFAULT_STALE_THRESHOLD,
                        help=f"Minutes before a running session is marked stale (default: {DEFAULT_STALE_THRESHOLD})")
    return parser.parse_args()


def get_date_prefixes(days: int) -> list[str]:
    """Get YYYYMMDD prefixes for the last N days."""
    prefixes = []
    for i in range(days):
        dt = datetime.now() - timedelta(days=i)
        prefixes.append(dt.strftime("%Y%m%d"))
    return prefixes


def scan_sessions(log_dir: Path, date_prefixes: list[str], stale_threshold_min: int) -> list[dict]:
    """Find all .status files, return parsed session info sorted by recency."""
    sessions = []
    if not log_dir.exists():
        return sessions

    for entry in sorted(log_dir.iterdir(), reverse=True):
        if not entry.is_dir():
            continue
        # Only check directories matching our date prefixes
        matches_date = any(entry.name.startswith(prefix) for prefix in date_prefixes)
        if not matches_date:
            # Optimization: if we've passed all our target dates, stop
            if sessions and entry.name < min(date_prefixes):
                break
            continue

        status_file = entry / ".status"
        if status_file.exists():
            try:
                data = json.loads(status_file.read_text())
                data["dir_name"] = entry.name
                data["dir_path"] = str(entry)

                # Compute elapsed time
                if "started_at" in data:
                    try:
                        started = datetime.strptime(data["started_at"], "%Y-%m-%d %H:%M:%S")
                        elapsed = (datetime.now() - started).total_seconds()
                        data["elapsed_s"] = int(elapsed)

                        # Mark stale if running too long
                        if data.get("state") == "running" and elapsed > stale_threshold_min * 60:
                            data["state"] = "stale"
                    except ValueError:
                        data["elapsed_s"] = 0

                # If done, compute duration from started_at to completed_at
                if data.get("state") == "done" and "completed_at" in data and "started_at" in data:
                    try:
                        started = datetime.strptime(data["started_at"], "%Y-%m-%d %H:%M:%S")
                        completed = datetime.strptime(data["completed_at"], "%Y-%m-%d %H:%M:%S")
                        data["duration_s"] = int((completed - started).total_seconds())
                    except ValueError:
                        pass

                # Scrape response size if done
                resp_file = entry / "response.md"
                if resp_file.exists():
                    try:
                        stat = resp_file.stat()
                        data["response_bytes"] = stat.st_size
                        data["response_lines"] = sum(1 for _ in open(resp_file))
                    except OSError:
                        pass

                # Scrape input.json for cwd (project context)
                input_file = entry / "input.json"
                if input_file.exists():
                    try:
                        inp = json.loads(input_file.read_text())
                        data["cwd"] = inp.get("cwd", "")
                        # Extract project name from cwd
                        if data["cwd"]:
                            data["project"] = os.path.basename(data["cwd"])
                    except (json.JSONDecodeError, OSError):
                        pass

                sessions.append(data)
            except (json.JSONDecodeError, OSError):
                continue

    return sessions


def format_elapsed(seconds: int) -> str:
    """Format seconds into a human-readable duration string."""
    if seconds < 0:
        return "?"
    elif seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        return f"{seconds // 60}m{seconds % 60:02d}s"
    else:
        return f"{seconds // 3600}h{(seconds % 3600) // 60:02d}m"


def format_bytes(nbytes: int) -> str:
    """Format byte count into human-readable size."""
    if nbytes < 1024:
        return f"{nbytes}B"
    elif nbytes < 1024 * 1024:
        return f"{nbytes / 1024:.1f}K"
    else:
        return f"{nbytes / (1024 * 1024):.1f}M"


def truncate(s: str, max_len: int) -> str:
    """Truncate string with ellipsis."""
    if len(s) <= max_len:
        return s
    return s[:max_len - 1] + "…"


def draw_dashboard(stdscr, sessions: list[dict], show_stale: bool, days: int, stale_threshold: int):
    """Render the dashboard to the curses screen."""
    stdscr.erase()
    h, w = stdscr.getmaxyx()

    running = [s for s in sessions if s.get("state") == "running"]
    stale = [s for s in sessions if s.get("state") == "stale"]
    done = [s for s in sessions if s.get("state") == "done"]

    # Filter out stale if hidden
    display_sessions = sessions if show_stale else [s for s in sessions if s.get("state") != "stale"]

    # Header bar
    header = (f" LLM Dashboard | ⟳ {len(running)} running"
              f"{f' | ⚠ {len(stale)} stale' if stale else ''}"
              f" | ✓ {len(done)} done"
              f" | {days}d | {datetime.now().strftime('%H:%M:%S')} ")
    try:
        stdscr.attron(curses.A_REVERSE | curses.A_BOLD)
        stdscr.addstr(0, 0, header.center(w)[:w-1])
        stdscr.attroff(curses.A_REVERSE | curses.A_BOLD)
    except curses.error:
        pass

    # Column headers
    # Adaptive columns based on terminal width
    if w >= 120:
        col_fmt = f"{'ST':<6} {'MODEL':<30} {'TIME':<8} {'WINDOW':<10} {'PROJECT':<15} {'SIZE':<6} {'PROMPT'}"
    elif w >= 90:
        col_fmt = f"{'ST':<6} {'MODEL':<25} {'TIME':<8} {'WINDOW':<10} {'PROMPT'}"
    else:
        col_fmt = f"{'ST':<6} {'MODEL':<20} {'TIME':<7} {'PROMPT'}"

    try:
        stdscr.attron(curses.A_BOLD | curses.A_UNDERLINE)
        stdscr.addstr(2, 0, col_fmt[:w-1])
        stdscr.attroff(curses.A_BOLD | curses.A_UNDERLINE)
    except curses.error:
        pass

    # Sessions
    row = 3
    for sess in display_sessions:
        if row >= h - 2:
            break

        state = sess.get("state", "?")
        model = sess.get("model", "?")
        # Shorten model name: strip common prefixes
        model_short = model.replace("bifrost-claude:", "").replace("bifrost-", "")
        prompt = sess.get("prompt", "")
        window = sess.get("tmux_window", "")
        project = sess.get("project", "")
        response_bytes = sess.get("response_bytes", 0)

        # Determine elapsed/duration display
        if state == "done" and "duration_s" in sess:
            time_str = format_elapsed(sess["duration_s"])
        else:
            time_str = format_elapsed(sess.get("elapsed_s", 0))

        # Color and icon by state
        if state == "running":
            color = curses.color_pair(1)  # green
            icon = "⟳"
        elif state == "done":
            color = curses.color_pair(2)  # cyan
            icon = "✓"
        elif state == "stale":
            color = curses.color_pair(3) | curses.A_DIM  # yellow dim
            icon = "⚠"
        else:
            color = curses.color_pair(4)  # red
            icon = "?"

        # Build line based on width
        if w >= 120:
            line = (f"{icon} {state[:4]:<4} "
                    f"{truncate(model_short, 29):<30} "
                    f"{time_str:<8} "
                    f"{truncate(window, 9):<10} "
                    f"{truncate(project, 14):<15} "
                    f"{format_bytes(response_bytes) if response_bytes else '':<6} "
                    f"{prompt}")
        elif w >= 90:
            line = (f"{icon} {state[:4]:<4} "
                    f"{truncate(model_short, 24):<25} "
                    f"{time_str:<8} "
                    f"{truncate(window, 9):<10} "
                    f"{prompt}")
        else:
            line = (f"{icon} {state[:4]:<4} "
                    f"{truncate(model_short, 19):<20} "
                    f"{time_str:<7} "
                    f"{prompt}")

        try:
            stdscr.addstr(row, 0, line[:w-1], color)
        except curses.error:
            pass
        row += 1

    # Empty state
    if not display_sessions:
        msg = "No sessions found. Start an LLM request in vim!"
        try:
            stdscr.addstr(h // 2, max(0, (w - len(msg)) // 2), msg, curses.A_DIM)
        except curses.error:
            pass

    # Footer
    if running:
        longest = max(s.get("elapsed_s", 0) for s in running)
        footer = f" {len(running)} active | longest: {format_elapsed(longest)} | q:quit d:days s:stale r:refresh "
    else:
        footer = f" No active sessions | {len(display_sessions)} total | q:quit d:days s:stale r:refresh "

    try:
        stdscr.attron(curses.A_REVERSE)
        stdscr.addstr(h - 1, 0, footer.ljust(w)[:w-1])
        stdscr.attroff(curses.A_REVERSE)
    except curses.error:
        pass

    stdscr.refresh()


def main(stdscr):
    args = parse_args()
    days = args.days
    stale_threshold = args.stale_threshold
    show_stale = True

    curses.curs_set(0)
    stdscr.timeout(int(REFRESH_INTERVAL * 1000))

    # Init colors
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)   # running
    curses.init_pair(2, curses.COLOR_CYAN, -1)    # done
    curses.init_pair(3, curses.COLOR_YELLOW, -1)  # stale
    curses.init_pair(4, curses.COLOR_RED, -1)     # error/unknown

    while True:
        date_prefixes = get_date_prefixes(days)
        sessions = scan_sessions(LOG_DIR, date_prefixes, stale_threshold)
        draw_dashboard(stdscr, sessions, show_stale, days, stale_threshold)

        key = stdscr.getch()
        if key == ord('q') or key == ord('Q'):
            break
        elif key == ord('r') or key == ord('R'):
            stdscr.clear()
        elif key == ord('d') or key == ord('D'):
            # Cycle days: 1 -> 2 -> 3 -> 7 -> 1
            day_cycle = [1, 2, 3, 7]
            try:
                idx = day_cycle.index(days)
                days = day_cycle[(idx + 1) % len(day_cycle)]
            except ValueError:
                days = 2
            stdscr.clear()
        elif key == ord('s') or key == ord('S'):
            show_stale = not show_stale
            stdscr.clear()
        elif key == curses.KEY_RESIZE:
            stdscr.clear()


if __name__ == "__main__":
    curses.wrapper(main)
