# vim-llm-assistant

A Vim plugin that integrates Large Language Models (LLMs) directly into your Vim workflow.

## Features

- Process text with LLMs right from Vim
- Maintain conversation history in a dedicated buffer
- Select from multiple LLM models
- Customize prompts and roles

## Installation

### Using Vim-Plug

```vim
Plug 'g19fanatic/vim-llm-assistant'
```

### Using Vundle

```vim
Plugin 'g19fanatic/vim-llm-assistant'
```

### Manual Installation

```
git clone https://github.com/yourusername/vim-llm-assistant.git ~/.vim/pack/plugins/start/vim-llm-assistant
```

## Usage

Basic commands:

- `:LLM [prompt]` - Process the current buffer with an LLM, optionally with a prompt
- `:SetLLMModel model_name` - Set the default LLM model
- `:ListLLMModels` - Show available LLM models

## Configuration

Add these settings to your `.vimrc` to customize the plugin:

```vim
" Set default LLM model
let g:llm_default_model = 'claude-3-7-sonnet-20250219'

" Set LLM role
let g:llm_role = 'default-vim-role'
```

## Context Structure

When you invoke the LLM assistant, the plugin gathers contextual information from your Vim session and passes it to the LLM in a structured JSON format. Understanding this context structure helps you craft more effective prompts and potentially extend the plugin for custom workflows.

### What's Included in the Context

The plugin automatically sends the following information to the LLM:

1. **Cursor Position**:
   - `cursor_line`: Current line number where the cursor is positioned
   - `cursor_col`: Current column number where the cursor is positioned

2. **Active Buffer**:
   - `active_buffer.filename`: Path of the file you're currently editing
   - `active_buffer.contents`: Complete text contents of the active buffer

3. **Visible Buffers in Current Tab**:
   - `buffers`: Array of other buffers visible in the current tab
   - Each buffer includes `filename` and `contents` properties
   - The LLM scratch buffer (history) is excluded from this list

4. **LLM History**:
   - `llm_history`: Complete conversation history from previous interactions

5. **User Prompt**:
   - `prompt`: Your specific instruction to the LLM (when provided)

### Why This Approach?

This context structure provides several advantages:

- **Focused Context**: By only including buffers from the current tab, the plugin maintains relevance while avoiding token limit issues
- **Cursor Awareness**: The LLM knows where you're currently working, enabling position-aware suggestions
- **Conversation Continuity**: Including the conversation history allows for follow-up questions and refinements
- **Tab-specific Context**: Each tab can maintain its own working context (useful for different projects)

### Example Context JSON

```json
{
  "cursor_line": 42,
  "cursor_col": 10,
  "active_buffer": {
    "filename": "/path/to/myfile.py",
    "contents": "def hello_world():\n    print('Hello, World!')\n"
  },
  "buffers": [
    {
      "filename": "/path/to/another_file.py",
      "contents": "# Another file in the current tab\n"
    }
  ],
  "llm_history": "==== Previous conversation history ====",
  "prompt": "Explain how this function works"
}
```

### Extending the Context

- **Command Output**: Capture output from shell commands like `:r! git diff` or `:r! ls -la` by modifying the plugin to accept command output as part of the context.

  ```vim
  " Example function to extend context with command output
  function! llm#with_command_output(command, prompt) abort
    let l:output = system(a:command)
    let l:extended_prompt = "Command output:\n" . l:output . "\n\nUser prompt: " . a:prompt
    call llm#run(l:extended_prompt)
  endfunction

  " Example usage:
  " :call llm#with_command_output('git diff origin/master', 'Explain these changes')
  ```

- **Project Structure**: Include information about the project structure by passing the output of `find` or similar commands.

- **Git Context**: Add git blame information, branch details, or commit history for more relevant suggestions.

- **Runtime Information**: Include Vim settings, environment variables, or other runtime information that might be relevant to your query.

By understanding the context structure, you can craft more effective prompts that leverage the information already available to the LLM.

## Requirements

This plugin requires the 'aichat' command-line tool to be installed and configured on your system.

## License

MIT License
