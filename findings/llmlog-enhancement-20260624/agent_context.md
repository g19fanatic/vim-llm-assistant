# Agent Context for LLMLog Enhancement

## Key Files
- `autoload/llm/log.vim` — All log infrastructure: dir management, open, tail, clean, browse functions
- `plugin/llm.vim` — Command definitions (lines 87-90: LLMLog*, line 45-47: log_level override)
- `autoload/llm/adapters/aichat.vim` — aichat adapter with env var setup (lines 163-166: AICHAT_LOG_PATH/LEVEL), session.log append (lines 345-355)
- `project_info/build_run_test.md` — User documentation (target for task 7)
- `findings/llmlog-toolset-research-20260624/` — Prior research on log mechanisms (4 files)

## Build Commands
N/A — VimScript plugin, no build step.

## Test Commands
Manual verification: Open vim, source plugin, run commands. Automated verification not available.
For each code task, verify by:
1. Running `vim -u NONE -c "source plugin/llm.vim" -c "source autoload/llm/log.vim"` to check for syntax errors
2. Confirming new commands appear in `:command LLMLog`
3. Checking function exists: `:echo exists('*llm#log#<funcname>')`

## VimScript Patterns in This Project
- Functions use `abort` keyword (mandatory)
- File-local functions use `s:` prefix
- Public API uses `llm#log#` namespace
- Commands defined in `plugin/llm.vim` with explicit -nargs, -complete
- Error messages use `echom '[LLM] ...'` format
- Warning messages use `echohl WarningMsg` + `echom` + `echohl None`
- Interactive lists use `inputlist()` pattern (see s:resolve_request_dir at log.vim:67-82)

## Log Architecture
- Log root: `g:llm_log_dir` (default: `~/.local/share/vim-llm-assistant/logs`)
- Per-request dirs: `{root}/YYYYMMDD_HHMMSS_NNN/` containing: response.md, input.json, tools.log, aichat.log
- Session log: `{root}/session.log` (one-line per request: `datetime | model | duration | status | prompt`)
- Latest symlink: `{root}/latest → {most_recent_dir_name}`
- Only response.md + session.log exist at info level; input.json + aichat.log only at debug level
- tools.log often empty (aichat overrides LLM_OUTPUT internally)
