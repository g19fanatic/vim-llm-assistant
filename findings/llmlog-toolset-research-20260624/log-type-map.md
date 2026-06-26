# Log File Types → Retrieval Paths Map

## Overview

This document maps every log file type in vim-llm-assistant to its disk location,
creation mechanism, and retrieval command. All paths are expanded from defaults.

---

## Disk Path Structure

```
~/.local/share/vim-llm-assistant/logs/          ← g:llm_log_dir (expand())
├── session.log                                  ← append-only session journal
├── latest → 20260611_092151_001                 ← symlink to newest request dir
├── 20260611_092151_001/                         ← per-request directory
│   ├── response.md                              ← LLM response (streamed in real-time)
│   ├── input.json                               ← full JSON context (debug only)
│   ├── tools.log                                ← tool/function call output
│   └── aichat.log                               ← aichat debug log (debug only)
├── 20260611_093412_001/
│   └── ...
└── ...
```

**Base directory**: `expand(g:llm_log_dir)` → default `~/.local/share/vim-llm-assistant/logs`
**Per-request directory**: `{base}/{YYYYMMDD_HHMMSS_NNN}/` — sequence number avoids collisions within same second

---

## Log File Type Details

### 1. response.md

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/<YYYYMMDD_HHMMSS_NNN>/response.md` |
| **Created by** | `s:aichat_adapter.process_async()` at `autoload/llm/adapters/aichat.vim:186-192` (header) + `out_cb` lambda at `:197` (streaming lines) |
| **Created when** | Every request where `g:llm_log_level != 'none'` (i.e., always, since 'none' → 'info') |
| **Content** | HTML comment header (time, model, prompt) followed by raw LLM response text, streamed line-by-line as it arrives |
| **Access commands** | `:LLMLog` (default), `:LLMLog response`, `:LLMLogTail` (default), `:LLMLogTail response` |
| **Programmatic access** | `llm#log#latest_response()` → `{g:llm_log_dir}/latest/response.md` |
| **Can be live-tailed** | ✅ Yes — primary use case of `:LLMLogTail` |
| **Condition** | Always created (at info AND debug levels) |

**Creation flow**:
1. `llm#log#create_request()` (`log.vim:28`) sets path: `l:dir . '/response.md'`
2. Before job starts, header is written: `writefile([header_lines], l:log_paths.response)` (`aichat.vim:186-192`)
3. As aichat streams stdout, `out_cb` appends each line: `writefile([msg], l:log_paths.response, 'a')` (`aichat.vim:197`)
4. At completion, `s:on_job_complete` reads back the full file to pass to callback (`aichat.vim:328-329`)

---

### 2. input.json

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/<YYYYMMDD_HHMMSS_NNN>/input.json` |
| **Created by** | `llm#run()` at `autoload/llm.vim:344-347` |
| **Created when** | Only persisted when `g:llm_log_level ==# 'debug'` |
| **Content** | Full JSON context payload: `{llm_history, buffers, active_buffer, file_arguments, prompt, cursor_line, cursor_col}` |
| **Access commands** | `:LLMLog input` |
| **Can be live-tailed** | ❌ No — written once before request starts |
| **Condition** | **DEBUG level only** — at 'info' level, JSON goes to `tempname()` (auto-deleted) |

**Creation flow**:
1. `llm#log#create_request()` (`log.vim:27`) sets path: `l:dir . '/input.json'`
2. `llm#run()` checks log level:
   - `debug`: `let l:tempfile = l:log_paths.input` → persists as log file (`llm.vim:344`)
   - `info`: `let l:tempfile = tempname()` → auto-cleaned after use (`llm.vim:346`)
3. JSON written: `call writefile(split(l:json_data, "\n"), l:tempfile)` (`llm.vim:347`)

**Note**: At 'info' level, the input.json path EXISTS in the dict but the file is **never created**. Opening `:LLMLog input` at 'info' level will show "File not found".

---

### 3. tools.log

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/<YYYYMMDD_HHMMSS_NNN>/tools.log` |
| **Created by** | `s:on_job_complete()` at `autoload/llm/adapters/aichat.vim:319-321` |
| **Created when** | At job completion, IF the LLM_OUTPUT temp file exists and has content (`getfsize > 0`) |
| **Content** | Tool/function call output captured via `LLM_OUTPUT` environment variable |
| **Access commands** | `:LLMLog tools` |
| **Can be live-tailed** | ❌ No — written once at job completion |
| **Condition** | Always attempted at both info and debug levels, but may be empty/missing |

**Creation flow**:
1. `llm#log#create_request()` (`log.vim:29`) sets path: `l:dir . '/tools.log'`
2. `process_async()` creates temp file: `let l:temp_file = tempname()` (`aichat.vim:136`)
3. Temp file passed as env: `LLM_OUTPUT={temp_file}` in the command string (`aichat.vim:168`)
4. At completion: `writefile(readfile(a:temp_file), l:job_info.log_paths.tools)` (`aichat.vim:320`)

**Caveat**: Due to aichat's internal LLM_OUTPUT override behavior (creates per-call `/tmp/aichat-{PID}-eval-{UUID}` files), the outer temp file often receives NO data. This means `tools.log` is frequently empty or not created, even when tools were actually invoked. See `findings/logging-robustness-research-20260611/aichat-logging-behavior.md` §2.

---

### 4. aichat.log

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/<YYYYMMDD_HHMMSS_NNN>/aichat.log` |
| **Created by** | The aichat binary itself (Rust process), directed via AICHAT_LOG_PATH env var |
| **Created when** | Only when `g:llm_log_level ==# 'debug'` (which sets the env vars) |
| **Content** | Full aichat internal debug output: API request/response JSON, tool call traces, token usage, errors |
| **Access commands** | `:LLMLog aichat`, `:LLMLogTail aichat` |
| **Can be live-tailed** | ✅ Yes — aichat writes in real-time during execution |
| **Condition** | **DEBUG level only** — at 'info' level, env vars are not set and file is never created |

**Creation flow**:
1. `llm#log#create_request()` (`log.vim:30`) sets path: `l:dir . '/aichat.log'`
2. In `process_async()`, conditional env setup (`aichat.vim:165-167`):
   ```vim
   if g:llm_log_level ==# 'debug' && has_key(l:log_paths, 'aichat')
     let l:aichat_log_env = 'AICHAT_LOG_PATH=' . shellescape(l:log_paths.aichat) . ' AICHAT_LOG_LEVEL=debug '
   endif
   ```
3. aichat binary reads AICHAT_LOG_PATH and writes debug data throughout execution
4. File grows in real-time — suitable for `tail -F`

**Note**: When not at debug level, `:LLMLog aichat` and `:LLMLogTail aichat` will show "File not found" since the env var directing output is never set.

---

### 5. session.log

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/session.log` |
| **Created by** | `llm#log#session_append()` at `autoload/llm/log.vim:36-38`, called from `s:on_job_complete()` (`aichat.vim:336-341`) |
| **Created when** | After every successful request completion (at any non-none log level, i.e., always) |
| **Content** | Append-only journal with one line per request: `YYYY-MM-DD HH:MM:SS | model | duration_s | status | prompt_preview` |
| **Access commands** | `:LLMLog session` |
| **Can be live-tailed** | ⚠️ Partially — appended at job completion (not during), so useful for monitoring completion history |
| **Condition** | Always appended (at info AND debug levels) |

**Creation flow**:
1. `session.log` path is NOT in `llm#log#create_request()` return dict — it's a root-level file
2. Path resolved: `llm#log#dir() . '/session.log'` (`log.vim:37`)
3. After callback fires, `s:on_job_complete` constructs entry (`aichat.vim:334-339`):
   ```
   2026-06-11 09:21:08 | claude-3-7-sonnet-20250219 | 17s | OK | Analyze this function and suggest...
   ```
4. Appended via: `call writefile([a:entry], l:logfile, 'a')` (`log.vim:38`)

**Format of each line**:
```
{timestamp} | {model} | {duration}s | {OK|ERROR:code} | {prompt_first_80_chars}
```

---

### 6. latest (symlink)

| Attribute | Value |
|-----------|-------|
| **Disk path** | `~/.local/share/vim-llm-assistant/logs/latest` |
| **Created by** | `llm#log#create_request()` at `autoload/llm/log.vim:31-32` |
| **Created when** | Every request (atomic update via `ln -sfn`) |
| **Content** | Symlink pointing to the basename of the newest request directory (e.g., `20260611_092151_001`) |
| **Access commands** | Used internally by `llm#log#latest_response()` for statusline |
| **Programmatic access** | `expand(g:llm_log_dir) . '/latest/response.md'` → the most recent response |
| **Condition** | Always created/updated |

**Creation flow**:
```vim
let l:latest = l:base . '/latest'
call system('ln -sfn ' . shellescape(l:dirname) . ' . shellescape(l:latest))
```

**Note**: This is a relative symlink (`ln -sfn dirname latest_path`) — it points to the dirname only, not a full path, making the log directory relocatable.

---

## Conditional Creation Summary

| Log File | info level | debug level | Condition |
|----------|:----------:|:-----------:|-----------|
| response.md | ✅ | ✅ | Always (any non-none level) |
| input.json | ❌ | ✅ | `g:llm_log_level ==# 'debug'` |
| tools.log | ⚠️ | ⚠️ | Only if LLM_OUTPUT temp file has content (often empty due to aichat override) |
| aichat.log | ❌ | ✅ | `g:llm_log_level ==# 'debug'` (requires AICHAT_LOG_PATH env var) |
| session.log | ✅ | ✅ | Always appended at completion |
| latest | ✅ | ✅ | Always updated at request start |

---

## Retrieval Command Matrix

| Command | File Accessed | Disk Path (expanded) | Requires Debug? |
|---------|--------------|----------------------|:---------------:|
| `:LLMLog` | response.md | `~/.local/share/vim-llm-assistant/logs/{request}/response.md` | No |
| `:LLMLog response` | response.md | (same) | No |
| `:LLMLog input` | input.json | `~/.local/share/vim-llm-assistant/logs/{request}/input.json` | ⚠️ File exists only at debug |
| `:LLMLog tools` | tools.log | `~/.local/share/vim-llm-assistant/logs/{request}/tools.log` | No (but often empty) |
| `:LLMLog aichat` | aichat.log | `~/.local/share/vim-llm-assistant/logs/{request}/aichat.log` | ⚠️ File exists only at debug |
| `:LLMLog session` | session.log | `~/.local/share/vim-llm-assistant/logs/session.log` | No |
| `:LLMLog dir` | directory | `~/.local/share/vim-llm-assistant/logs/` | No |
| `:LLMLogDir` | directory | `~/.local/share/vim-llm-assistant/logs/` | No |
| `:LLMLogTail` | response.md | `~/.local/share/vim-llm-assistant/logs/{request}/response.md` | No |
| `:LLMLogTail response` | response.md | (same) | No |
| `:LLMLogTail aichat` | aichat.log | `~/.local/share/vim-llm-assistant/logs/{request}/aichat.log` | ⚠️ File exists only at debug |
| `:LLMLogClean [N]` | all `{request}/` dirs | `~/.local/share/vim-llm-assistant/logs/YYYYMMDD_*` | No |

**`{request}`** = resolved via `s:resolve_request_dir()` → active request → last request → empty

---

## Request Directory Resolution (for all per-request files)

All per-request file access commands use `s:resolve_request_dir()` (`log.vim:52-85`):

```
Priority:
1. s:active_requests (list) — if 1 active, use it; if >1, prompt user
2. s:last_request_dir (string) — persists after completion, set at request start
3. '' (empty) — triggers "No log directories found" error message
```

This means:
- **During a running request**: Commands access the running request's log directory
- **After completion**: Commands access the most recently completed request's log directory
- **Multiple concurrent requests**: User is prompted to choose via `inputlist()`
- **No requests ever made this session**: Commands fail with informational message

---

## File Content Formats

### response.md
```markdown
<!-- vim-llm-assistant response log -->
<!-- Time: Wed Jun 11 09:21:08 2026 -->
<!-- Model: claude-3-7-sonnet-20250219 -->
<!-- Prompt: Analyze this function -->

The function appears to...
[full LLM response text, streamed line by line]
```

### input.json (debug only)
```json
{"llm_history":"...","buffers":[...],"active_buffer":{"filename":"...","contents":"..."},"prompt":"...","cursor_line":42,"cursor_col":1}
```

### tools.log
```
[raw tool output — format varies by tool]
true
{"result": "..."}
```

### aichat.log (debug only)
```
2026-06-11T09:21:05.044Z [DEBUG] aichat::client::bedrock: Request https://...
2026-06-11T09:21:08.315Z [DEBUG] aichat::client::bedrock: non-stream-data: {...}
2026-06-11T09:21:12.560Z [DEBUG] aichat::function: Creating per-call temporary file...
```

### session.log
```
2026-06-11 09:21:08 | claude-3-7-sonnet-20250219 | 17s | OK | Analyze this function and suggest improvements
2026-06-11 09:35:42 | claude-3-7-sonnet-20250219 | 4s | OK | What does this error mean?
2026-06-11 10:02:15 | gpt-4o | 12s | ERROR:1 | Refactor the auth module to use...
```

---

## Source Code References

| What | Where |
|------|-------|
| Per-request dir creation | `autoload/llm/log.vim:12-33` (`llm#log#create_request()`) |
| response.md path definition | `autoload/llm/log.vim:28` |
| input.json path definition | `autoload/llm/log.vim:27` |
| tools.log path definition | `autoload/llm/log.vim:29` |
| aichat.log path definition | `autoload/llm/log.vim:30` |
| latest symlink creation | `autoload/llm/log.vim:31-32` |
| session.log append | `autoload/llm/log.vim:36-38` |
| AICHAT_LOG_PATH env set | `autoload/llm/adapters/aichat.vim:165-167` |
| LLM_OUTPUT env set | `autoload/llm/adapters/aichat.vim:168` |
| response.md header write | `autoload/llm/adapters/aichat.vim:186-192` |
| response.md streaming write | `autoload/llm/adapters/aichat.vim:197` (out_cb) |
| tools.log persist | `autoload/llm/adapters/aichat.vim:319-321` |
| session.log entry format | `autoload/llm/adapters/aichat.vim:334-339` |
| input.json persist (debug) | `autoload/llm.vim:344-347` |
| Log level override (none→info) | `plugin/llm.vim:47-49` |
| g:llm_log_dir default | `plugin/llm.vim:38-39` |
