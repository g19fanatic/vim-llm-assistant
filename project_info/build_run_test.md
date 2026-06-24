# Build, Run, and Test Instructions

## Installation

### Prerequisites

1. **Vim or Neovim**:
   - Vim 8.0+ or Neovim (required for JSON support)
   - Basic Vim configuration

2. **aichat CLI**:
   - Must be installed and configured on your system
   - Authentication to LLM providers properly set up
   - Available in your PATH

### Installation Options

#### Using Vim-Plug

Add to your `.vimrc` or `init.vim`:
```vim
Plug 'g19fanatic/vim-llm-assistant'
```
Then run `:PlugInstall` in Vim.

#### Using Vundle

Add to your `.vimrc` or `init.vim`:
```vim
Plugin 'g19fanatic/vim-llm-assistant'
```
Then run `:PluginInstall` in Vim.

#### Manual Installation

```bash
git clone https://github.com/g19fanatic/vim-llm-assistant.git ~/.vim/pack/plugins/start/vim-llm-assistant
```

## Configuration

### Basic Configuration

Add these settings to your `.vimrc` or `init.vim`:

```vim
" Set default LLM model
let g:llm_default_model = 'claude-3-7-sonnet-20250219'

" Set LLM role (optional, defaults to default-vim-role.md in plugin directory)
" let g:llm_role = '/path/to/custom/role.md'

" Set default adapter (optional, defaults to 'aichat')
" let g:llm_default_adapter = 'aichat'

" Optional: Map keys for convenience
nnoremap <leader>ll :LLM<space>
```

### Advanced Configuration

```vim
" Define specific adapters to load
let g:llm_adapters = ['aichat']  " Future: Add more adapters when available

" Set session directory (optional)
" let g:llm_session_dir = '~/.vim/llm_sessions'

" Create custom key mappings for snippets
vnoremap <leader>ls :LLMSnip<CR>
nnoremap <leader>lv :ViewLLMSnippets<CR>
nnoremap <leader>lc :ClearLLMSnippets<CR>

" Session management shortcuts
nnoremap <leader>lss :SaveLLMSession<space>
nnoremap <leader>lsl :LoadLLMSession<space>
```

## Testing

### Manual Testing

1. **Basic Functionality**:
   ```vim
   :LLM What is this file doing?
   ```
   Should display a response in a new scratch buffer.

2. **Model Selection**:
   ```vim
   :SetLLMModel claude-3-opus-20240229
   :LLM Explain this code in detail
   ```
   Should use the specified model.

3. **Snippets**:
   - Select text in visual mode
   - `:LLMSnip`
   - `:LLM What does this selection do?`
   - Should only process the selected snippet.

4. **Session Management**:
   ```vim
   :SaveLLMSession my_session
   ```
   (Close and reopen Vim)
   ```vim
   :LoadLLMSession my_session
   ```
   Should restore your LLM conversation and buffer layout.

### Troubleshooting

If you encounter issues:

1. **Check Adapter Availability**:
   ```vim
   :ListLLMAdapters
   ```
   Should show 'aichat' as available.

2. **Check Model Availability**:
   ```vim
   :ListLLMModels
   ```
   Should list available models.

3. **Check Error Messages**:
   - Look for error messages in the LLM scratch buffer
   - Check if aichat is working from command line

4. **Debug Mode**:
   Add to your configuration:
   ```vim
   let g:llm_debug = 1
   ```
   This will show more verbose information in the LLM buffer.

## Development

### Setting Up Development Environment

1. **Clone Repository**:
   ```bash
   git clone https://github.com/g19fanatic/vim-llm-assistant.git
   cd vim-llm-assistant
   ```

2. **Symlink for Testing**:
   ```bash
   ln -s $(pwd) ~/.vim/pack/dev/start/vim-llm-assistant
   ```

3. **Or use a plugin manager in development mode**:
   ```vim
   " In .vimrc with vim-plug
   Plug '~/path/to/vim-llm-assistant'
   ```

### Adding a New Adapter

1. Create new file: `autoload/llm/adapters/youradapter.vim`
2. Implement the adapter interface (use aichat.vim as template)
3. Make sure to register the adapter with `llm#adapter#register()`
4. Add to `g:llm_adapters` list in your config

### Modifying the Core

When modifying core functionality:

1. Update `autoload/llm.vim` for most functionality
2. Update `plugin/llm.vim` only for command definitions or initialization
3. Test changes with a variety of commands and inputs

### Documentation

If adding features:

1. Update `doc/llm.txt` with new commands or options
2. Update `README.md` with user-facing changes
3. Add comments to code explaining complex sections

## Usage Examples

### Basic Usage

```vim
:LLM Explain this function
```

### Code Generation

```vim
:LLM Write a function that sorts an array of integers
```

### With Snippets

```vim
" Select code in visual mode
:LLMSnip
:LLM Refactor this to be more efficient
```

### Session Management

```vim
" Save current session
:SaveLLMSession debugging_session

" Load previous session
:LoadLLMSession debugging_session
```

### Model Switching

```vim
" List available models
:ListLLMModels

" Switch models
:SetLLMModel claude-3-opus-20240229

" Use for complex tasks
:LLM Design a system architecture for this code
```

## Log Access & Debugging

The plugin provides a comprehensive logging system for diagnosing issues,
reviewing past conversations, and monitoring active requests in real time.

### Quick Reference — Log Commands

| Command | Description |
|---------|-------------|
| `:LLMLog [type]` | Open a log file in a vsplit (default: `response`) |
| `:LLMLogDir` | Browse the log root directory in netrw |
| `:LLMLogTail [type]` | Live-tail a log in a terminal split |
| `:LLMLogClean [days]` | Remove old log directories by age/count |
| `:LLMLogDebug` | Toggle log level between `info` and `debug` at runtime |

**Type argument** (used by `:LLMLog` and `:LLMLogTail`):

| Type | File | Available At |
|------|------|--------------|
| `response` | `response.md` | info, debug |
| `input` | `input.json` | debug only |
| `tools` | `tools.log` | info, debug |
| `aichat` | `aichat.log` | debug only |
| `session` | `session.log` (root-level) | info, debug |
| `dir` | _(opens netrw)_ | — |

### Configuration Variables

Add these to your `.vimrc` to customize logging behavior:

```vim
" Log root directory (default: ~/.local/share/vim-llm-assistant/logs)
let g:llm_log_dir = '~/.local/share/vim-llm-assistant/logs'

" Log level: 'none', 'info', or 'debug' (default: 'info')
"   none  — disable ALL logging (no files written, no cleanup)
"   info  — write response.md + session.log per request
"   debug — additionally write input.json + aichat.log with full diagnostics
let g:llm_log_level = 'info'

" Maximum log directories to keep (default: 500, 0 = unlimited)
let g:llm_log_keep_count = 500

" Maximum log age in days (default: 30, 0 = keep forever)
let g:llm_log_max_age_days = 30
```

### Log Directory Layout

```
~/.local/share/vim-llm-assistant/logs/
├── session.log                      # One-line summary per request
├── latest -> 20250615_143022_001    # Symlink to most recent request
├── 20250615_140512_001/             # Per-request directory
│   ├── response.md                  # LLM response (always at info+)
│   ├── tools.log                    # Tool output (often empty)
│   ├── input.json                   # Full input payload (debug only)
│   └── aichat.log                   # aichat internal log (debug only)
├── 20250615_143022_001/
│   └── ...
└── ...
```

**Directory naming**: `YYYYMMDD_HHMMSS_NNN` where `NNN` is a sequence number
to disambiguate requests within the same second.

**session.log format** (one line per completed request):
```
2025-06-15 14:30:22 | claude-3-7-sonnet-20250219 | 8s | OK | Explain this function
2025-06-15 14:35:01 | claude-3-7-sonnet-20250219 | 3s | ERROR:1 | Fix the bug in...
```

Fields: `datetime | model | duration | status | prompt` (prompt truncated to 80 chars).

### Enabling Debug Mode

#### At runtime (toggle)

```vim
:LLMLogDebug
```

This toggles `g:llm_log_level` between `info` and `debug`. The current level is
echoed after each toggle. Subsequent `:LLM` requests will write full diagnostics
including `input.json` and `aichat.log`.

#### In your vimrc (persistent)

```vim
let g:llm_log_level = 'debug'
```

#### Disabling logging entirely

```vim
let g:llm_log_level = 'none'
```

When set to `'none'`, no log files are written, no directories are created,
and startup cleanup is skipped.

### Command Details

#### `:LLMLog [type]`

Opens the specified log file for the most recent (or active) request in a
vertical split. Defaults to `response` if no type is given.

- If multiple requests are active, presents a numbered list to choose from
- Copies the opened file path to the unnamed (`"`) and system (`+`) registers
- For `input` or `aichat` types at non-debug level, shows a helpful message
  explaining how to enable debug logging

#### `:LLMLogDir`

Opens the log root directory in netrw for manual browsing.

#### `:LLMLogTail [type]`

Starts a live `tail -F` of the specified log file in a terminal split (requires
Vim with `+terminal`). Useful for watching responses stream in real time.

- Reuses an existing terminal if already tailing the same file
- Falls back to autoread-based polling if `+terminal` is unavailable
- For `session` type, tails the root-level session.log (not per-request)

#### `:LLMLogClean [days]`

Removes old log directories. Applies two policies:

1. **Count limit**: If total directories exceed `g:llm_log_keep_count`, removes
   the oldest until within budget
2. **Age limit**: Removes directories older than `[days]` (defaults to
   `g:llm_log_max_age_days`)

Also runs automatically at startup (non-blocking, via timer).

#### `:LLMLogDebug`

Toggles `g:llm_log_level` between `info` and `debug` at runtime. Echoes the
new level. No restart required — takes effect on the next `:LLM` request.

### aichat Environment Variables

When running at debug level, the plugin sets these environment variables for
the aichat subprocess:

| Variable | Value | Purpose |
|----------|-------|---------|
| `AICHAT_LOG_PATH` | `<request_dir>/aichat.log` | Directs aichat's internal logging to the per-request directory |
| `AICHAT_LOG_LEVEL` | `debug` | Enables verbose aichat logging |
| `LLM_OUTPUT` | `<tempfile>` | Captures tool output (used internally by the plugin) |

These are only set when `g:llm_log_level ==# 'debug'` and are scoped to the
individual aichat process — they do not affect your shell environment.

### Shell Recipes — Accessing Logs from the Terminal

```bash
# Default log location
LOG_DIR=~/.local/share/vim-llm-assistant/logs

# View the latest response
cat "$LOG_DIR/latest/response.md"

# Tail the latest response in real time (while Vim is running)
tail -F "$LOG_DIR/latest/response.md"

# View session history (all past requests)
cat "$LOG_DIR/session.log"

# Search session history for a keyword
grep -i "keyword" "$LOG_DIR/session.log"

# List all request directories (newest last)
ls -1t "$LOG_DIR"/[0-9]*_[0-9]*_[0-9]* | tail -20

# View aichat debug log for latest request (requires debug level)
cat "$LOG_DIR/latest/aichat.log"

# Count total log directories
ls -1d "$LOG_DIR"/[0-9]*_[0-9]*_[0-9]* 2>/dev/null | wc -l

# Manual cleanup: remove logs older than 7 days
find "$LOG_DIR" -maxdepth 1 -name '[0-9]*_[0-9]*_[0-9]*' -mtime +7 -exec rm -rf {} +

# Disk usage of all logs
du -sh "$LOG_DIR"
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `:LLMLog input` says "requires debug level" | Run `:LLMLogDebug` to switch to debug mode, then retry your request |
| No log directories exist | Verify `g:llm_log_level` is not `'none'`; run `:LLM` at least once |
| `session.log` is empty | Logging only appends after a request completes; check `g:llm_log_level` |
| `:LLMLogTail` shows stale content | The log follows the *active* or *latest* request — start a new `:LLM` |
| Terminal tail doesn't update | Ensure `+terminal` feature is compiled in (`:echo has('terminal')`) |
| Logs consuming too much disk | Lower `g:llm_log_keep_count` or `g:llm_log_max_age_days`, then `:LLMLogClean` |
| `latest` symlink is broken | Occurs if the target was cleaned; run any `:LLM` to recreate it |