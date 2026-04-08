import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / 'parse_aichat_log.py'


def run_parser(aichat_log: Path, session_id: str, output: Path, state_file: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            '--aichat-log',
            str(aichat_log),
            '--session-id',
            session_id,
            '--output',
            str(output),
            '--state-file',
            str(state_file),
        ],
        check=True,
    )


def read_jsonl(path: Path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class ParseAiChatLogTests(unittest.TestCase):
    def test_parses_tool_calls_and_token_aggregation(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            aichat_log = tmp / 'aichat.log'
            session_jsonl = tmp / 'session.jsonl'
            state_file = tmp / 'state.json'

            ralph_dir = tmp / 'ralph'
            ralph_dir.mkdir()
            (ralph_dir / 'fix_plan.md').write_text('# fix\n- [x] done\n- [ ] 2. current\n')

            aichat_log.write_text(
                '\n'.join(
                    [
                        '[2026-04-01T01:00:00+00:00 INFO] non-stream-data: {"model":"m1","usage":{"input_tokens":100,"output_tokens":25}}',
                        '[2026-04-01T01:00:01+00:00 INFO] run_llm_function subagent {"args":{"task":"x"}}',
                        f'[2026-04-01T01:00:02+00:00 INFO] run_llm_function ralph_loop {{"args":{{"ralph_dir":"{ralph_dir}"}}}}',
                        '[2026-04-01T01:00:03+00:00 INFO] non-stream-data: {"model":"m1","usage":{"prompt_tokens":40,"completion_tokens":10}}',
                    ]
                )
                + '\n'
            )

            run_parser(aichat_log, 's1', session_jsonl, state_file)
            events = read_jsonl(session_jsonl)

            tool_events = [e for e in events if e.get('event_type') == 'tool_call']
            turn_events = [e for e in events if e.get('event_type') == 'llm_turn_end']
            summary = [e for e in events if e.get('event_type') == 'token_usage_summary'][-1]

            self.assertEqual(len(tool_events), 2)
            self.assertEqual(tool_events[0]['tool_name'], 'subagent')
            self.assertEqual(tool_events[1]['tool_name'], 'ralph_loop')
            self.assertIn('2. current', tool_events[1].get('ralph_step', ''))

            self.assertEqual(len(turn_events), 2)
            self.assertEqual(summary['total_input_tokens'], 140)
            self.assertEqual(summary['total_output_tokens'], 35)
            self.assertEqual(summary['total_tokens'], 175)
            self.assertEqual(summary['llm_turn_count'], 2)
            self.assertEqual(summary['tool_call_count'], 2)

    def test_incremental_state_avoids_reprocessing(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            aichat_log = tmp / 'aichat.log'
            session_jsonl = tmp / 'session.jsonl'
            state_file = tmp / 'state.json'

            aichat_log.write_text(
                '[2026-04-01T01:00:00+00:00 INFO] non-stream-data: {"model":"m1","usage":{"input_tokens":10,"output_tokens":5}}\n'
            )

            run_parser(aichat_log, 's2', session_jsonl, state_file)
            first = read_jsonl(session_jsonl)
            self.assertTrue(any(e.get('event_type') == 'llm_turn_end' for e in first))

            run_parser(aichat_log, 's2', session_jsonl, state_file)
            second = read_jsonl(session_jsonl)
            self.assertEqual(len(second), len(first))

            with aichat_log.open('a') as f:
                f.write('[2026-04-01T01:00:01+00:00 INFO] run_llm_function subagent\n')

            run_parser(aichat_log, 's2', session_jsonl, state_file)
            third = read_jsonl(session_jsonl)
            self.assertEqual(len([e for e in third if e.get('event_type') == 'tool_call']), 1)


    def test_cmd_name_format_and_tool_output(self):
        """Test that 'run_llm_function called with cmd_name: X' extracts correct tool name,
        and that Tool output: true/false emits tool_output events."""
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            aichat_log = tmp / 'aichat.log'
            session_jsonl = tmp / 'session.jsonl'
            state_file = tmp / 'state.json'

            aichat_log.write_text(
                '[2026-04-01T01:00:00+00:00 INFO] non-stream-data: {"model":"m1","usage":{"input_tokens":50,"output_tokens":10}}\n'
                '[2026-04-01T01:00:01+00:00 DEBUG] aichat::function: run_llm_function called with cmd_name: safe_script_executor\n'
                '[2026-04-01T01:00:02+00:00 DEBUG] aichat::function: Tool output: true\n'
            )

            run_parser(aichat_log, 's3', session_jsonl, state_file)
            events = read_jsonl(session_jsonl)

            tool_events = [e for e in events if e.get('event_type') == 'tool_call']
            output_events = [e for e in events if e.get('event_type') == 'tool_output']

            # Tool name extracted correctly (not 'called')
            self.assertEqual(len(tool_events), 1)
            self.assertEqual(tool_events[0]['tool_name'], 'safe_script_executor')

            # tool_output event emitted with correct tool correlation
            self.assertEqual(len(output_events), 1)
            self.assertTrue(output_events[0]['success'])
            self.assertEqual(output_events[0]['tool_name'], 'safe_script_executor')

    def test_tool_call_requested_no_double_counting(self):
        """Test that non-stream-data toolUse items emit tool_call_requested (not tool_call),
        and that tool_call_count is not doubled."""
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            aichat_log = tmp / 'aichat.log'
            session_jsonl = tmp / 'session.jsonl'
            state_file = tmp / 'state.json'

            non_stream = json.dumps({
                "model": "m1",
                "usage": {"input_tokens": 100, "output_tokens": 20},
                "output": {
                    "message": {
                        "content": [
                            {
                                "type": "toolUse",
                                "toolUseId": "tid1",
                                "name": "subagent",
                                "input": {"task": "x"},
                            }
                        ]
                    }
                },
            })
            aichat_log.write_text(
                f'[2026-04-01T01:00:00+00:00 INFO] non-stream-data: {non_stream}\n'
                '[2026-04-01T01:00:01+00:00 DEBUG] aichat::function: run_llm_function called with cmd_name: subagent\n'
            )

            run_parser(aichat_log, 's4', session_jsonl, state_file)
            events = read_jsonl(session_jsonl)

            tool_call_events = [e for e in events if e.get('event_type') == 'tool_call']
            tool_call_requested_events = [e for e in events if e.get('event_type') == 'tool_call_requested']
            summary = [e for e in events if e.get('event_type') == 'token_usage_summary'][-1]

            # Only one authoritative 'tool_call' event (from run_llm_function)
            self.assertEqual(len(tool_call_events), 1)
            self.assertEqual(tool_call_events[0]['tool_name'], 'subagent')

            # One 'tool_call_requested' from non-stream-data toolUse (has toolUseId)
            self.assertEqual(len(tool_call_requested_events), 1)
            self.assertEqual(tool_call_requested_events[0]['tool_name'], 'subagent')
            self.assertEqual(tool_call_requested_events[0].get('tool_use_id'), 'tid1')

            # tool_call_count = 1, NOT 2 — no double-counting
            self.assertEqual(summary['tool_call_count'], 1)

    def test_cache_read_tokens_extracted(self):
        """Test that cacheReadInputTokens is extracted and aggregated."""
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            aichat_log = tmp / 'aichat.log'
            session_jsonl = tmp / 'session.jsonl'
            state_file = tmp / 'state.json'

            aichat_log.write_text(
                '[2026-04-01T01:00:00+00:00 INFO] non-stream-data: '
                '{"model":"m1","usage":{"inputTokens":100,"outputTokens":20,"cacheReadInputTokens":500}}\n'
            )

            run_parser(aichat_log, 's5', session_jsonl, state_file)
            events = read_jsonl(session_jsonl)

            turn_events = [e for e in events if e.get('event_type') == 'llm_turn_end']
            summary = [e for e in events if e.get('event_type') == 'token_usage_summary'][-1]

            self.assertEqual(len(turn_events), 1)
            self.assertEqual(turn_events[0].get('cache_read_tokens'), 500)
            self.assertEqual(summary.get('total_cache_read_tokens'), 500)


if __name__ == '__main__':
    unittest.main()
