# vim-llm-assistant — LLM Context Strategy

## Project Purpose
A Vim plugin that sends the current editing context (buffers, cursor, history) to an LLM via an adapter layer (default: `aichat`) and displays responses in a persistent scratch buffer. Supports async jobs, session persistence, file attachments, and user-defined notification hooks.

---

## Directory Layout (LOC)

```
vim-llm-assistant/
├── plugin/llm.vim              (76)   — startup: commands, defaults, adapter loading
├── autoload/llm.vim            (831)  — core: context build, scratch buffer, sessions, notify
├── autoload/llm/adapter.vim    (54)   — adapter registry + interface contract
├── autoload/llm/adapters/
│   └── aichat.vim              (293)  — aichat CLI adapter (sync + async, job tracking)
├── default-vim-role.md         (416)  — system prompt sent to LLM by aichat --role
├── doc/llm.txt                        — Vim :help documentation
├── project_info/                      — LLM-maintained documentation (this directory)
└── README.md, summary.md, todos.md
```

---

## Key Entry Points (`filepath:line`)

| Symbol | Location | Purpose |
|--------|----------|---------|
| Commands registered | `plugin/llm.vim:35-51` | All `:LLM*` / `Set*` / `*Session` commands |
| `llm#run()` | `autoload/llm.vim:449` | Main entry: builds JSON context, fires async job |
| `llm#run_with_files()` | `autoload/llm.vim:357` | Parses `:LLMFile` args → calls `llm#run()` |
| `OnLLMComplete` closure | `autoload/llm.vim:~555` | Async callback: writes to scratch buffer |
| `llm#process_async()` | `autoload/llm.vim:~195` | Routes to adapter sync or async path |
| `llm#adapter#register()` | `autoload/llm/adapter.vim:7` | Adapters self-register here |
| `s:aichat_adapter.process_async()` | `autoload/llm/adapters/aichat.vim:86` | Launches `job_start` with aichat CLI |
| `s:aichat_adapter.process()` | `autoload/llm/adapters/aichat.vim:171` | Synchronous fallback via `system()` |
| `llm#save_session()` | `autoload/llm.vim:~640` | Serializes history+snippets+layout to JSON |
| `llm#load_session()` | `autoload/llm.vim:~710` | Restores session from JSON |
| `llm#maybe_notify()` | `autoload/llm.vim:~828` | Calls `g:Llm_notify_func` if set |

---

## JSON Context Structure

`llm#run()` serializes this dict and writes it to a tempfile; the adapter passes it to `aichat --file <tempfile>`:

```json
{
  "cursor_line": 42,
  "cursor_col": 10,
  "active_buffer": {
    "filename": "src/foo.py",
    "contents": "<full text or snippets>"
  },
  "buffers": [
    { "filename": "other.py", "contents": "..." }
  ],
  "prompt": "optional inline user prompt",
  "llm_history": "<scratch buffer text from previous turns>",
  "file_arguments": ["/abs/path/to/file1", "/abs/path/to/file2"]
}
```

- `buffers` — all tab-visible buffers except active, scratch, and snippet buffers  
- `llm_history` — full `[LLM-Scratch]` buffer content (conversation memory)  
- `file_arguments` — only present when `:LLMFile` is used  
- `prompt` — only present when a prompt string was provided  
- Snippet overrides: if `[LLM-Snippets]` has entries for a file, `contents` is replaced with just those line ranges

---

## Vim Commands

| Command | Description |
|---------|-------------|
| `:LLM [prompt]` | Send context + optional prompt to LLM (async) |
| `:LLMFile <files> [-- prompt]` | Attach files; files parsed before `--`, prompt after |
| `:SetLLMModel [model]` | Set `g:llm_default_model`; tab-completes from adapter |
| `:SetLLMAdapter [name]` | Switch active adapter at runtime |
| `:[range]LLMSnip` | Register visual selection as snippet (stores filename:start,end) |
| `:ViewLLMSnippets` | Open `[LLM-Snippets]` buffer |
| `:ClearLLMSnippets` | Empty the snippet buffer |
| `:ListLLMModels` | Echo `aichat --list-models` output |
| `:ListLLMAdapters` | Echo registered adapter names |
| `:ListLLMJobs` | Show active async jobs (popup/float/split) |
| `:StopLLMJob [id]` | Send SIGTERM to a running job |
| `:SaveLLMSession [file]` | Save history+snippets+layout to `~/.vim/vim-llm-assistant/sessions/` |
| `:LoadLLMSession [file]` | Restore session from file |

---

## Configuration Variables (`plugin/llm.vim`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `g:llm_default_model` | `'claude-3-7-sonnet-20250219'` | Model passed to adapter |
| `g:llm_role` | `'default-vim-role'` | `aichat --role` argument (maps to `default-vim-role.md`) |
| `g:llm_default_adapter` | `'aichat'` | Active adapter name |
| `g:llm_adapters` | `['aichat']` | Adapters to load at startup |
| `g:llm_use_async` | `has('job') && has('timers')` | Enable async job path |
| `g:Llm_notify_func` | *(unset)* | Funcref called after completion: `func(ctx)` where `ctx = {prompt, model, tmux_window}` |
| `g:llm_adapter_cmd_extra` | *(unset)* | Dict `{'aichat': 'FuncName'}` — function prepends env vars to aichat command |
| `g:llm_debug` | *(unset)* | Set to 1 to enable `echom` debug traces |

---

## Adapter Interface Contract

All adapters must implement these methods and call `llm#adapter#register(name, adapter_dict)`:

```vim
" Required
adapter.process(json_filename, prompt, model)     → String  " sync execution
adapter.get_available_models()                    → List    " for tab completion
adapter.check_availability()                      → Bool    " is tool installed?
adapter.get_name()                                → String  " adapter identifier

" Optional (enables async path)
adapter.process_async(json_filename, prompt, model, Callback)  " fires Callback(output)
adapter.list_jobs()   → List of {id, prompt, model, elapsed, status}
adapter.stop_job(job_id) → Bool
```

`aichat` adapter constructs: `LLM_OUTPUT=<tmp> aichat --role <role> --model <model> [-f file ...] --file <json> [-- prompt]`

---

## Session Logging Subsystem

Sessions stored at: `~/.vim/vim-llm-assistant/sessions/*.json`

Saved state:
```json
{
  "history":       ["line1", "line2", ...],   // [LLM-Scratch] buffer lines
  "snippets":      ["file.py: 10,25", ...],   // [LLM-Snippets] buffer lines
  "visible_files": ["/abs/path/file.py", ...],
  "tabs": [
    { "windows": ["/abs/path/file.py", "[LLM-Scratch]"] }
  ]
}
```

- `SaveLLMSession` / `LoadLLMSession` with tab-completion from session dir
- Load restores layout: closes all tabs, reopens per saved structure
- Special buffers `[LLM-Scratch]` / `[LLM-Snippets]` stored by basename and reopened via `llm#open_*_buffer()`

---

## Quick Start for LLMs

**To answer questions about this codebase:**
1. Core logic lives in `autoload/llm.vim` — read `llm#run()` to understand data flow
2. Commands are declared in `plugin/llm.vim` (76 lines, easy to scan entirely)
3. The aichat adapter is self-contained in `autoload/llm/adapters/aichat.vim`
4. The system prompt the LLM sees is `default-vim-role.md`

**To make changes:**
- Adding a command → `plugin/llm.vim` (declare) + `autoload/llm.vim` (implement)
- Adding an adapter → create `autoload/llm/adapters/<name>.vim`, implement interface, call `llm#adapter#register()`
- Changing context structure → modify `llm#run()` around line 449 in `autoload/llm.vim`
- Changing async behavior → `s:aichat_adapter.process_async()` in `autoload/llm/adapters/aichat.vim:86`

**Critical invariants:**
- `llm#run()` always writes a tempfile and passes it to the adapter; never passes content directly
- `OnLLMComplete` is a closure that captures `l:prompt`, `l:model`, `l:tmux_window`, and `l:tempfile`
- Scratch buffer (`[LLM-Scratch]`) = conversation history; Snippet buffer (`[LLM-Snippets]`) = line-range selectors
- Session save/load uses `g:llm_scratch_bufnr` / `g:llm_snippet_bufnr` globals to identify special buffers
