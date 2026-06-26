# Current LLMLog Commands Audit

## Overview

The vim-llm-assistant plugin provides 4 user-facing log management commands defined in `plugin/llm.vim:86-89` and implemented in `autoload/llm/log.vim`.

## Configuration Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `g:llm_log_dir` | `~/.local/share/vim-llm-assistant/logs` | Root log directory (`plugin/llm.vim:39`) |
| `g:llm_log_level` | `'info'` | Log verbosity: info (response+session) or debug (+input+aichat) (`plugin/llm.vim:43-44`) |
| `g:llm_log_keep_count` | `500` | Max log directories to retain, 0=unlimited (`plugin/llm.vim:53`) |
| `g:llm_log_max_age_days` | `30` | Max log age in days, 0=keep forever (`plugin/llm.vim:58`) |

**Note**: `g:llm_log_level = 'none'` is overridden to `'info'` at startup (`plugin/llm.vim:47-49`).

---

## Commands

### 1. `:LLMLog [type]`

**Definition**: `plugin/llm.vim:86`
```vim
command! -nargs=? -complete=customlist,llm#log#complete_types LLMLog call llm#log#open(<q-args>)
```

**Arguments**: Optional type — one of `response`, `input`, `tools`, `aichat`, `session`, `dir` (default: `response`)

**Implementation**: `autoload/llm/log.vim:95-131` (`llm#log#open()`)

**Behavior by type**:
| Type | File Accessed | Behavior |
|------|--------------|----------|
| `response` (default) | `{request_dir}/response.md` | Opens in vsplit, jumps to end, copies path to `@"` and `@+` |
| `input` | `{request_dir}/input.json` | Same as above |
| `tools` | `{request_dir}/tools.log` | Same as above |
| `aichat` | `{request_dir}/aichat.log` | Same as above |
| `session` | `{g:llm_log_dir}/session.log` | Opens in vsplit, jumps to end, copies path |
| `dir` | `{g:llm_log_dir}/` | Opens netrw browser (delegates to `llm#log#browse()`) |

**Request directory resolution** (`autoload/llm/log.vim:63-85`, `s:resolve_request_dir()`):
1. Checks `llm#get_active_requests()` — if exactly 1 active request, uses its `.dir`
2. If multiple active requests, prompts user with `inputlist()` to pick one (defaults to most recent)
3. Falls back to `llm#get_last_request_dir()` — persists even after request completes

**Window behavior** (`autoload/llm/log.vim:88-96`, `s:open_or_focus()`):
- If buffer already visible in a window, focuses that window
- Otherwise opens in a new vsplit

---

### 2. `:LLMLogDir`

**Definition**: `plugin/llm.vim:87`
```vim
command! LLMLogDir call llm#log#browse()
```

**Arguments**: None

**Implementation**: `autoload/llm/log.vim:133-137` (`llm#log#browse()`)

**Behavior**:
- Opens `g:llm_log_dir` in netrw (`:edit {dir}`)
- Copies directory path to `@"` and `@+` registers

**File Accessed**: The log root directory (default: `~/.local/share/vim-llm-assistant/logs/`)

**Note**: Functionally identical to `:LLMLog dir`

---

### 3. `:LLMLogTail [type]`

**Definition**: `plugin/llm.vim:88`
```vim
command! -nargs=? LLMLogTail call llm#log#tail(<q-args>)
```

**Arguments**: Optional type — `response` or `aichat` (default: `response`)

**Implementation**: `autoload/llm/log.vim:140-193` (`llm#log#tail()`)

**Behavior**:
1. Resolves request directory via `s:resolve_request_dir()`
2. Maps type to file: `response` → `response.md`, `aichat` → `aichat.log`
3. Touches the file if it doesn't exist yet (so `tail -F` can follow it)
4. Copies file path to `@"` and `@+`
5. **If `has('terminal')`**:
   - Checks for existing terminal tailing the same file (avoids duplicates)
   - Opens `tail -F {file}` in a bottom terminal split via `term_start()`
   - Returns focus to previous window
6. **Fallback (no terminal support)**:
   - Opens the file in vsplit with `autoread`
   - Sets up a 1-second timer to `checktime` for auto-refresh
   - Scrolls to bottom on file change

**Files Accessed**: `{request_dir}/response.md` or `{request_dir}/aichat.log`

**Use case**: Live monitoring of streaming LLM responses or aichat debug output

---

### 4. `:LLMLogClean [days]`

**Definition**: `plugin/llm.vim:89`
```vim
command! -nargs=? LLMLogClean call llm#log#clean(<q-args>)
```

**Arguments**: Optional days threshold (default: `g:llm_log_max_age_days` = 30)

**Implementation**: `autoload/llm/log.vim:196-225` (`llm#log#clean()`)

**Behavior**:
1. Globs all request directories matching `[0-9]*_[0-9]*_[0-9]*` pattern
2. **Count-based limit** (applied first): If directories exceed `g:llm_log_keep_count`, removes oldest excess
3. **Age-based limit** (applied second): Removes directories with `getftime()` older than cutoff
4. Reports number of directories removed

**Files Accessed**: All timestamped subdirectories of `g:llm_log_dir`

**Also runs automatically** at `VimEnter` via `llm#log#startup_cleanup()` (`plugin/llm.vim:92-94`)

---

## Internal Infrastructure (Not User-Facing)

These functions support the commands above:

| Function | Location | Purpose |
|----------|----------|---------|
| `llm#log#dir()` | `autoload/llm/log.vim:4-8` | Ensures log directory exists, returns path |
| `llm#log#create_request()` | `autoload/llm/log.vim:12-33` | Creates timestamped per-request dir with all log file paths |
| `llm#log#session_append(entry)` | `autoload/llm/log.vim:36-38` | Appends a line to `session.log` |
| `llm#log#latest_response()` | `autoload/llm/log.vim:41-43` | Returns `{g:llm_log_dir}/latest/response.md` (for statusline) |
| `llm#log#complete_types()` | `autoload/llm/log.vim:46-49` | Tab-completion: response, input, tools, aichat, session, dir |
| `llm#log#startup_cleanup()` | `autoload/llm/log.vim:228-232` | Silent cleanup at VimEnter |
| `s:resolve_request_dir()` | `autoload/llm/log.vim:52-85` | Resolves active/last request directory |
| `s:open_or_focus(file)` | `autoload/llm/log.vim:88-96` | Focus existing window or vsplit |

**Request registry** (`autoload/llm.vim:9-10`):
| Variable | Purpose |
|----------|---------|
| `s:active_requests` | List of active request dicts (each has `.dir`, `.log_paths`, `.model`, `.start_time`, `.prompt`) |
| `s:last_request_dir` | Most recently started request dir (persists after completion) |

**Access functions** (`autoload/llm.vim:14-29`):
| Function | Purpose |
|----------|---------|
| `llm#get_current_log_paths()` | Returns `.log_paths` dict of most recent active request |
| `llm#get_active_requests()` | Returns full `s:active_requests` list |
| `llm#get_last_request_dir()` | Returns `s:last_request_dir` string |

---

## Log File Structure

Each request creates a directory: `{g:llm_log_dir}/YYYYMMDD_HHMMSS_NNN/`

Files within each request directory:
| File | Purpose | Created When |
|------|---------|-------------|
| `input.json` | Full input context sent to LLM | `g:llm_log_level == 'debug'` |
| `response.md` | LLM response (streamed) | Always (when logging enabled) |
| `tools.log` | Tool/function call output | When tools are used |
| `aichat.log` | aichat CLI debug output | `g:llm_log_level == 'debug'` |

Root-level files:
| File | Purpose |
|------|---------|
| `session.log` | Append-only session log (timestamps, models, prompts) |
| `latest` | Symlink → most recent request directory |

---

## Command-to-File Access Map (Quick Reference)

| Command | Files It Can Access |
|---------|-------------------|
| `:LLMLog` / `:LLMLog response` | `{request}/response.md` |
| `:LLMLog input` | `{request}/input.json` |
| `:LLMLog tools` | `{request}/tools.log` |
| `:LLMLog aichat` | `{request}/aichat.log` |
| `:LLMLog session` | `{root}/session.log` |
| `:LLMLog dir` / `:LLMLogDir` | `{root}/` (netrw) |
| `:LLMLogTail` / `:LLMLogTail response` | `{request}/response.md` (live) |
| `:LLMLogTail aichat` | `{request}/aichat.log` (live) |
| `:LLMLogClean [days]` | Removes old `{root}/YYYYMMDD_*` dirs |
