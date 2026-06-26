# Comprehensive Logging Improvement Plan for vim-llm-assistant

## Executive Summary

The plugin's current logging has three fundamental problems:
1. **Misleading status line** — shows an `LLM_OUTPUT` temp file (tool output pipe) instead of a useful log path
2. **No persistent response logs** — the actual LLM response only exists in memory (callbacks) and is never written to disk
3. **No user-facing log management** — no commands to browse, tail, or manage logs

This plan proposes specific code changes to implement robust, multi-file logging with real-time tail capability, persistent log browsing, and a `latest` symlink for zero-friction access.

---

## Evidence Base (Tasks 1–4 Synthesis)

| Source | Key Finding |
|--------|-------------|
| Task 1 (temp-file-lifecycle.md) | Three temp files per request: input JSON (llm.vim:634), async LLM_OUTPUT (aichat.vim:121), sync LLM_OUTPUT (aichat.vim:213) — all deleted on completion |
| Task 2 (status-line-bug.md) | `s:show_status_message` (aichat.vim:30) displays `s:llm_jobs[id].temp_file` — the LLM_OUTPUT tool pipe, not the LLM response stream |
| Task 3 (aichat-logging-behavior.md) | `AICHAT_LOG_PATH` controls aichat's debug log; `LLM_OUTPUT` is consumed by per-tool-call temp files that OVERRIDE the passed-in value; real LLM response goes through stdout→out_cb |
| Task 4 (logging-best-practices.md) | Per-request subdirectories with `latest` symlink; session.log audit trail; `.md` extension for response; count+age based cleanup; reference patterns from copilot.vim (`:Copilot log`), coc.nvim (`:CocOpenLog`), vim-lsp (`g:lsp_log_file`) |

---

## Architecture: Current vs. Proposed

### Current Data Flow
```
llm#run()
  ├─ tempname() → input JSON [written at llm.vim:635, deleted at llm.vim:671]
  └─ adapter.process_async()
       ├─ tempname() → LLM_OUTPUT env var [created aichat.vim:121, deleted aichat.vim:281]
       ├─ aichat stdout → out_cb → l:output list [IN MEMORY ONLY]
       └─ exit_cb → s:on_job_complete → callback → [LLM-Scratch] buffer

Status line shows: /tmp/vXXXXXX/N  (LLM_OUTPUT temp path — misleading, often empty)
```

### Proposed Data Flow
```
llm#run()
  ├─ log_dir/{request_dir}/input.json [PERSISTED — the full context payload]
  └─ adapter.process_async()
       ├─ tempname() → LLM_OUTPUT [still needed for aichat tool system, still deleted]
       ├─ aichat stdout → out_cb → BOTH l:output list AND log_dir/{request_dir}/response.md
       ├─ AICHAT_LOG_PATH → log_dir/{request_dir}/aichat.log [set by plugin internally]
       └─ exit_cb → s:on_job_complete → append to session.log

Status line shows: ~/.local/share/vim-llm-assistant/logs/latest/response.md  (tail-able!)
Symlink:          latest → 20240611_103000_001/
```

---

## Proposed Directory Structure

```
~/.local/share/vim-llm-assistant/logs/    # g:llm_log_dir (XDG-compliant default)
├── session.log                            # Append-only audit trail
├── latest -> 20240611_103215_002/         # Symlink to most recent request dir
├── 20240611_103000_001/                   # Per-request directory: YYYYMMDD_HHMMSS_SEQ
│   ├── input.json                         # Full context payload (what was sent to aichat)
│   ├── response.md                        # LLM response stream (tail-able, .md for highlighting)
│   ├── tools.log                          # Tool output via LLM_OUTPUT (may be empty)
│   └── aichat.log                         # Aichat debug log (only if g:llm_log_level = 'debug')
├── 20240611_103215_002/
│   ├── input.json
│   ├── response.md
│   ├── tools.log
│   └── aichat.log
└── ...
```

### Why Per-Request Directories?

1. **Clean file names** — `response.md` vs `2024-06-11_103000_response.md` (no repeated timestamps)
2. **Easy browsing** — everything from one request is grouped together
3. **`latest` symlink** — enables stable path: `tail -f ~/.local/share/vim-llm-assistant/logs/latest/response.md`
4. **Natural cleanup** — delete an entire directory to remove one request's logs
5. **Reference precedent** — similar to coc.nvim's per-session directory, copilot.vim's stable log path

---

## Implementation Plan

### Phase 1: Log Infrastructure (Foundation)

#### 1.1 New Configuration Variables

**File**: `plugin/llm.vim` (insert after line 30, after `g:llm_use_async`)

```vim
" Persistent log directory (XDG data home compliant)
if !exists('g:llm_log_dir')
  let g:llm_log_dir = expand('~/.local/share/vim-llm-assistant/logs')
endif

" Log level: 'none' (current behavior), 'info' (response + session), 'debug' (+ input + aichat)
if !exists('g:llm_log_level')
  let g:llm_log_level = 'info'
endif

" Cleanup: max log directories to keep (0 = unlimited)
if !exists('g:llm_log_keep_count')
  let g:llm_log_keep_count = 100
endif

" Cleanup: max log age in days (0 = keep forever)
if !exists('g:llm_log_max_age_days')
  let g:llm_log_max_age_days = 30
endif
```

#### 1.2 Log Directory Management Functions

**File**: `autoload/llm/log.vim` (NEW FILE — keeps logging concerns separated)

```vim
" Ensure log directory exists
function! llm#log#dir() abort
  let l:dir = expand(g:llm_log_dir)
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

" Create a new per-request log directory and return paths dict
" Returns: {'dir': path, 'input': path, 'response': path, 'tools': path, 'aichat': path}
function! llm#log#create_request() abort
  let l:base = llm#log#dir()
  let l:timestamp = strftime('%Y%m%d_%H%M%S')
  
  " Find next sequence number for this second
  let l:seq = 1
  while isdirectory(l:base . '/' . l:timestamp . '_' . printf('%03d', l:seq))
    let l:seq += 1
  endwhile
  
  let l:dirname = l:timestamp . '_' . printf('%03d', l:seq)
  let l:dir = l:base . '/' . l:dirname
  call mkdir(l:dir, 'p')
  
  " Update 'latest' symlink (atomic via rename)
  let l:latest = l:base . '/latest'
  if filereadable(l:latest) || isdirectory(l:latest)
    call delete(l:latest)
  endif
  " Use system() for symlink since Vim has no native symlink function
  call system('ln -sfn ' . shellescape(l:dirname) . ' ' . shellescape(l:latest))
  
  return {
        \ 'dir': l:dir,
        \ 'input': l:dir . '/input.json',
        \ 'response': l:dir . '/response.md',
        \ 'tools': l:dir . '/tools.log',
        \ 'aichat': l:dir . '/aichat.log',
        \ 'dirname': l:dirname
        \ }
endfunction

" Append a line to session.log
function! llm#log#session_append(entry) abort
  let l:logfile = llm#log#dir() . '/session.log'
  call writefile([a:entry], l:logfile, 'a')
endfunction

" Get the path to the latest response log (for status line)
function! llm#log#latest_response() abort
  let l:latest = expand(g:llm_log_dir) . '/latest/response.md'
  return l:latest
endfunction
```

#### 1.3 Module-Level State for Log Path Propagation

**File**: `autoload/llm.vim` (add near top, after `llm#debug` function ~line 6)

```vim
" Current request's log paths (set in llm#run, read by adapters)
let s:current_log_paths = {}

function! llm#get_current_log_paths() abort
  return s:current_log_paths
endfunction
```

This avoids breaking the `process_async()` function signature, which matters for adapter interface compatibility.

---

### Phase 2: Fix the Status Line (Solves the Reported Bug)

#### 2.1 Store the Correct Log Path in Job Tracking

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Line ~192-198 (where `s:llm_jobs` dict is populated)

```vim
" CURRENT (line 192-198):
let s:llm_jobs[string(l:job_id)] = {
      \ 'job': l:job,
      \ 'timer_id': l:timer_id,
      \ 'prompt': a:prompt,
      \ 'model': l:model,
      \ 'start_time': localtime(),
      \ 'temp_file': l:temp_file
      \ }

" PROPOSED:
let s:llm_jobs[string(l:job_id)] = {
      \ 'job': l:job,
      \ 'timer_id': l:timer_id,
      \ 'prompt': a:prompt,
      \ 'model': l:model,
      \ 'start_time': localtime(),
      \ 'temp_file': l:temp_file,
      \ 'log_file': l:log_paths.response,
      \ 'log_paths': l:log_paths
      \ }
```

#### 2.2 Update Status Line Display

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Line 30 (inside `s:show_status_message`)

```vim
" CURRENT (line 30):
let l:temp = has_key(l:job_info, 'temp_file') ? l:job_info.temp_file : '?'

" PROPOSED (backward-compatible fallback):
let l:temp = has_key(l:job_info, 'log_file') ? l:job_info.log_file
      \ : (has_key(l:job_info, 'temp_file') ? l:job_info.temp_file : '?')
```

**Result**: Status line now shows `~/.local/share/vim-llm-assistant/logs/20240611_103000_001/response.md` — a file the user can immediately `tail -f`.

---

### Phase 3: Persistent Response Logging (Real-Time Tail)

#### 3.1 Write Response Stream to Disk via out_cb

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Line ~167 (the `out_cb` callback in `process_async`)

```vim
" CURRENT (line 167):
'out_cb': {channel, msg -> [add(l:output, msg), llm#debug('aichat.out_cb: Received ' . len(msg) . ' chars')]},

" PROPOSED (tee to disk):
'out_cb': {channel, msg -> [
      \ add(l:output, msg),
      \ writefile([msg], l:log_paths.response, 'a'),
      \ llm#debug('aichat.out_cb: Received ' . len(msg) . ' chars')
      \ ]},
```

The `'a'` flag in `writefile()` appends atomically. Each line flushes immediately, making the file tail-able from the first token. This is the **single most impactful change** in the entire plan.

#### 3.2 Write Response Header Before Job Start

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Before `job_start()` call (after log_paths is obtained, ~line 160)

```vim
" Write header to response log for context when tailing
if g:llm_log_level !=# 'none'
  call writefile([
        \ '<!-- vim-llm-assistant response log -->',
        \ '<!-- Time: ' . strftime('%c') . ' -->',
        \ '<!-- Model: ' . l:model . ' -->',
        \ '<!-- Prompt: ' . a:prompt . ' -->',
        \ '',
        \ ], l:log_paths.response)
endif
```

#### 3.3 Persist Input JSON (Instead of Deleting)

**File**: `autoload/llm.vim`  
**Location**: Line ~634-635 (in `llm#run()`)

```vim
" CURRENT (line 634-635):
let l:tempfile = tempname()
call writefile(split(l:json_data, "\n"), l:tempfile)

" PROPOSED:
let s:current_log_paths = (g:llm_log_level !=# 'none') ? llm#log#create_request() : {}
let l:tempfile = !empty(s:current_log_paths) && g:llm_log_level ==# 'debug'
      \ ? s:current_log_paths.input
      \ : tempname()
call writefile(split(l:json_data, "\n"), l:tempfile)
```

And modify the deletion in `OnLLMComplete`:

**Location**: Line ~671 (inside `OnLLMComplete` closure)

```vim
" CURRENT (line 671):
call delete(l:tempfile)

" PROPOSED:
if g:llm_log_level ==# 'debug' && !empty(s:current_log_paths)
  " Input JSON is already at its final log path — don't delete
else
  call delete(l:tempfile)
  " If info-level logging, still copy the tempfile content to log dir
  if g:llm_log_level ==# 'info' && !empty(s:current_log_paths)
    " Don't persist input at info level (can be large, 100KB+)
  endif
endif
```

#### 3.4 Set AICHAT_LOG_PATH Internally

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Line 151 (command construction)

```vim
" CURRENT (line 151):
let l:cmd_base = ['bash', '-c', l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename)]

" PROPOSED (add AICHAT_LOG_PATH when debug-level logging):
let l:aichat_log_env = ''
if g:llm_log_level ==# 'debug' && has_key(l:log_paths, 'aichat')
  let l:aichat_log_env = 'AICHAT_LOG_PATH=' . shellescape(l:log_paths.aichat) . ' AICHAT_LOG_LEVEL=debug '
endif
let l:cmd_base = ['bash', '-c', l:cmd_extra . l:aichat_log_env . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename)]
```

#### 3.5 Append Tool Output to Log (Preserve LLM_OUTPUT Content)

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Inside `s:on_job_complete` (~line 267-281), before deleting `a:temp_file`

```vim
" Before deleting the tool output file, copy its content to the log dir
if filereadable(a:temp_file) && getfsize(a:temp_file) > 0
  let l:job_info = get(s:llm_jobs, string(a:job_id), {})
  if has_key(l:job_info, 'log_paths') && g:llm_log_level !=# 'none'
    call writefile(readfile(a:temp_file), l:job_info.log_paths.tools)
  endif
endif
call delete(a:temp_file)  " Still delete the temp file
```

#### 3.6 Session Log Entry on Completion

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Inside `s:on_job_complete`, after the callback fires

```vim
" Append to session.log
if g:llm_log_level !=# 'none'
  let l:duration = localtime() - l:job_info.start_time
  let l:entry = strftime('%Y-%m-%d %H:%M:%S') . ' | '
        \ . l:job_info.model . ' | '
        \ . l:duration . 's | '
        \ . (a:status == 0 ? 'OK' : 'ERROR:' . a:status) . ' | '
        \ . l:job_info.prompt[:80]
  call llm#log#session_append(l:entry)
endif
```

---

### Phase 4: User-Facing Commands

#### 4.1 Command Definitions

**File**: `plugin/llm.vim` (append after line 61, after `ListLLMJobs`)

```vim
" Log management commands
command! -nargs=? -complete=customlist,llm#log#complete_types LLMLog call llm#log#open(<q-args>)
command! LLMLogDir call llm#log#browse()
command! -nargs=? LLMLogTail call llm#log#tail(<q-args>)
command! -nargs=? LLMLogClean call llm#log#clean(<q-args>)
```

#### 4.2 Command Implementations

**File**: `autoload/llm/log.vim` (append to the new file from Phase 1.2)

```vim
" Complete function for log types
function! llm#log#complete_types(arglead, cmdline, cursorpos) abort
  return filter(['response', 'input', 'tools', 'aichat', 'session', 'dir'], 'v:val =~ "^" . a:arglead')
endfunction

" Open the most recent log file of a given type
" Usage: :LLMLog [response|input|tools|aichat|session]
function! llm#log#open(type) abort
  let l:type = empty(a:type) ? 'response' : a:type
  
  if l:type ==# 'session'
    let l:file = llm#log#dir() . '/session.log'
    if !filereadable(l:file)
      echom '[LLM] No session.log found'
      return
    endif
    execute 'vsplit ' . fnameescape(l:file)
    normal! G
    return
  endif
  
  if l:type ==# 'dir'
    call llm#log#browse()
    return
  endif
  
  " Find latest request directory
  let l:latest_dir = expand(g:llm_log_dir) . '/latest'
  if !isdirectory(l:latest_dir)
    echom '[LLM] No log directories found in ' . g:llm_log_dir
    return
  endif
  
  " Map type to filename
  let l:filemap = {'response': 'response.md', 'input': 'input.json', 'tools': 'tools.log', 'aichat': 'aichat.log'}
  let l:filename = get(l:filemap, l:type, 'response.md')
  let l:file = l:latest_dir . '/' . l:filename
  
  if !filereadable(l:file)
    echom '[LLM] File not found: ' . l:file
    return
  endif
  
  execute 'vsplit ' . fnameescape(l:file)
  normal! G
endfunction

" Browse the log directory in netrw
function! llm#log#browse() abort
  let l:dir = llm#log#dir()
  execute 'edit ' . fnameescape(l:dir)
endfunction

" Tail the current/latest response log in a terminal split
" Usage: :LLMLogTail [response|aichat]
function! llm#log#tail(type) abort
  let l:type = empty(a:type) ? 'response' : a:type
  let l:filemap = {'response': 'response.md', 'aichat': 'aichat.log'}
  let l:filename = get(l:filemap, l:type, 'response.md')
  
  let l:latest = expand(g:llm_log_dir) . '/latest/' . l:filename
  
  if !filereadable(l:latest)
    " Try using the symlink even if file doesn't exist yet (tail -f will wait)
    let l:latest = expand(g:llm_log_dir) . '/latest/' . l:filename
  endif
  
  " Use Vim's built-in terminal for tail (works in Vim 8.1+)
  if has('terminal')
    execute 'botright terminal ++close tail -f ' . shellescape(l:latest)
    wincmd p  " Return focus to previous window
    echom '[LLM] Tailing ' . l:latest . ' (close terminal to stop)'
  else
    " Fallback: open file with autoread
    call llm#log#open(l:type)
    setlocal autoread
    let b:llm_tail_timer = timer_start(1000, {-> execute('checktime')}, {'repeat': -1})
    augroup LLMTail
      autocmd! * <buffer>
      autocmd FileChangedShellPost <buffer> normal! G
      autocmd BufWinLeave <buffer> call timer_stop(b:llm_tail_timer)
    augroup END
    echom '[LLM] Tailing ' . l:type . ' log (auto-refreshing, close buffer to stop)'
  endif
endfunction

" Clean old log directories
" Usage: :LLMLogClean [days]  — removes dirs older than N days
function! llm#log#clean(days) abort
  let l:days = empty(a:days) ? g:llm_log_max_age_days : str2nr(a:days)
  let l:dir = llm#log#dir()
  let l:removed = 0
  
  " Get all request directories (match YYYYMMDD_HHMMSS_NNN pattern)
  let l:dirs = glob(l:dir . '/[0-9]*_[0-9]*_[0-9]*', 0, 1)
  
  " Apply count-based limit first
  if g:llm_log_keep_count > 0 && len(l:dirs) > g:llm_log_keep_count
    call sort(l:dirs)
    let l:excess = l:dirs[:len(l:dirs) - g:llm_log_keep_count - 1]
    for l:d in l:excess
      call delete(l:d, 'rf')
      let l:removed += 1
    endfor
    let l:dirs = l:dirs[len(l:excess):]
  endif
  
  " Apply age-based limit
  if l:days > 0
    let l:cutoff = localtime() - (l:days * 86400)
    for l:d in l:dirs
      if getftime(l:d) < l:cutoff
        call delete(l:d, 'rf')
        let l:removed += 1
      endif
    endfor
  endif
  
  echom '[LLM] Cleaned ' . l:removed . ' log directories'
endfunction

" Startup cleanup (called at VimEnter via timer for non-blocking behavior)
function! llm#log#startup_cleanup() abort
  if g:llm_log_level ==# 'none'
    return
  endif
  call llm#log#clean('')
endfunction
```

#### 4.3 Auto-Cleanup at Startup

**File**: `plugin/llm.vim` (append at end)

```vim
" Run log cleanup at startup (non-blocking)
if exists('g:llm_log_level') && g:llm_log_level !=# 'none'
  autocmd VimEnter * call timer_start(0, {-> llm#log#startup_cleanup()})
endif
```

---

### Phase 5: Adapter Integration (Plumbing)

#### 5.1 Obtain Log Paths in process_async

**File**: `autoload/llm/adapters/aichat.vim`  
**Location**: Inside `s:aichat_adapter.process_async()`, after `let l:temp_file = tempname()` (line ~121)

```vim
" After line 121 (let l:temp_file = tempname()):
let l:log_paths = llm#get_current_log_paths()
```

This retrieves the log paths set by `llm#run()` in Phase 3.3 without modifying the function signature.

#### 5.2 Guard All Logging Behind Level Check

Every disk write operation should be guarded:

```vim
" Pattern used throughout:
if g:llm_log_level !=# 'none' && !empty(l:log_paths)
  " ... perform logging operation ...
endif
```

This ensures `g:llm_log_level = 'none'` restores exact current behavior with zero overhead.

---

## Summary of Changes Per File

### `plugin/llm.vim` (76 lines currently)

| Location | Change |
|----------|--------|
| After line 30 | Add `g:llm_log_dir`, `g:llm_log_level`, `g:llm_log_keep_count`, `g:llm_log_max_age_days` |
| After line 61 | Add `LLMLog`, `LLMLogDir`, `LLMLogTail`, `LLMLogClean` command definitions |
| End of file | Add VimEnter autocmd for startup cleanup |

### `autoload/llm.vim` (915 lines currently)

| Location | Change |
|----------|--------|
| After line ~6 | Add `s:current_log_paths` variable and `llm#get_current_log_paths()` accessor |
| Line ~634 | Set `s:current_log_paths` via `llm#log#create_request()` before creating tempfile |
| Line ~635 | Conditionally use `s:current_log_paths.input` instead of `tempname()` (debug level) |
| Line ~671 | Conditionally skip `delete(l:tempfile)` when logging at debug level |

### `autoload/llm/adapters/aichat.vim` (312 lines currently)

| Location | Change |
|----------|--------|
| Line 30 | Status line: prefer `log_file` over `temp_file` |
| After line ~121 | Get `l:log_paths = llm#get_current_log_paths()` |
| Before `job_start()` (~line 160) | Write response header to `l:log_paths.response` |
| Line 151 | Add `AICHAT_LOG_PATH=` to command (debug level) |
| Line 167 (`out_cb`) | Add `writefile([msg], l:log_paths.response, 'a')` for response tee |
| Lines 192-198 | Add `'log_file'` and `'log_paths'` keys to `s:llm_jobs` dict |
| Inside `s:on_job_complete` (~line 270) | Copy tool output to `log_paths.tools` before deleting temp |
| Inside `s:on_job_complete` (after callback) | Append entry to session.log |

### `autoload/llm/log.vim` (NEW FILE)

| Content |
|---------|
| `llm#log#dir()` — ensure log directory exists |
| `llm#log#create_request()` — create per-request dir + update `latest` symlink |
| `llm#log#session_append()` — append to session.log |
| `llm#log#latest_response()` — get stable latest response path |
| `llm#log#open()` — open log by type (`:LLMLog`) |
| `llm#log#browse()` — open log dir (`:LLMLogDir`) |
| `llm#log#tail()` — terminal tail (`:LLMLogTail`) |
| `llm#log#clean()` — cleanup old logs (`:LLMLogClean`) |
| `llm#log#startup_cleanup()` — VimEnter cleanup |
| `llm#log#complete_types()` — command-line completion |

---

## Configuration Options Summary

| Variable | Default | Description |
|----------|---------|-------------|
| `g:llm_log_dir` | `~/.local/share/vim-llm-assistant/logs` | Persistent log base directory |
| `g:llm_log_level` | `'info'` | `'none'` (current behavior), `'info'` (response+session), `'debug'` (+input+aichat) |
| `g:llm_log_keep_count` | `100` | Max request directories to retain (0=unlimited) |
| `g:llm_log_max_age_days` | `30` | Auto-cleanup threshold in days (0=keep forever) |

### Log Level Behaviors

| Level | Response File | Input JSON | Aichat Debug Log | Session Log | Tool Output |
|-------|--------------|-----------|-----------------|-------------|-------------|
| `none` | ✗ | ✗ (deleted) | ✗ | ✗ | ✗ (deleted) |
| `info` | ✓ (written via out_cb) | ✗ (deleted) | ✗ (not set) | ✓ | ✓ (if non-empty) |
| `debug` | ✓ (written via out_cb) | ✓ (persisted) | ✓ (AICHAT_LOG_PATH set) | ✓ | ✓ (if non-empty) |

---

## New User-Facing Commands

| Command | Description | Example |
|---------|-------------|---------|
| `:LLMLog [type]` | Open latest log in vsplit. Types: `response` (default), `input`, `tools`, `aichat`, `session` | `:LLMLog response` |
| `:LLMLogDir` | Browse log directory in netrw | `:LLMLogDir` |
| `:LLMLogTail [type]` | Open terminal split with `tail -f` on latest log | `:LLMLogTail` |
| `:LLMLogClean [days]` | Remove log dirs older than N days (or apply count limit) | `:LLMLogClean 7` |

### Real-Time Monitoring Patterns

| Method | Command | Pros | Cons |
|--------|---------|------|------|
| External terminal | `tail -f ~/.local/share/vim-llm-assistant/logs/latest/response.md` | Zero Vim overhead, always works | Requires separate terminal |
| Vim terminal split | `:LLMLogTail` | Stays in Vim, one command | Uses a buffer slot |
| Copy from status line | Copy displayed path, paste into `tail -f` | No plugin knowledge needed | Manual |

The `latest` symlink is the key enabler — it provides a **stable path** that users can bookmark in their terminal, add to tmux panes, or wire into other tools without needing to know the current timestamp.

---

## Migration & Backward Compatibility

1. **Default `info` level** — users get logging immediately with no config changes
2. **`g:llm_log_level = 'none'`** — restores exact current behavior (all temp files deleted, no persistent logs)
3. **`g:llm_adapter_cmd_extra`** — existing external `AICHAT_LOG_PATH` setup continues to work. The plugin only sets it when `g:llm_log_level = 'debug'` AND no external value is already set
4. **Status line fallback** — if `log_file` key is missing from job dict (e.g., during transition), falls back to existing `temp_file` behavior
5. **No signature changes** — uses module-level state (`s:current_log_paths`) to pass log paths to adapters, preserving the adapter interface contract

---

## Implementation Priority (Recommended Merge Order)

| Order | Phase | Impact | Effort | Description |
|-------|-------|--------|--------|-------------|
| 1 | Phase 1 + 5 | Foundation | Medium | Log infrastructure + plumbing (no visible change yet) |
| 2 | Phase 2 | **HIGH** | Low | Fix status line — immediately solves the reported bug |
| 3 | Phase 3 | **HIGH** | Medium | Persistent response logging — enables real-time tail |
| 4 | Phase 4 | Medium | Medium | User-facing commands — polish and discoverability |

Phases 1+5 must come first as they provide the foundation. Phase 2 is the quickest win for user impact. Phase 3 is the core value-add. Phase 4 is polish.

**Minimum viable fix** (could be a single PR): Phase 2 alone — change status line to show `AICHAT_LOG_PATH` (which already exists externally). This requires only changing line 30 of aichat.vim to show the existing aichat debug log path instead of the LLM_OUTPUT temp path. However, the full plan provides much more value.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Disk space from persistent logs | Low | Count+age cleanup, `g:llm_log_level='none'` escape hatch |
| Performance of `writefile()` in `out_cb` | Low | `writefile([msg], path, 'a')` is atomic single-line append; negligible vs network latency |
| Breaking adapter interface | Low | Module-level state avoids signature changes |
| Large input JSON files (100KB+) | Medium | Only persist at `debug` level; `info` level skips input |
| Race condition with external `AICHAT_LOG_PATH` | Low | Plugin only sets it when `debug` level; external setting takes precedence via cmd_extra prepend order |
| `latest` symlink on Windows | Medium | Use conditional: only create symlink on Unix; on Windows, store path in a `latest.txt` file |
| Cleanup deletes user-wanted logs | Low | Conservative defaults (30 days, 100 count); `:LLMLogClean` is explicit |

---

## Testing Plan

1. **Status line fix** (Phase 2): Run `:LLM test prompt` → verify status line shows `~/.local/share/vim-llm-assistant/logs/YYYYMMDD_HHMMSS_001/response.md`
2. **Tail capability** (Phase 3): Run `:LLMLogTail` during active job → verify file updates line-by-line in terminal split
3. **External tail** (Phase 3): Run `tail -f ~/.local/share/vim-llm-assistant/logs/latest/response.md` in external terminal → verify real-time output
4. **Persistence** (Phase 3): After job completes, verify `response.md` exists with full LLM output, `session.log` has entry
5. **Debug level** (Phase 3): Set `g:llm_log_level = 'debug'` → verify `input.json` and `aichat.log` also persist
6. **Disable logging** (all phases): Set `g:llm_log_level = 'none'` → verify NO files persist (exact current behavior)
7. **Commands** (Phase 4): Test `:LLMLog`, `:LLMLogDir`, `:LLMLogTail`, `:LLMLogClean` — verify each works correctly
8. **Cleanup** (Phase 4): Create >100 log dirs, run `:LLMLogClean` → verify count limit enforced
9. **Backward compat**: Remove all new `g:llm_log*` vars from vimrc → verify plugin starts and works (defaults apply)
10. **Symlink stability**: Run 3 requests rapidly → verify `latest` always points to most recent

---

## Appendix: Reference Plugin Patterns

| Plugin | Log Access Command | Log Location | Approach |
|--------|-------------------|-------------|----------|
| copilot.vim | `:Copilot log` | `~/.local/state/nvim/copilot.log` | Single append-only file, opened in buffer |
| coc.nvim | `:CocOpenLog` | `~/.config/coc/extensions/coc.log` | Size-rotated, opened in split |
| ALE | `:ALEInfo` | In-memory only | Command history dumped to buffer on demand |
| vim-lsp | `g:lsp_log_file` config | User-specified path | JSON-RPC message logging to file |
| vim-dispatch | `:Copen` | Temp file per dispatch | Opens quickfix with output |

The proposed design borrows:
- From **copilot.vim**: Simple command to open log (`:LLMLog`)
- From **coc.nvim**: Configurable log location, log levels
- From **vim-lsp**: User-configurable `g:llm_log_dir` and `g:llm_log_level`
- From **vim-dispatch**: The "open output" pattern (`:LLMLog` ≈ `:Copen`)
- **Novel addition**: `latest` symlink + per-request directories + terminal tail integration

---

## Appendix: Session Log Format

The `session.log` is a single append-only file providing a grep-able audit trail:

```
2024-06-11 10:30:00 | claude-3-7-sonnet | 12s | OK | Fix the authentication bug in login.py
2024-06-11 10:32:15 | claude-3-7-sonnet | 8s | OK | Explain this function
2024-06-11 10:45:00 | gpt-4o | 3s | ERROR:1 | Write tests for the auth module
```

Fields: `timestamp | model | duration | status | prompt_preview(80 chars)`

This enables quick queries like:
- `grep ERROR session.log` — find failed requests
- `grep claude session.log` — filter by model
- `tail -5 session.log` — see last 5 requests
- `wc -l session.log` — count total requests this session
