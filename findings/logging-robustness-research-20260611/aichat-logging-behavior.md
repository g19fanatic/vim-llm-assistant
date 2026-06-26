# Aichat Logging Behavior Research

## Investigation Summary

Researched aichat's logging and output mechanisms to understand what files are created during a run, how the `LLM_OUTPUT` environment variable is consumed, and where real-time output goes.

---

## 1. What Files Aichat Creates

### aichat.log — The Main Debug Log
- **Location**: `~/.config/aichat/aichat.log` (629KB as of investigation)
- **Controlled by**: `AICHAT_LOG_PATH` and `AICHAT_LOG_LEVEL` environment variables
- **Format**: Timestamped DEBUG entries with full API request/response data
  ```
  2026-06-11T09:21:05.044Z [DEBUG] aichat::client::bedrock: Request https://...
  2026-06-11T09:21:08.315Z [DEBUG] aichat::client::bedrock: non-stream-data: {...}
  ```
- **Contains**: Full JSON payloads of API requests and responses, tool call traces, token usage stats
- **Note**: Contains null bytes (binary padding) after log entries — appears to be a log rotation artifact

### Per-Call Temporary Files for Tool Output
- **Pattern**: `/tmp/aichat-{PID}-eval-{UUID}`
- **Purpose**: Created by aichat INTERNALLY for each tool invocation
- **Lifecycle**:
  1. `Creating per-call temporary file for LLM_OUTPUT: /tmp/aichat-PID-eval-UUID`
  2. Tool runs, writes output to this file
  3. `Reading tool output from per-call temporary file: /tmp/aichat-PID-eval-UUID`
  4. File is read and presumably deleted after
- **Example from log**:
  ```
  2026-06-11T09:21:12.560Z [DEBUG] aichat::function: Creating per-call temporary file for LLM_OUTPUT: /tmp/aichat-197730-eval-8b7b1b6a-2204-4f57-8951-80034bae21b7
  2026-06-11T09:21:12.607Z [DEBUG] aichat::function: Reading tool output from per-call temporary file: /tmp/aichat-197730-eval-8b7b1b6a-2204-4f57-8951-80034bae21b7
  2026-06-11T09:21:12.607Z [DEBUG] aichat::function: Tool output: true
  ```

### Session Files
- **Location**: `~/.config/aichat/sessions/*.yaml`
- **Purpose**: Persist conversation history when using `--session`
- **Not created** in the vim-llm-assistant use case (no `--session` flag used)

---

## 2. How LLM_OUTPUT Is Consumed

### The Vim Plugin's Use of LLM_OUTPUT
The vim plugin (`aichat.vim`) creates a temp file path via `tempname()` and passes it as `LLM_OUTPUT=<path>` environment variable to aichat.

### Aichat's Internal Handling
From the aichat debug log, the internal flow is:

1. **On tool call**: aichat logs `LLM_OUTPUT environment variable: Some("/tmp/vkD6Msd/2")` — this is the value SET BY THE VIM PLUGIN
2. **Per-call override**: aichat creates its OWN per-call temp file: `Creating per-call temporary file for LLM_OUTPUT: /tmp/aichat-PID-eval-UUID`
3. **Tool execution**: The tool receives the per-call temp file as its `LLM_OUTPUT`, NOT the vim plugin's file
4. **Output capture**: After tool runs, aichat reads from the per-call file: `Tool output: true`

### Key Insight: LLM_OUTPUT Has Two Layers

| Layer | Set By | Value | Purpose |
|-------|--------|-------|---------|
| Outer | Vim plugin (`aichat.vim:~110`) | `tempname()` → `/tmp/vXXXXXX/N` | Originally intended for tool output capture |
| Inner | Aichat internally | `/tmp/aichat-{PID}-eval-{UUID}` | Per-call isolation for each tool invocation |

Aichat **overrides** the outer LLM_OUTPUT with its own per-call files. The outer file set by the vim plugin may receive nothing or only a final combined result (the log shows `Displaying tool call prompt (IS_STDOUT_TERMINAL: false, llm_output_defined: true)`).

### How Tools (scripts/run-tool.sh) Use LLM_OUTPUT
From `~/sources/llm-functions/scripts/run-tool.sh`:
```bash
if [[ -z "$LLM_OUTPUT" ]]; then
    is_temp_llm_output=1
    if ! export LLM_OUTPUT="$(mktemp)"; then
        ...
    fi
fi
# ... tool runs ...
cat "$LLM_OUTPUT"  # outputs the result
```

- If LLM_OUTPUT is already set (by aichat), tools append their output to it
- If not set, they create their own temp file
- Tool output is written to `$LLM_OUTPUT` via `>> "$LLM_OUTPUT"` (append)

### MCP Server Handling
From `~/sources/llm-functions/mcp/server/index.js`:
```javascript
const { exitCode, stderr } = await runCommand(command, args, { ...env, LLM_OUTPUT: tmpFile });
```
The MCP bridge creates its own temp file and passes it to the tool subprocess.

---

## 3. Where Real-Time Output Goes

### The Actual LLM Response Stream
- **aichat stdout** → captured by Vim's `out_cb` callback → stored in memory (`l:output` list)
- **Never written to disk** during execution
- Only appears in the `[LLM-Scratch]` buffer after completion
- **Not available** for real-time tailing by the user

### The Debug Log (AICHAT_LOG_PATH)
- **Set by the vim plugin**: `AICHAT_LOG_PATH=/home/pdibiase/.local/share/vim-llm-assistant/logs/2026-06-11_052351_aichat.log`
- **Set by the vim plugin**: `AICHAT_LOG_LEVEL=debug`
- Contains full API requests/responses in real-time
- **CAN be tailed**: `tail -f $AICHAT_LOG_PATH` during execution
- **But**: contains raw JSON API dumps, not human-readable conversation flow

### Status Line Display
- Shows the **outer** `LLM_OUTPUT` path (the vim plugin's `tempname()` file)
- This file is often **empty** because aichat overrides it with per-call files
- The user sees a path they can't usefully tail

---

## 4. Environment Variables Controlling Logging

| Variable | Current Value (set by vim plugin) | Purpose |
|----------|-----------------------------------|---------|
| `AICHAT_LOG_PATH` | `~/.local/share/vim-llm-assistant/logs/YYYY-MM-DD_HHMMSS_aichat.log` | Where aichat writes its debug log |
| `AICHAT_LOG_LEVEL` | `debug` | Log verbosity (debug = everything) |
| `LLM_OUTPUT` | `/tmp/aichat-{PID}-eval-{UUID}` (per-call, set by aichat internally) | Where tools write output |
| `LLM_ROOT_DIR` | `~/.config/aichat/functions` | Root of llm-functions directory |
| `LLM_TOOL_CACHE_DIR` | `~/.config/aichat/functions/cache/{tool_name}` | Tool-specific cache |

---

## 5. Critical Findings for the Logging Improvement Plan

### The Plugin Already Creates Log Files!
The vim plugin ALREADY sets `AICHAT_LOG_PATH` to a per-session log file under `~/.local/share/vim-llm-assistant/logs/`. This was not obvious from the source alone — it's confirmed by the runtime environment.

### The Status Line Bug Root Cause (Confirmed)
The status line shows the `tempname()` LLM_OUTPUT file, but:
1. Aichat internally overrides this with per-call temp files
2. The outer file may be empty or only contain aggregated tool output
3. The user probably wants to see EITHER the aichat debug log OR the actual response stream
4. Neither of these is what's shown

### aichat Has No `--log` or `--output` CLI Flag
From `aichat --help` (v0.30.0): No explicit log/output flags exist. Logging is controlled entirely via environment variables (`AICHAT_LOG_PATH`, `AICHAT_LOG_LEVEL`). Since aichat is a Rust binary, `RUST_LOG` was not set (aichat uses its own logging system).

### No Streaming-to-File Mode
aichat's `--no-stream` flag disables streaming but doesn't redirect output to a file. There's no built-in way to stream the LLM response to a file for real-time tailing. The response is only available via stdout (captured by vim callbacks).

---

## 6. Recommendations

1. **Show the correct log path**: The status line should show `AICHAT_LOG_PATH` (the debug log), not the LLM_OUTPUT temp file
2. **Create a human-readable log**: Consider intercepting the `out_cb` callback to also write to a tailable file
3. **Expose existing logs**: The plugin already creates `~/.local/share/vim-llm-assistant/logs/` files — add a command to open/tail them
4. **Per-request log naming**: The existing log path includes timestamp — could also include model/prompt info in filename
