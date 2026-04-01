#!/usr/bin/env python3
"""Parse a per-session aichat log file and emit incremental JSONL events.

Reads the aichat debug log and extracts:
- Token usage from `non-stream-data` JSON lines
- Tool call names from `run_llm_function` lines

When --state-file is provided, only new log content since last parse is processed.
Cumulative token totals are persisted in state and emitted as `token_usage_summary`.
"""

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

RE_NON_STREAM_MARKER = re.compile(r"non-stream-data:\s*")
RE_TOOL_CALL = re.compile(r"run_llm_function(?:\s+|:\s*|\()([A-Za-z0-9_.\-]+)")
RE_TIMESTAMP = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T[\d:.+-]+)\]")
RE_TOOL_KV = re.compile(r"\btool(?:_name)?\s*[=:]\s*([A-Za-z0-9_.\-]+)")


DEFAULT_STATE = {
    "last_offset": 0,
    "pending_fragment": "",
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "llm_turn_count": 0,
    "tool_call_count": 0,
    "recent_line_hashes": [],
}

MAX_RECENT_LINE_HASHES = 500


def _find_first_json_object(text: str) -> dict[str, Any] | None:
    """Extract first JSON object from text, tolerating trailing noise."""
    start = text.find("{")
    if start < 0:
        return None
    decoder = json.JSONDecoder()
    try:
        obj, _ = decoder.raw_decode(text[start:])
    except json.JSONDecodeError:
        return None
    return obj if isinstance(obj, dict) else None


def _extract_usage(data: dict[str, Any]) -> tuple[int, int]:
    usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
    inp = int(
        usage.get("input_tokens")
        or usage.get("prompt_tokens")
        or usage.get("prompt_token_count")
        or 0
    )
    out = int(
        usage.get("output_tokens")
        or usage.get("completion_tokens")
        or usage.get("completion_token_count")
        or 0
    )
    if inp == 0 and out == 0:
        total = int(usage.get("total_tokens") or 0)
        if total > 0:
            out = total
    return inp, out


def _extract_tool_name(line: str) -> str:
    m = RE_TOOL_CALL.search(line)
    if m:
        return m.group(1).strip()
    m = RE_TOOL_KV.search(line)
    if m:
        return m.group(1).strip()
    return ""


def _extract_tool_payload(line: str) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    obj = _find_first_json_object(line)
    if isinstance(obj, dict):
        payload = obj
    return payload


def _find_current_ralph_step(ralph_dir: str) -> str:
    if not ralph_dir:
        return ""
    fix_plan = Path(ralph_dir) / "fix_plan.md"
    if not fix_plan.exists():
        return ""
    try:
        for line in fix_plan.read_text(errors="replace").splitlines():
            if re.match(r"^\s*-\s*\[\s\]\s+", line):
                return line.strip()
    except OSError:
        return ""
    return ""


def _is_duplicate_line(state: dict[str, Any], line: str) -> bool:
    digest = hashlib.sha1(line.encode("utf-8", errors="replace")).hexdigest()
    recent = state.get("recent_line_hashes", [])
    if digest in recent:
        return True
    recent.append(digest)
    if len(recent) > MAX_RECENT_LINE_HASHES:
        recent = recent[-MAX_RECENT_LINE_HASHES:]
    state["recent_line_hashes"] = recent
    return False


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

        if _is_duplicate_line(state, line):
            continue

        if RE_NON_STREAM_MARKER.search(line):
            try:
                data = _find_first_json_object(line) or {}
                inp, out = _extract_usage(data)
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
            except (TypeError, ValueError):
                pass

        if "run_llm_function" in line or "tool_name" in line or "tool=" in line:
            tool_name = _extract_tool_name(line)
            if not tool_name:
                continue
            payload = _extract_tool_payload(line)
            raw_args = payload.get("args") if isinstance(payload.get("args"), dict) else {}
            if not raw_args and isinstance(payload.get("arguments"), dict):
                raw_args = payload.get("arguments")
            ralph_dir = ""
            if isinstance(raw_args, dict):
                ralph_dir = str(raw_args.get("ralph_dir") or raw_args.get("resume") or "")
            ralph_step = _find_current_ralph_step(ralph_dir)
            state["tool_call_count"] = int(state.get("tool_call_count", 0)) + 1
            events.append(
                {
                    "event_type": "tool_call",
                    "tool_name": tool_name,
                    "tool_args": raw_args if isinstance(raw_args, dict) else {},
                    "ralph_dir": ralph_dir,
                    "ralph_step": ralph_step,
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
