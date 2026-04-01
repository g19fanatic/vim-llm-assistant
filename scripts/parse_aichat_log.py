#!/usr/bin/env python3
"""Parse a per-session aichat log file and emit incremental JSONL events.

Reads the aichat debug log and extracts:
- Token usage from `non-stream-data` JSON lines
- Tool call names from `run_llm_function` lines

When --state-file is provided, only new log content since last parse is processed.
Cumulative token totals are persisted in state and emitted as `token_usage_summary`.
"""

import argparse
import json
import re
from datetime import datetime
from pathlib import Path

RE_NON_STREAM = re.compile(r"non-stream-data:\s*(\{.+\})\s*$")
RE_TOOL_CALL = re.compile(r"run_llm_function\s+(\S+)")
RE_TIMESTAMP = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T[\d:.+-]+)\]")


DEFAULT_STATE = {
    "last_offset": 0,
    "pending_fragment": "",
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "llm_turn_count": 0,
    "tool_call_count": 0,
}


def load_state(state_path: Path | None) -> dict:
    if state_path is None or not state_path.exists():
        return dict(DEFAULT_STATE)
    try:
        data = json.loads(state_path.read_text(errors="replace"))
        merged = dict(DEFAULT_STATE)
        merged.update(data)
        return merged
    except json.JSONDecodeError:
        return dict(DEFAULT_STATE)


def save_state(state_path: Path | None, state: dict) -> None:
    if state_path is None:
        return
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state))


def parse_incremental(log_path: Path, state: dict) -> tuple[list[dict], dict]:
    events: list[dict] = []
    if not log_path.exists():
        return events, state

    file_size = log_path.stat().st_size
    last_offset = int(state.get("last_offset", 0))
    if last_offset < 0 or last_offset > file_size:
        # Log rotated/truncated.
        last_offset = 0
        state["pending_fragment"] = ""

    with log_path.open("rb") as f:
        f.seek(last_offset)
        chunk = f.read()
        new_offset = f.tell()

    if not chunk:
        return events, state

    decoded = chunk.decode("utf-8", errors="replace")
    text = state.get("pending_fragment", "") + decoded
    lines = text.splitlines(keepends=True)

    complete_lines: list[str] = []
    pending_fragment = ""
    for line in lines:
        if line.endswith("\n") or line.endswith("\r"):
            complete_lines.append(line.rstrip("\r\n"))
        else:
            pending_fragment = line

    for line in complete_lines:
        line_ts = ""
        ts_match = RE_TIMESTAMP.search(line)
        if ts_match:
            line_ts = ts_match.group(1)

        m = RE_NON_STREAM.search(line)
        if m:
            try:
                data = json.loads(m.group(1))
                usage = data.get("usage", {})
                inp = int(usage.get("prompt_tokens", usage.get("input_tokens", 0)) or 0)
                out = int(usage.get("completion_tokens", usage.get("output_tokens", 0)) or 0)
                state["total_input_tokens"] = int(state.get("total_input_tokens", 0)) + inp
                state["total_output_tokens"] = int(state.get("total_output_tokens", 0)) + out
                state["llm_turn_count"] = int(state.get("llm_turn_count", 0)) + 1
                events.append(
                    {
                        "event_type": "llm_turn_end",
                        "input_tokens": inp,
                        "output_tokens": out,
                        "model": data.get("model", ""),
                        "line_ts": line_ts,
                    }
                )
            except (json.JSONDecodeError, TypeError, ValueError):
                pass

        m = RE_TOOL_CALL.search(line)
        if m:
            tool_name = m.group(1)
            state["tool_call_count"] = int(state.get("tool_call_count", 0)) + 1
            events.append(
                {
                    "event_type": "tool_call",
                    "tool_name": tool_name,
                    "line_ts": line_ts,
                }
            )

    if events:
        total_input = int(state.get("total_input_tokens", 0))
        total_output = int(state.get("total_output_tokens", 0))
        events.append(
            {
                "event_type": "token_usage_summary",
                "total_input_tokens": total_input,
                "total_output_tokens": total_output,
                "total_tokens": total_input + total_output,
                "tool_call_count": int(state.get("tool_call_count", 0)),
                "llm_turn_count": int(state.get("llm_turn_count", 0)),
            }
        )

    state["pending_fragment"] = pending_fragment
    state["last_offset"] = new_offset
    return events, state


def main() -> None:
    parser = argparse.ArgumentParser(description="Parse aichat log for session events")
    parser.add_argument("--aichat-log", required=True, help="Path to aichat log file")
    parser.add_argument("--session-id", required=True, help="Session ID to tag events with")
    parser.add_argument("--output", required=True, help="Path to append JSONL events")
    parser.add_argument(
        "--state-file",
        default="",
        help="Optional parser state file for incremental parsing",
    )
    args = parser.parse_args()

    state_path = Path(args.state_file) if args.state_file else None
    state = load_state(state_path)
    events, new_state = parse_incremental(Path(args.aichat_log), state)
    save_state(state_path, new_state)

    if not events:
        return

    ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    with open(args.output, "a") as f:
        for event in events:
            event["ts"] = ts
            event["session_id"] = args.session_id
            event["source"] = "aichat_log_parser"
            f.write(json.dumps(event) + "\n")


if __name__ == "__main__":
    main()
