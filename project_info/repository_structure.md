# Repository Structure

> **Last updated**: 2026-04-06  
> **Note**: The task description referenced `scripts/` (llm_status.py, parse_aichat_log.py, tests/) and `autoload/llm/session_log.vim` — **none of these files exist yet** in the repository. This document reflects the actual current file tree.

---

## Directory Tree

```
vim-llm-assistant/
├── autoload/
│   ├── llm.vim               # 831 LOC — Core plugin functionality
│   ├── llm.vim.bak           # 831 LOC — Backup: pre-tmux-fix state
│   └── llm/
│       ├── adapter.vim       #  54 LOC — Adapter registry/interface
│       └── adapters/
│           ├── aichat.vim    # 293 LOC — aichat CLI adapter
│           └── aichat.vim.bak# 293 LOC — Backup: pre-cmd-augmentation state
│
├── doc/
│   └── llm.txt               # 116 LOC — Vim :help documentation
│
├── plugin/
│   ├── llm.vim               #  76 LOC — Commands + initialization
│   └── llm.vim.bak           #  76 LOC — Backup of plugin entry point
│
├── project_info/             # Documentation directory
│   ├── README.md             #  24 LOC — Index with reading order
│   ├── architecture.md       # 127 LOC — Component breakdown, data flow
│   ├── build_run_test.md     # 225 LOC — Install, config, usage examples
│   ├── complexity_areas.md   # 172 LOC — Complex components, tech debt
│   ├── features_and_development.md  # 445 LOC — Dev history, feature details
│   ├── project_overview.md   #  37 LOC — What, why, key features
│   ├── repository_structure.md # this file
│   ├── summarize_log.md      # 204 LOC — Log of /summarize operations
│   └── technologies.md       # 108 LOC — External deps, implementation choices
│
├── .gitignore                #   2 LOC — Ignores swap files
├── LICENSE.txt               #   7 LOC — License
├── README.md                 # 316 LOC — Public-facing project overview
├── README.md.bak             # 280 LOC — Backup: older README version
├── default-vim-role.md       # 416 LOC — Default LLM system prompt/role
├── detailed-info.md          # 346 LOC — Legacy detailed info (pre-project_info/)
├── summary.md                # 103 LOC — Session summary / handover notes
└── todos.md                  #  11 LOC — Active task list
```

---

## Source Files (Active)

### `plugin/llm.vim` — 76 LOC
Plugin entry point, loaded at Vim startup. Defines all user-facing commands and sets default configuration globals.

**Key locations:**
- `plugin/llm.vim:46` — `:LLM` command definition
- `plugin/llm.vim:47` — `:LLMFile` command definition
- `plugin/llm.vim:48-49` — `:SetLLMModel` / `:SetLLMAdapter` commands
- `plugin/llm.vim:51-55` — Snippet commands (`:LLMSnip`, `:ViewLLMSnippets`, `:ClearLLMSnippets`, `:ListLLMModels`, `:ListLLMAdapters`)
- `plugin/llm.vim:58-59` — `:StopLLMJob` / `:ListLLMJobs` (async job management)
- `plugin/llm.vim:75-76` — `:SaveLLMSession` / `:LoadLLMSession`

---

### `autoload/llm.vim` — 831 LOC
Core implementation: context gathering, buffer management, async job orchestration, session persistence, and notification dispatch.

**Key locations:**
- `autoload/llm.vim:2` — `llm#debug()` — debug logging helper
- `autoload/llm.vim:9` — `llm#encode()` — JSON encoding wrapper
- `autoload/llm.vim:14` — `llm#open_scratch_buffer()` — creates/focuses the LLM output buffer
- `autoload/llm.vim:66` — `llm#open_snippet_buffer()` — opens reusable snippet buffer
- `autoload/llm.vim:92` — `llm#clear_snippet_buffer()` — clears snippet buffer
- `autoload/llm.vim:102` — `llm#add_snippet()` — captures visual selection as snippet
- `autoload/llm.vim:123` — `llm#get_buffer_content()` — extracts content from a buffer by number/filename
- `autoload/llm.vim:169` — `llm#process()` — synchronous LLM dispatch
- `autoload/llm.vim:178` — `llm#process_async()` — asynchronous LLM dispatch (main code path)
- `autoload/llm.vim:201` — `llm#get_available_models()` — lists available models via adapter
- `autoload/llm.vim:210` — `llm#set_default_model()` — sets `g:llm_default_model`
- `autoload/llm.vim:221` — `llm#list_jobs()` — shows popup/float/split of active async jobs
- `autoload/llm.vim:344` — `llm#stop_job()` — cancels an active async job by ID
- `autoload/llm.vim:358` — `llm#run_with_files()` — `:LLMFile` entry point (delegates to `llm#run`)
- `autoload/llm.vim:456` — `llm#run()` — main `:LLM` entry point; gathers context, builds JSON, calls `process_async`
- `autoload/llm.vim:590` — `maybe_notify` context dict construction (adds `tmux_window` key)
- `autoload/llm.vim:594-598` — tmux window capture + `process_async` call (tmux notification fix)
- `autoload/llm.vim:604` — `llm#ensure_session_dir()` — creates session directory if missing
- `autoload/llm.vim:613` — `llm#complete_sessions()` — tab-completion for session names
- `autoload/llm.vim:620` — `llm#save_session()` — serializes history buffer, snippets, and window layout
- `autoload/llm.vim:719` — `llm#load_session()` — restores session state from disk
- `autoload/llm.vim:827` — `llm#maybe_notify()` — calls `g:Llm_notify_func` if configured

---

### `autoload/llm/adapter.vim` — 54 LOC
Adapter registry: stores registered adapter objects and manages the active adapter selection.

**Key locations:**
- `autoload/llm/adapter.vim:8` — `llm#adapter#register()` — adds adapter to registry dict
- `autoload/llm/adapter.vim:21` — `llm#adapter#get_current()` — returns active adapter object
- `autoload/llm/adapter.vim:29` — `llm#adapter#get_current_name()` — returns active adapter name string
- `autoload/llm/adapter.vim:37` — `llm#adapter#set_current()` — switches active adapter
- `autoload/llm/adapter.vim:45` — `llm#adapter#list()` — returns list of registered adapter names

---

### `autoload/llm/adapters/aichat.vim` — 293 LOC
Concrete adapter implementation for the `aichat` CLI tool. Handles async job lifecycle, command augmentation, file argument injection, model enumeration, and self-registration.

**Key locations:**
- `autoload/llm/adapters/aichat.vim:11` — `s:show_status_message()` — timer callback showing "[LLM] Processing..." in statusline
- `autoload/llm/adapters/aichat.vim:24` — `s:generate_job_id()` — increments global job counter
- `autoload/llm/adapters/aichat.vim:31` — `s:aichat_adapter.list_jobs()` — returns active job info list
- `autoload/llm/adapters/aichat.vim:53` — `s:aichat_adapter.stop_job()` — sends SIGTERM to a running job
- `autoload/llm/adapters/aichat.vim:88` — `s:aichat_adapter.process_async()` — main async dispatch: builds command with cmd_extra + file flags, starts `job_start()`
- `autoload/llm/adapters/aichat.vim:100-110` — command augmentation check (`g:llm_adapter_cmd_extra`)
- `autoload/llm/adapters/aichat.vim:186` — `s:aichat_adapter.process()` — synchronous variant (blocking `system()` call)
- `autoload/llm/adapters/aichat.vim:243` — `s:on_job_complete()` — job exit callback: stops timer, joins output, calls user callback
- `autoload/llm/adapters/aichat.vim:275` — `s:aichat_adapter.get_available_models()` — runs `aichat --list-models`
- `autoload/llm/adapters/aichat.vim:282` — `s:aichat_adapter.check_availability()` — checks `which aichat`
- `autoload/llm/adapters/aichat.vim:289` — `s:aichat_adapter.get_name()` — returns `'aichat'`
- `autoload/llm/adapters/aichat.vim:293` — self-registration via `llm#adapter#register('aichat', ...)`

---

## Documentation Files

### `doc/llm.txt` — 116 LOC
Vim `:help` format documentation. Covers command reference, configuration variables, and usage examples. Accessible via `:help llm` after install.

### `default-vim-role.md` — 416 LOC
Default system prompt passed to the LLM as `g:llm_role`. Defines how the LLM should interpret JSON context, format responses, manage the task system (`/init`, `/save`, `/compact`, etc.), and use code location references (`filepath:line`).

- `default-vim-role.md:121-125` — `/init` update mode auto-detection logic
- `default-vim-role.md:119-132` — Code location references format spec

### `README.md` — 316 LOC
Public-facing project overview: features, installation, configuration, and usage examples.

---

## Backup Files (`.bak`)

| File | LOC | Origin |
|------|-----|--------|
| `autoload/llm.vim.bak` | 831 | Pre-tmux-notification-fix backup (2026-03-13) |
| `autoload/llm/adapters/aichat.vim.bak` | 293 | Pre-command-augmentation backup |
| `plugin/llm.vim.bak` | 76 | Backup of plugin entry point |
| `README.md.bak` | 280 | Older README version |

These files are **not loaded by Vim** and serve only as rollback snapshots. They are untracked or tracked in git but not part of the active plugin.

---

## Root-Level Prose Files

| File | LOC | Purpose |
|------|-----|---------|
| `summary.md` | 103 | Rolling session summary / handover context |
| `todos.md` | 11 | Active task list in `[ ]`/`[x]` format |
| `detailed-info.md` | 346 | Legacy comprehensive info (predates `project_info/`) |

---

## Missing / Planned Files (Not Yet Created)

The following files were referenced in the task but **do not exist** in the repository:

| Expected Path | Status | Planned Purpose |
|---------------|--------|-----------------|
| `scripts/llm_status.py` | ❌ Not found | Python status/monitoring script |
| `scripts/parse_aichat_log.py` | ❌ Not found | Log parser for aichat output |
| `scripts/tests/` | ❌ Not found | Test suite for scripts |
| `autoload/llm/session_log.vim` | ❌ Not found | Session logging autoload module |

---

## File Relationships

```
plugin/llm.vim
  └── defines user commands → delegates to autoload/llm.vim

autoload/llm.vim (llm#run, llm#run_with_files)
  ├── builds JSON context
  ├── calls llm#process_async()
  │     └── calls llm#adapter#get_current().process_async()
  │               └── autoload/llm/adapters/aichat.vim
  ├── manages session state (llm#save_session / llm#load_session)
  └── calls llm#maybe_notify() on completion

autoload/llm/adapter.vim
  └── registry: maps name → adapter object
        └── aichat.vim calls llm#adapter#register() at load time
```

## Autoload Naming Conventions

- `llm#function_name()` — Core functions in `autoload/llm.vim`
- `llm#adapter#function_name()` — Adapter registry in `autoload/llm/adapter.vim`
- `s:aichat_adapter.method()` — Dict-based methods on the aichat adapter object

## Directory Organization Rationale

| Directory | Load Time | Purpose |
|-----------|-----------|---------|
| `plugin/` | Vim startup | Commands, globals, guard checks |
| `autoload/` | On-demand | Implementation — only loaded when first called |
| `doc/` | `:help` lookup | Vim help system integration |
| Root | N/A | Configuration, role prompts, documentation |
| `project_info/` | N/A | Developer context docs (not loaded by Vim) |
