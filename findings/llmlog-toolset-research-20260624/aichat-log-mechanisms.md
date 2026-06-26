# Aichat Logging Mechanisms in vim-llm-assistant

## Summary

This document maps all environment variables, CLI options, and configuration mechanisms
used by the vim-llm-assistant plugin to control aichat's logging behavior. Based on
reading `autoload/llm/adapters/aichat.vim`, `autoload/llm/log.vim`, `autoload/llm.vim`,
and `plugin/llm.vim`, cross-referenced with prior research in
`findings/logging-robustness-research-20260611/aichat-logging-behavior.md`.

---

## 1. Environment Variables Set by the Plugin

### AICHAT_LOG_PATH
- **Source**: `autoload/llm/adapters/aichat.vim:166`
- **Value**: `l:log_paths.aichat` → resolves to `~/.local/share/vim-llm-assistant/logs/<YYYYMMDD_HHMMSS_NNN>/aichat.log`
- **Condition**: Only set when `g:llm_log_level ==# 'debug'`
- **Purpose**: Tells aichat where to write its internal debug log (full API request/response JSON)
- **At default 'info' level**: NOT SET — aichat writes no debug log

### AICHAT_LOG_LEVEL
- **Source**: `autoload/llm/adapters/aichat.vim:166`
- **Value**: Always `'debug'` (hardcoded)
- **Condition**: Only set when `g:llm_log_level ==# 'debug'` (same conditional as AICHAT_LOG_PATH)
- **Purpose**: Controls aichat's log verbosity; `debug` = everything including full API payloads
- **At default 'info' level**: NOT SET — aichat uses no logging

### LLM_OUTPUT
- **Source**: `autoload/llm/adapters/aichat.vim:168` (async), `:280/:282` (sync)
- **Value**: `tempname()` — a Vim-generated temporary file path (e.g., `/tmp/vXXXXXX/N`)
- **Condition**: ALWAYS set, regardless of log level
- **Purpose**: Originally intended to capture tool output from aichat tool invocations
- **Key caveat** (from prior research): Aichat internally **overrides** this with per-call temp files (`/tmp/aichat-{PID}-eval-{UUID}`) for each tool invocation. The outer LLM_OUTPUT file may receive nothing useful.
- **Post-completion**: The temp file contents (if any) are persisted to `log_paths.tools` at job completion (`autoload/llm/adapters/aichat.vim:320-321`)

### NOT Set by Plugin (but relevant to aichat ecosystem)
| Variable | Set By | Purpose |
|----------|--------|---------|
| `LLM_ROOT_DIR` | aichat internally / user shell | Root of llm-functions directory (`~/.config/aichat/functions`) |
| `LLM_TOOL_CACHE_DIR` | aichat internally | Tool-specific cache (`~/.config/aichat/functions/cache/{tool_name}`) |
| `RUST_LOG` | N/A | Not used by aichat (has own logging system) |

---

## 2. Plugin Configuration Variables (Vim globals)

### g:llm_log_level
- **Source**: `plugin/llm.vim:39-44`
- **Default**: `'info'`
- **Values**: `'info'` | `'debug'` (note: `'none'` is explicitly overridden to `'info'` at plugin load)
- **Effect on logging**:
  | Level | response.md | input.json | aichat.log | tools.log | session.log |
  |-------|-------------|------------|------------|-----------|-------------|
  | `info` | ✅ Written | ❌ Temp only | ❌ Not created | ✅ Written | ✅ Appended |
  | `debug` | ✅ Written | ✅ Persisted | ✅ Created | ✅ Written | ✅ Appended |

### g:llm_log_dir
- **Source**: `plugin/llm.vim:34-35`
- **Default**: `~/.local/share/vim-llm-assistant/logs`
- **Purpose**: Base directory for all log storage
- **Structure**: `<g:llm_log_dir>/<YYYYMMDD_HHMMSS_NNN>/` per request

### g:llm_log_keep_count
- **Source**: `plugin/llm.vim:48-49`
- **Default**: `500`
- **Purpose**: Max number of request log directories to retain (excess pruned oldest-first)

### g:llm_log_max_age_days
- **Source**: `plugin/llm.vim:53-54`
- **Default**: `30`
- **Purpose**: Max age in days before log directories are cleaned

---

## 3. CLI Options Used by the Adapter

### Options passed to aichat
| Option | Source | Value |
|--------|--------|-------|
| `--role` | `aichat.vim:168` | `g:llm_role` (default: `'default-vim-role'`) |
| `--model` | `aichat.vim:168` | Resolved model name |
| `--file` | `aichat.vim:168` | Path to JSON input file |
| `-f` | `aichat.vim:152-156` | Additional file arguments (from `file_arguments` in JSON) |
| `--` | `aichat.vim:170` | Prompt text (when provided) |
| `--list-models` | `aichat.vim:356` | For model discovery (not in request path) |

### Logging-specific CLI flags
**None exist.** aichat (v0.30.0) has no `--log`, `--output`, `--verbose`, or `--debug` flags.
All logging control is exclusively through environment variables (AICHAT_LOG_PATH, AICHAT_LOG_LEVEL).

### The `--no-stream` flag
Available in aichat but **not used** by the plugin. It disables streaming but does NOT redirect
output to a file. The plugin captures stdout via Vim's `out_cb` channel callback instead.

---

## 4. Command Augmentation Mechanism (cmd_extra)

- **Source**: `autoload/llm/adapters/aichat.vim:137-147` (async), `:260-268` (sync)
- **Mechanism**: If `g:llm_adapter_cmd_extra.aichat` exists as a function reference, it's called
  with `(json_filename, prompt, model)` and its return value is prepended to the command string.
- **Purpose**: Allows users to inject additional environment variables or command prefixes
- **Example use**: Could inject `AICHAT_LOG_PATH=... AICHAT_LOG_LEVEL=debug` even at `info` log level
- **Current status**: No default is set; purely opt-in extension point

---

## 5. The Complete Command Construction

### Async path (process_async, line 168):
```
bash -c '{cmd_extra}{aichat_log_env}LLM_OUTPUT={temp_file} aichat --role {role} --model {model} {file_flags}--file {json_file} [-- {prompt}]'
```

Where:
- `{cmd_extra}` = output of `g:llm_adapter_cmd_extra.aichat()` (empty by default)
- `{aichat_log_env}` = `AICHAT_LOG_PATH=... AICHAT_LOG_LEVEL=debug ` (only at debug level, else empty)
- `{temp_file}` = `tempname()` output (always present)
- `{file_flags}` = `-f file1 -f file2 ...` (from json `file_arguments`, may be empty)

### Sync path (process, lines 280/282):
Identical structure but runs via `system()` instead of `job_start()`.

---

## 6. Log File Creation Flow

```
llm#run() [autoload/llm.vim:658]
  ├─ llm#log#create_request() [autoload/llm/log.vim:14]
  │    ├─ Creates: ~/.local/share/vim-llm-assistant/logs/YYYYMMDD_HHMMSS_NNN/
  │    ├─ Returns: {dir, input, response, tools, aichat, dirname}
  │    └─ Updates: 'latest' symlink → newest dirname
  │
  ├─ At 'debug' level: writes JSON to log_paths.input
  │   At 'info' level: writes JSON to tempname() (auto-cleaned)
  │
  └─ Calls adapter.process_async(json_file, prompt, model, callback)
       ├─ Sets env vars (AICHAT_LOG_PATH, AICHAT_LOG_LEVEL, LLM_OUTPUT)
       ├─ Writes response header to log_paths.response
       ├─ out_cb: appends each line to log_paths.response (real-time)
       └─ on_job_complete:
            ├─ Persists temp_file → log_paths.tools
            ├─ Appends to session.log
            └─ Calls callback with full response text
```

---

## 7. Key Findings & Cross-Reference with Prior Research

### Confirmed from prior research:
1. **AICHAT_LOG_PATH/LEVEL are the only levers** — no CLI flags for logging exist
2. **LLM_OUTPUT has a two-layer override problem** — aichat creates per-call temp files internally
3. **No streaming-to-file mode** — response only available via stdout/out_cb
4. **The plugin already writes response.md in real-time** via out_cb at ALL log levels (not just debug)

### New findings from this audit:
1. **AICHAT_LOG_PATH is NOT set at default 'info' level** — this means aichat.log is only
   created when user explicitly sets `g:llm_log_level = 'debug'` in their vimrc
2. **input.json is also debug-only** — at 'info' level, the input JSON goes to a temp file
   that's auto-cleaned (no persistence)
3. **The cmd_extra mechanism** exists as an extension point to inject any additional env vars
   or command prefixes — could be leveraged to conditionally enable AICHAT_LOG_PATH
4. **session.log is always appended** (at any non-none level) with: timestamp, model, duration,
   status, and prompt preview (truncated to 80 chars)
5. **tools.log persistence** depends on LLM_OUTPUT temp file having content — but due to
   the two-layer override, it may often be empty

### Env var lifecycle summary:
| Env Var | When Set | Who Reads It | Where Output Goes |
|---------|----------|--------------|-------------------|
| `AICHAT_LOG_PATH` | `g:llm_log_level == 'debug'` | aichat binary | `<request_dir>/aichat.log` |
| `AICHAT_LOG_LEVEL` | `g:llm_log_level == 'debug'` | aichat binary | Controls verbosity of above |
| `LLM_OUTPUT` | Always | aichat → tool scripts | `tempname()` → persisted to `<request_dir>/tools.log` |

---

## 8. Available aichat CLI Options (Complete, from `aichat --help` v0.30.0)

Relevant to logging/output control:
- `--no-stream` — Disable streaming (not used by plugin)
- `--dry-run` — Print request without executing (not used)
- No `--log`, `--verbose`, `--debug`, or `--output` flags exist

All other options used by the plugin: `--role`, `--model`, `--file`, `-f`, `--list-models`
