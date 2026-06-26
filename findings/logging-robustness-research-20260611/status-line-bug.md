# Status Line Bug Analysis

## Summary

The status line in vim-llm-assistant displays a **temp file path** (`LLM_OUTPUT`) that is misleading to users. It shows a randomly-named Vim temp file intended for aichat's internal tool output capture, not the actual LLM response stream. The actual LLM response only exists in memory (Vim job callbacks) and is never written to any file on disk during execution.

---

## What Is Displayed

**Function**: `s:show_status_message` in `autoload/llm/adapters/aichat.vim:12-40`

**Format shown to user**:
```
[LLM] Processing: 1. 12s /tmp/vXXXXXX/42
```

**Code that builds the display** (aichat.vim:30-31):
```vim
let l:temp = has_key(l:job_info, 'temp_file') ? l:job_info.temp_file : '?'
call add(l:blurbs, {'elapsed': l:elapsed, 'text': l:job_id . '. ' . l:elapsed . 's ' . l:temp})
```

The displayed path is `l:job_info.temp_file`, which is stored in `s:llm_jobs[id]`.

---

## What `temp_file` Actually Is

**Created at** `aichat.vim:110`:
```vim
let l:temp_file = tempname()
```

**Used as** environment variable for the aichat subprocess (aichat.vim:139):
```vim
let l:cmd_base = ['bash', '-c', l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ...']
```

**Purpose**: `LLM_OUTPUT` is an environment variable consumed by aichat's **tool system**. When aichat invokes tools (like `code_assistant`), those tools write their file output to `$LLM_OUTPUT`. It is **not** the main LLM response stream.

**Stored in job tracking** (aichat.vim:175-176):
```vim
let s:llm_jobs[string(l:job_id)] = {
      \ ...
      \ 'temp_file': l:temp_file
      \ }
```

**Deleted on completion** (aichat.vim:217):
```vim
call delete(a:temp_file)
```

---

## Where the Actual LLM Response Goes

The main LLM response (what the user actually wants to see) flows through an entirely different path:

1. **aichat process stdout** → captured by Vim's `out_cb` callback (aichat.vim:152):
   ```vim
   'out_cb': {channel, msg -> [add(l:output, msg), llm#debug('aichat.out_cb: Received ' . len(msg) . ' chars')]},
   ```

2. **Accumulated in memory** in the `l:output` list (a local variable in closure scope)

3. **On job exit** → `s:on_job_complete` joins the output (aichat.vim:222):
   ```vim
   let l:result = join(a:output, "\n")
   ```

4. **Passed to callback** → `OnLLMComplete` in `llm.vim` (defined ~line 370)

5. **Appended to `[LLM-Scratch]` buffer** → only then is it visible to the user

**Critical fact**: The LLM response is **never written to any file on disk** during execution. It only exists in Vim's internal memory until it's displayed in the scratch buffer after completion.

---

## What the User Expects vs. What They Get

| Aspect | User Expectation | Actual Reality |
|--------|-----------------|----------------|
| **Displayed path purpose** | "This is where the LLM output is being written — I can `tail -f` it" | It's the `LLM_OUTPUT` env var for aichat's tool system, not the response stream |
| **File contents during run** | Streaming LLM response text | Empty (if no tools run) OR aichat tool artifacts (unrelated to the response) |
| **File after completion** | Persists for later review | Deleted immediately by `call delete(a:temp_file)` |
| **Real-time observability** | Can watch output accumulate | Response only exists in Vim callback memory — no file to tail |
| **Log browsing** | Can browse past runs | No persistent logs exist at all |

---

## Root Cause

The bug has **three contributing causes**:

### 1. Conceptual Mismatch (Primary)
The status line displays `temp_file` because it's the only file-path available at runtime. But this path serves a completely different purpose (tool output capture via `LLM_OUTPUT` env var) than what the user naturally infers (LLM response output).

### 2. No Response Log File Exists
The architecture never writes the LLM response to any file during execution. It flows: aichat stdout → Vim callback buffer (memory) → scratch buffer (on completion). There is simply no tailable file for the response stream.

### 3. Ephemeral File Lifecycle  
Even if the user finds the displayed temp file, it:
- May be empty (no aichat tool writes to it in most requests)
- Contains tool artifacts, not the conversation response
- Gets deleted the instant the job completes

---

## Impact on User Experience

1. **Misleading information**: The status line implies the path is useful/actionable when it's not
2. **Impossible to tail**: Users cannot `tail -f` anything to watch the LLM response stream
3. **No post-hoc logs**: After completion, there's no way to review raw LLM input/output
4. **Confusion about aichat internals**: Users may investigate the temp file and find unexpected tool artifacts or nothing at all

---

## Affected Code Locations

| File | Lines | What |
|------|-------|------|
| `autoload/llm/adapters/aichat.vim` | 12-40 | `s:show_status_message` — displays the misleading temp_file path |
| `autoload/llm/adapters/aichat.vim` | 110 | `tempname()` — creates the LLM_OUTPUT temp file |
| `autoload/llm/adapters/aichat.vim` | 139 | Sets `LLM_OUTPUT=` env var for aichat subprocess |
| `autoload/llm/adapters/aichat.vim` | 175-176 | Stores `temp_file` in `s:llm_jobs` dict |
| `autoload/llm/adapters/aichat.vim` | 152 | `out_cb` — where the ACTUAL response goes (to memory) |
| `autoload/llm/adapters/aichat.vim` | 217 | `call delete(a:temp_file)` — deletes the file on completion |
| `autoload/llm.vim` | ~357 | SEPARATE `tempname()` for JSON input file (also deleted) |

---

## Recommendations

1. **Fix the status line** to show a meaningful, tailable log file path (not the `LLM_OUTPUT` temp file)
2. **Create a persistent log file** that streams the LLM response as it arrives via `out_cb`
3. **Use a known log directory** (e.g., `~/.vim/vim-llm-assistant/logs/`) with timestamped or numbered files
4. **Keep the `LLM_OUTPUT` mechanism** for tool output capture (it serves its own purpose) but don't expose it to users
5. **Consider a `:LLMLog` command** that opens the most recent (or specified) log file for review
