# Temp File Lifecycle Analysis

## Investigation Summary

Traced every `tempname()` call in the vim-llm-assistant plugin to document the full lifecycle of temporary files — from creation through usage to deletion. The plugin creates **3 distinct temp files** across two source files, serving two different purposes.

## Temp File Inventory

| # | Purpose | Creation Point | What's Written To It | Deletion Point | Variable Name |
|---|---------|---------------|---------------------|----------------|---------------|
| 1 | **Input JSON** (context payload) | `autoload/llm.vim:634` | JSON object with `llm_history`, `buffers`, `active_buffer`, `file_arguments`, `prompt`, `cursor_line`, `cursor_col` | `autoload/llm.vim:671` (in `OnLLMComplete` closure) | `l:tempfile` |
| 2 | **LLM_OUTPUT** (tool output capture, async mode) | `autoload/llm/adapters/aichat.vim:121` | Output from aichat's tool invocations (whatever tools write via the `LLM_OUTPUT` env var) | `autoload/llm/adapters/aichat.vim:281` (in `s:on_job_complete`) | `l:temp_file` |
| 3 | **LLM_OUTPUT** (tool output capture, sync mode) | `autoload/llm/adapters/aichat.vim:213` | Same as #2 — tool output via `LLM_OUTPUT` env var | `autoload/llm/adapters/aichat.vim:255` (immediately after `system()` returns) | `l:temp_file` |

## Detailed Lifecycle for Each Temp File

### Temp File #1: Input JSON Context Payload

**File**: `autoload/llm.vim`  
**Function**: `llm#run()`

```
Creation:    line 634  →  let l:tempfile = tempname()
Write:       line 635  →  call writefile(split(l:json_data, "\n"), l:tempfile)
Passed to:   line 678  →  call llm#process_async(l:tempfile, l:prompt, l:model, function('OnLLMComplete'))
Used as:     aichat CLI arg: `--file <tempfile>` (the input data fed to the LLM)
Deletion:    line 671  →  call delete(l:tempfile)  [inside OnLLMComplete closure]
```

**Lifecycle flow**:
1. `llm#run()` gathers all context (buffers, cursor, history, prompt)
2. Encodes it as JSON with deterministic key ordering (for prompt cache stability)
3. Writes JSON to temp file
4. Passes temp file path to `llm#process_async()` → adapter's `process_async()`
5. Adapter reads the file to extract `file_arguments`, then passes it to aichat as `--file` arg
6. After aichat completes and callback fires, `OnLLMComplete` deletes the file

**Content example** (conceptual):
```json
{
  "llm_history": "...",
  "buffers": [{"filename": "foo.py", "contents": "..."}],
  "active_buffer": {"filename": "bar.py", "contents": "..."},
  "file_arguments": ["/path/to/file1"],
  "prompt": "Fix this bug",
  "cursor_line": 42,
  "cursor_col": 10
}
```

### Temp File #2: LLM_OUTPUT (Async Mode — Tool Output)

**File**: `autoload/llm/adapters/aichat.vim`  
**Function**: `s:aichat_adapter.process_async()`

```
Creation:    line 121  →  let l:temp_file = tempname()
Passed to:   line 152  →  Used in command: 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat ...'
Stored in:   line 184  →  s:llm_jobs[string(l:job_id)].temp_file = l:temp_file
Displayed:   line 27   →  s:show_status_message reads l:job_info.temp_file for status line
Deletion:    line 281  →  call delete(a:temp_file)  [inside s:on_job_complete]
```

**Lifecycle flow**:
1. `process_async()` creates a temp file path (file does NOT exist yet at this point)
2. Path is set as the `LLM_OUTPUT` environment variable in the bash command
3. Path is stored in `s:llm_jobs` dict for status line display
4. `s:show_status_message()` timer (fires every 2000ms) reads this path and displays it in `echo`
5. During execution, aichat's **tools** (not the LLM response itself) may write to this file
6. When aichat exits, `s:on_job_complete()` deletes the file

**Critical insight**: The actual LLM response goes through **stdout** (captured by `out_cb` into `l:output` list). The `LLM_OUTPUT` file only receives tool-generated output. If no tools are invoked, this file may never be written to at all.

### Temp File #3: LLM_OUTPUT (Sync Mode — Tool Output)

**File**: `autoload/llm/adapters/aichat.vim`  
**Function**: `s:aichat_adapter.process()`

```
Creation:    line 213  →  let l:temp_file = tempname()
Passed to:   line 246  →  Used in command: 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat ...'
NOT tracked: (sync mode doesn't register in s:llm_jobs)
Deletion:    line 255  →  if filereadable(l:temp_file) call delete(l:temp_file) endif
```

**Lifecycle flow**:
1. Same as #2 but synchronous
2. `system()` blocks until aichat finishes
3. File is deleted immediately after `system()` returns
4. Return value is `l:aichat_response` (stdout from aichat)

## Status Line Display Mechanism

The status line timer (`s:show_status_message`, line 12-37) fires every 2 seconds and builds a message like:

```
[LLM] Processing: 1. 5s /tmp/vXXXXXX/YYYYY
```

Where `/tmp/vXXXXXX/YYYYY` is the `LLM_OUTPUT` temp file path (Temp File #2).

**What the user sees**: A path to a file that may be empty or only contain tool output.  
**What the user probably wants**: A way to see the actual LLM response stream, or a persistent log they can tail.

## Key Findings

1. **No persistent log files exist** — All temp files are deleted on completion. There is no way to review past LLM interactions except through the `[LLM-Scratch]` buffer.

2. **The status line path is misleading** — It shows the `LLM_OUTPUT` file (tool output capture), not the LLM response. The actual response flows through vim's `out_cb`/`err_cb` callbacks into memory (the `l:output` list) and is never written to a file the user can tail.

3. **LLM_OUTPUT may never be written to** — If aichat doesn't invoke any tools during a request, this file is never created by aichat; only the empty path exists. The `tempname()` call creates a *path* but not the file itself.

4. **Three temp files are created per async request** — Input JSON + LLM_OUTPUT (both deleted on completion). For sync mode it's Input JSON + LLM_OUTPUT (both deleted immediately).

5. **No way to tail real-time output** — The actual streaming response is captured in-memory via callbacks. There's no file a user can `tail -f` to watch the LLM response in real time.

6. **Cleanup is reliable** — Both async and sync paths properly delete their temp files. The async path handles this in `s:on_job_complete` which is triggered by `exit_cb`. No temp file leaks were found in the normal execution paths.

## Data Flow Diagram

```
llm#run()
  │
  ├── Creates INPUT JSON temp file (l:tempfile)
  │     └── Contains: full context payload
  │
  └── Calls llm#process_async(l:tempfile, ...)
        │
        └── adapter.process_async(json_filename, ...)
              │
              ├── Creates LLM_OUTPUT temp file (l:temp_file)
              │     └── Set as LLM_OUTPUT env var for aichat
              │
              ├── Stores l:temp_file in s:llm_jobs[id].temp_file
              │     └── Read by s:show_status_message timer (displayed to user)
              │
              ├── Starts aichat job with:
              │     ├── --file <INPUT JSON>   (reads context)
              │     └── LLM_OUTPUT=<path>     (tools write here)
              │
              ├── stdout → out_cb → l:output list (actual LLM response)
              ├── stderr → err_cb → l:output list (errors)
              │
              └── exit_cb → s:on_job_complete()
                    ├── Deletes LLM_OUTPUT temp file
                    ├── Joins l:output → passes to callback
                    └── callback (OnLLMComplete) deletes INPUT JSON temp file
```

## Recommendations for Next Steps

- **Task 2 (status line bug)**: The root cause is clear — `s:show_status_message` displays `s:llm_jobs[id].temp_file` which is the LLM_OUTPUT file, not a useful log file.
- **Task 3 (aichat logging)**: Investigate what `LLM_OUTPUT` env var actually means to aichat tools and whether aichat itself has logging flags.
- **Task 5 (improvement plan)**: Consider creating a persistent `~/.vim/vim-llm-assistant/logs/` directory with named files that persist across runs and can be tailed.
