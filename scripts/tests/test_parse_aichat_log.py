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


if __name__ == '__main__':
    unittest.main()
