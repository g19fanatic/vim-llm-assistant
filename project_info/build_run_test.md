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