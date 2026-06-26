# Vim Plugin Logging Best Practices for vim-llm-assistant

## Investigation Summary

Researched best practices for Vim plugin logging with a focus on: how users can tail logs in real-time during an LLM run, what log files should exist, how other Vim async plugins handle log visibility, and how to design a robust logging architecture for vim-llm-assistant.

---

## 1. How Other Vim Async Plugins Handle Logging

### ALE (Asynchronous Lint Engine)
- **Configuration**: `let g:ale_history_log_output = 1` to record linter output; optional `g:ale_log_file` for file-based debug logging
- **Visibility**: `:ALEInfo` command shows all recent linter runs, their commands, exit codes, and output
- **Pattern**: Single configurable log file path, append-mode, tailable with `tail -f`
- **Key insight**: Separates "user-visible output" (in quickfix/loclist) from "debug log" (optional file)

### vim-lsp
- **Configuration**: `let g:lsp_log_file = expand('~/vim-lsp.log')` + `let g:lsp_log_verbose = 1`
- **Visibility**: Logs both sent and received LSP messages to a single file
- **Pattern**: Single append-only log file, tailable, verbose mode toggle
- **Key insight**: Default is OFF; user explicitly opts in by setting the path

### copilot.vim
- **Configuration**: Logs to `~/.local/state/copilot/` (XDG state directory)
- **Visibility**: `:Copilot log` command opens the log file directly in a Vim buffer
- **Pattern**: Known persistent directory, Vim command for direct access, always-on logging
- **Key insight**: Provides a command that opens the log IN Vim rather than requiring external `tail`

### coc.nvim
- **Configuration**: `"coc.preferences.maxFileSize"`, log level in `:CocConfig`
- **Visibility**: `:CocInfo` for diagnostics summary, `:CocOpenLog` to open the log file
- **Pattern**: XDG-based log directory, multiple verbosity levels, dedicated commands
- **Key insight**: Two commands — one for quick summary, one for full log file

### vim-dispatch
- **Output handling**: Creates output files in known temp locations during execution
- **Visibility**: `:Copen` shows output in quickfix window
- **Pattern**: Real-time file writes during async execution; quickfix integration for viewing
- **Key insight**: Writes output to file AS it arrives (not buffered until completion)

---

## 2. Proposed Log File Types

Based on analysis of the plugin's architecture and user needs, five distinct log types are recommended:

| Log Type | Purpose | When Written | Size Estimate | Priority |
|----------|---------|--------------|---------------|----------|
| **Response Stream** | Raw LLM output as it arrives via `out_cb` | During async execution | 1-50KB per request | HIGH — this is what users want to tail |
| **Input JSON** | Full context payload sent to LLM | At request start | 5-200KB per request | MEDIUM — useful for debugging prompt issues |
| **Tool Output** | Aichat tool invocation results | During execution (if tools run) | 0-100KB per request | MEDIUM — useful for tool debugging |
| **Debug Log** | Internal plugin debug messages | Throughout execution | Variable | LOW — currently goes to `:messages` |
| **Aichat Debug** | Full aichat API request/response log | Throughout execution | 100KB-10MB per session | ALREADY EXISTS via `AICHAT_LOG_PATH` |

### Current State

The user ALREADY has a working aichat debug log via environment variables:
```bash
# In ~/.bashrc:
export AICHAT_LOG_LEVEL=debug
export AICHAT_LOG_PATH="$HOME/.local/share/vim-llm-assistant/logs/${d}_aichat.log"
```

This produces per-session log files at `~/.local/share/vim-llm-assistant/logs/YYYY-MM-DD_HHMMSS_aichat.log` (currently 336 files, 345MB). This log is **already tailable** and contains full API payloads — but the plugin has no command to access it.

### What's Missing

1. **Response stream log** — The actual LLM response text goes through `out_cb` into memory (`l:output` list) but is never written to a tailable file during execution
2. **Input JSON persistence** — The context JSON is written to `tempname()` then deleted after completion; no persistent copy
3. **Plugin awareness of AICHAT_LOG_PATH** — The plugin doesn't know about or expose the existing debug log

---

## 3. Naming Conventions

### Recommended Directory Structure

```
~/.local/share/vim-llm-assistant/logs/
├── sessions/                        # Per-session aichat debug logs (existing)
│   └── 2026-06-11_052351_aichat.log
├── requests/                        # Per-request log files
│   ├── 2026-06-11_093045_001_response.log    # LLM response stream
│   ├── 2026-06-11_093045_001_input.json      # Input context
│   └── 2026-06-11_093045_001_tools.log       # Tool output (if any)
└── current -> requests/2026-06-11_093045_001_response.log  # Symlink to active
```

### File Naming Pattern

```
<YYYY-MM-DD>_<HHMMSS>_<job_id>_<type>.<ext>
```

- **Date prefix**: Enables lexicographic sorting and easy cleanup
- **Job ID**: Matches the `s:next_job_id` counter already in the plugin
- **Type suffix**: `response`, `input`, `tools`
- **Extension**: `.log` for streaming text, `.json` for structured data

### Symlink for "Current" Log

A `current` symlink pointing to the active response log enables:
```bash
tail -f ~/.local/share/vim-llm-assistant/logs/current
```

This is the key UX improvement — the user always has a stable path to tail.

---

## 4. Persistence Strategy

### Retention Policy (Recommended Defaults)

| Setting | Default | Rationale |
|---------|---------|-----------|
| `g:llm_log_keep_days` | 7 | Balance between disk usage and debugging needs |
| `g:llm_log_keep_count` | 100 | Maximum number of request logs to keep |
| `g:llm_log_max_size_mb` | 500 | Total log directory size cap |
| `g:llm_log_enabled` | 1 | On by default (lightweight — only response stream) |
| `g:llm_log_input` | 0 | Input JSON logging opt-in (can be large) |

### Cleanup Strategy

1. **Lazy cleanup**: Run cleanup logic at plugin startup (VimEnter autocmd), not during requests
2. **Age-based**: Delete files older than `g:llm_log_keep_days`
3. **Count-based**: Keep only the most recent `g:llm_log_keep_count` request logs
4. **Size-based**: If total exceeds `g:llm_log_max_size_mb`, delete oldest first
5. **Never delete during execution**: Only clean up on startup or explicit command

### Existing Log Accumulation

The current setup already accumulates 345MB across 336 files over ~2.5 months with NO rotation. This confirms the need for automated cleanup. The current rate is ~140MB/month which would grow unbounded.

---

## 5. Tail-ability Design

### The Core Problem

Currently, the LLM response flows through Vim's job channel callbacks into memory:
```vim
'out_cb': {channel, msg -> [add(l:output, msg), ...]}
```

This is fast and correct for the plugin's needs, but provides **no file to tail**. The response is only materialized to the `[LLM-Scratch]` buffer AFTER the job completes.

### Solution: Tee Pattern in out_cb

Write each line to a log file AS it arrives, in addition to the existing memory accumulation:

```vim
" Proposed modification to out_cb (aichat.vim ~line 163):
'out_cb': {channel, msg -> [
    \ add(l:output, msg),
    \ writefile([msg], l:response_log, 'a'),
    \ llm#debug('aichat.out_cb: Received ' . len(msg) . ' chars')
    \ ]},
```

**Key properties for tail-ability**:
1. **Append mode** (`'a'` flag): Each `out_cb` call appends one line immediately
2. **No buffering**: `writefile()` with `'a'` flag writes immediately (no Vim output buffering)
3. **File exists before job starts**: Create the file (touch) before `job_start()` so `tail -f` can attach early
4. **Stable path**: Use a symlink (`current`) that points to the active log

### Three Ways to Tail (in order of user-friendliness)

#### Method 1: Vim Terminal Split (Best UX)
```vim
" :LLMTail command opens a terminal split tailing the current log
command! LLMTail call llm#tail_log()

function! llm#tail_log() abort
  let l:log = g:llm_log_dir . '/current'
  if filereadable(l:log)
    execute 'terminal ++rows=10 tail -f ' . shellescape(l:log)
  else
    echo '[LLM] No active log file'
  endif
endfunction
```

#### Method 2: Open Log in Buffer (Passive Viewing)
```vim
" :LLMLog opens the most recent response log in a split (copilot.vim pattern)
command! LLMLog call llm#open_log()

function! llm#open_log() abort
  let l:log = llm#get_latest_log()
  if !empty(l:log)
    execute 'split ' . fnameescape(l:log)
    normal! G
  endif
endfunction
```

#### Method 3: External Terminal
```bash
# User runs in a separate tmux pane:
tail -f ~/.local/share/vim-llm-assistant/logs/current
```

### Status Line Fix (Critical)

The status line should show the **tailable response log path** instead of the useless LLM_OUTPUT temp file:

```vim
" Current (broken):
let l:temp = has_key(l:job_info, 'temp_file') ? l:job_info.temp_file : '?'

" Proposed (fixed):
let l:temp = has_key(l:job_info, 'response_log') ? l:job_info.response_log : '?'
```

---

## 6. Proposed Configuration Variables

```vim
" Log directory (default follows XDG_DATA_HOME pattern)
if !exists('g:llm_log_dir')
  let g:llm_log_dir = expand('~/.local/share/vim-llm-assistant/logs')
endif

" Enable response stream logging (write LLM output to file as it arrives)
if !exists('g:llm_log_enabled')
  let g:llm_log_enabled = 1
endif

" Also log the input JSON context (can be large, off by default)
if !exists('g:llm_log_input')
  let g:llm_log_input = 0
endif

" Retention: days to keep logs
if !exists('g:llm_log_keep_days')
  let g:llm_log_keep_days = 7
endif

" Retention: maximum number of request log sets to keep
if !exists('g:llm_log_keep_count')
  let g:llm_log_keep_count = 100
endif
```

---

## 7. Proposed Vim Commands

| Command | Description | Pattern Source |
|---------|-------------|----------------|
| `:LLMLog` | Open the most recent response log in a split buffer | copilot.vim (`:Copilot log`) |
| `:LLMTail` | Open a terminal split with `tail -f` on the current/active log | vim-dispatch (`:Copen`) |
| `:LLMLogs` | Open the log directory in netrw for browsing | Original |
| `:LLMLogClean` | Run manual cleanup of old logs | ALE-inspired |
| `:LLMInfo` | Show current logging configuration and active log path | coc.nvim (`:CocInfo`) |

---

## 8. Implementation Approach (High-Level)

### Phase 1: Minimal Viable Logging (addresses core user complaint)

1. **Add response log tee** in `out_cb` (aichat.vim:163) — write each line to a file as it arrives
2. **Create log directory** at startup if it doesn't exist
3. **Update status line** to show the response log path instead of LLM_OUTPUT temp file
4. **Add `:LLMLog` command** to open the current/latest response log
5. **Add `current` symlink** management — point to active response log

### Phase 2: Full Logging Suite

6. **Add `:LLMTail` command** with terminal split
7. **Add input JSON logging** (opt-in via `g:llm_log_input`)
8. **Add log rotation/cleanup** at startup
9. **Add `:LLMLogs` and `:LLMInfo` commands**
10. **Integrate with existing `AICHAT_LOG_PATH`** — expose it via `:LLMInfo`

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Default log location | `~/.local/share/vim-llm-assistant/logs/` | Already used by existing `AICHAT_LOG_PATH` setup; follows XDG convention |
| Log during execution (not after) | Yes — tee pattern | Core requirement: real-time tail-ability |
| Default enabled | Yes for response stream | Primary use case; low overhead |
| Input JSON logging | Off by default | Can be very large (200KB+); opt-in |
| Cleanup timing | At VimEnter, not during requests | Never slow down LLM requests with I/O overhead |
| Symlink for "current" | Yes | Stable path for external `tail -f` without knowing job ID |

---

## 9. Comparison: Current vs Proposed

| Aspect | Current | Proposed |
|--------|---------|----------|
| Real-time output visibility | None (in-memory only) | Response log file, tailable in real-time |
| Status line shows | LLM_OUTPUT temp file (empty/useless) | Response log path (tailable) |
| Persistent logs | Only via AICHAT_LOG_PATH (external setup) | Built-in per-request response logs |
| Vim commands for logs | None | `:LLMLog`, `:LLMTail`, `:LLMLogs`, `:LLMInfo` |
| Log cleanup | None (345MB accumulated) | Configurable retention + startup cleanup |
| User effort to tail | Must know about AICHAT_LOG_PATH env var | `:LLMTail` or `tail -f .../current` |
| Input JSON visibility | Deleted after request | Optionally persisted |

---

## 10. References and Sources

- **ALE source**: https://github.com/dense-analysis/ale — `g:ale_history_log_output`, `:ALEInfo`
- **vim-lsp source**: https://github.com/prabirshrestha/vim-lsp — `g:lsp_log_file`
- **copilot.vim source**: https://github.com/github/copilot.vim — `:Copilot log`
- **coc.nvim source**: https://github.com/neoclide/coc.nvim — `:CocOpenLog`, `:CocInfo`
- **vim-dispatch source**: https://github.com/tpope/vim-dispatch — quickfix output pattern
- **Existing setup**: `~/.bashrc` exports `AICHAT_LOG_LEVEL=debug` and `AICHAT_LOG_PATH` per-session
- **Existing log dir**: `~/.local/share/vim-llm-assistant/logs/` (336 files, 345MB, date range 2026-03-31 to 2026-06-11)
- **Plugin code**: `autoload/llm/adapters/aichat.vim` (out_cb at line ~163, status line at lines 12-37)
