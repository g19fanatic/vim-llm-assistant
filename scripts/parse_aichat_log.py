#!/usr/bin/env python3
"""Parse a per-session aichat log file and emit JSONL events.

Reads the aichat debug log, extracts:
- Token usage from 'non-stream-data' JSON lines
- Tool call names from 'run_llm_function' lines
- Timing from timestamp deltas

Appends structured JSONL events to the session log file.
"""
import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

# Patterns observed in aichat debug logs
RE_TIMESTAMP = re.compile(r'^\[(\d{4}-\d{2}-\d{2}T[\d:.]+)')
RE_NON_STREAM = re.compile(r'non-stream-data:\s*(\{.+\})\s*$')
RE_TOOL_CALL = re.compile(r'run_llm_function\s+(\S+)')
RE_TOKEN_USAGE = re.compile(r'"usage"\s*:\s*(\{[^}]+\})')


def parse_aichat_log(log_path: Path) -> list[dict]:
    """Parse aichat log and return structured events."""
    events = []
    if not log_path.exists():
        return events

    total_input_tokens = 0
    total_output_tokens = 0
    tool_calls = []

    for line in log_path.read_text(errors='replace').splitlines():
        # Extract token usage from non-stream-data responses
        m = RE_NON_STREAM.search(line)
        if m:
            try:
                data = json.loads(m.group(1))
                usage = data.get('usage', {})
                inp = usage.get('prompt_tokens', usage.get('input_tokens', 0))
                out = usage.get('completion_tokens', usage.get('output_tokens', 0))
                total_input_tokens += inp
                total_output_tokens += out
                events.append({
                    'event_type': 'llm_turn_end',
                    'input_tokens': inp,
                    'output_tokens': out,
                    'model': data.get('model', ''),
                })
            except (json.JSONDecodeError, KeyError):
                pass

        # Extract tool call invocations
        m = RE_TOOL_CALL.search(line)
        if m:
            tool_name = m.group(1)
            tool_calls.append(tool_name)
            events.append({
                'event_type': 'tool_call',
                'tool_name': tool_name,
            })

    # Summary event
    events.append({
        'event_type': 'token_usage_summary',
        'total_input_tokens': total_input_tokens,
        'total_output_tokens': total_output_tokens,
        'total_tokens': total_input_tokens + total_output_tokens,
        'tool_call_count': len(tool_calls),
    })

    return events


def main():
    parser = argparse.ArgumentParser(description='Parse aichat log for session events')
    parser.add_argument('--aichat-log', required=True, help='Path to aichat log file')
    parser.add_argument('--session-id', required=True, help='Session ID to tag events with')
    parser.add_argument('--output', required=True, help='Path to append JSONL events')
    args = parser.parse_args()

    events = parse_aichat_log(Path(args.aichat_log))

    ts = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    with open(args.output, 'a') as f:
        for event in events:
            event['ts'] = ts
            event['session_id'] = args.session_id
            event['source'] = 'aichat_log_parser'
            f.write(json.dumps(event) + '\n')


if __name__ == '__main__':
    main()
