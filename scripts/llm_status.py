#!/usr/bin/env python3
"""LLM Session Status TUI - Real-time session monitoring.

Uses `rich` library to display:
- Session Info panel (ID, model, prompt, elapsed time)
- Token Usage panel (input/output/total)
- Tool Calls panel (list of tools invoked with timestamps)
- Ralph/Subagent panel (iteration progress, subagent status)
- Timeline panel (chronological event stream)
- Errors panel (warnings and errors)

Usage:
  python3 llm_status.py --log-dir ~/.local/share/vim-llm-assistant/logs --follow
  python3 llm_status.py --session-id 20260331_151642-1 --follow
"""
import argparse
import glob
import json
import os
import time
from pathlib import Path

from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


def find_latest_session(log_dir: Path) -> str | None:
    """Find the most recent session JSONL file."""
    files = sorted(log_dir.glob('*_session.jsonl'), key=os.path.getmtime, reverse=True)
    if not files:
        return None
    # Extract session_id from filename: <session_id>_session.jsonl
    return files[0].stem.replace('_session', '')


def load_events(log_dir: Path, session_id: str) -> list[dict]:
    """Load all JSONL events for a session."""
    path = log_dir / f'{session_id}_session.jsonl'
    events = []
    if not path.exists():
        return events
    for line in path.read_text(errors='replace').splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return events


def build_session_panel(events: list[dict]) -> Panel:
    """Build Session Info panel."""
    start = next((e for e in events if e.get('event_type') == 'session_start'), {})
    end = next((e for e in events if e.get('event_type') == 'session_end'), None)
    model = start.get('model', 'unknown')
    prompt = start.get('prompt', '')[:80]
    status = f"exit={end['exit_status']}" if end else 'running...'
    sid = start.get('session_id', 'unknown')
    text = Text()
    text.append(f"Session: {sid}\n", style="bold cyan")
    text.append(f"Model:   {model}\n")
    text.append(f"Prompt:  {prompt}\n", style="dim")
    text.append(f"Status:  {status}\n", style="bold green" if end and end.get('exit_status') == 0 else "bold yellow")
    return Panel(text, title="Session Info", border_style="cyan")


def build_token_panel(events: list[dict]) -> Panel:
    """Build Token Usage panel."""
    summary = next((e for e in events if e.get('event_type') == 'token_usage_summary'), None)
    turns = [e for e in events if e.get('event_type') == 'llm_turn_end']
    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("Metric", style="dim")
    table.add_column("Value", justify="right")
    if summary:
        table.add_row("Input tokens", f"{summary.get('total_input_tokens', 0):,}")
        table.add_row("Output tokens", f"{summary.get('total_output_tokens', 0):,}")
        table.add_row("Total tokens", f"{summary.get('total_tokens', 0):,}")
        table.add_row("LLM turns", str(len(turns)))
    else:
        table.add_row("Status", "awaiting data...")
    return Panel(table, title="Token Usage", border_style="magenta")


def build_tools_panel(events: list[dict]) -> Panel:
    """Build Tool Calls panel."""
    tools = [e for e in events if e.get('event_type') == 'tool_call']
    table = Table(show_header=True, header_style="bold green")
    table.add_column("#", style="dim", width=4)
    table.add_column("Tool Name")
    for i, t in enumerate(tools[-20:], 1):  # last 20
        table.add_row(str(i), t.get('tool_name', ''))
    if not tools:
        table.add_row("-", "no tool calls yet")
    return Panel(table, title=f"Tool Calls ({len(tools)})", border_style="green")


def build_ralph_panel(events: list[dict]) -> Panel:
    """Build Ralph/Subagent panel."""
    stream = [e for e in events if e.get('event_type') == 'stream_event']
    text = Text()
    for s in stream[-15:]:  # last 15
        sub = s.get('sub_type', '')
        detail = s.get('detail', '')[:100]
        style = 'bold red' if 'error' in sub else 'bold yellow' if 'warning' in sub else ''
        text.append(f"[{sub}] {detail}\n", style=style)
    if not stream:
        text.append("No ralph/subagent events yet\n", style="dim")
    return Panel(text, title="Ralph / Subagents", border_style="yellow")


def build_display(events: list[dict]) -> Layout:
    """Build the full 6-panel layout."""
    layout = Layout()
    layout.split_column(
        Layout(name="top", size=6),
        Layout(name="middle"),
        Layout(name="bottom", size=8),
    )
    layout["top"].split_row(
        Layout(build_session_panel(events)),
        Layout(build_token_panel(events)),
    )
    layout["middle"].split_row(
        Layout(build_tools_panel(events)),
        Layout(build_ralph_panel(events)),
    )
    # Timeline: last N events
    timeline = Text()
    for e in events[-10:]:
        ts = e.get('ts', '??')
        etype = e.get('event_type', '??')
        timeline.append(f"{ts} {etype}\n", style="dim")
    layout["bottom"].update(Panel(timeline, title="Timeline", border_style="blue"))
    return layout


def main():
    parser = argparse.ArgumentParser(description='LLM Session Status TUI')
    parser.add_argument('--log-dir', required=True, help='Directory containing JSONL session logs')
    parser.add_argument('--session-id', default='', help='Specific session ID to view')
    parser.add_argument('--follow', action='store_true', help='Continuously refresh')
    args = parser.parse_args()

    log_dir = Path(args.log_dir)
    session_id = args.session_id or find_latest_session(log_dir)

    if not session_id:
        print("No session logs found in", log_dir)
        return

    console = Console()

    if args.follow:
        with Live(console=console, screen=False, refresh_per_second=2) as live:
            try:
                while True:
                    events = load_events(log_dir, session_id)
                    live.update(build_display(events))
                    time.sleep(0.5)
            except KeyboardInterrupt:
                pass
    else:
        events = load_events(log_dir, session_id)
        console.print(build_display(events))


if __name__ == '__main__':
    main()
