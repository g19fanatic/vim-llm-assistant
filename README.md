# vim-llm-assistant

A Vim plugin that integrates Large Language Models (LLMs) directly into your Vim workflow.

## Features

- Process text with LLMs right from Vim
- Maintain conversation history in a dedicated buffer
- Select from multiple LLM models
- Customize prompts and roles
- Save and load sessions for persistent conversations

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
- `:SaveLLMSession [filename]` - Save the current LLM session (history, snippets, and tab layout)
- `:LoadLLMSession filename` - Load a previously saved LLM session

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

- **Command Output**: Pull in custom contexts by creating new buffers with explicit command outputs (e.g., `:new | r! git diff` or `:vsp | r! ls -la`), making it clear to the LLM what specific information you want it to consider.

- **Project Structure**: Include information about the project structure by passing the output of `find` or similar commands.

- **Git Context**: Add git blame information, branch details, or commit history for more relevant suggestions.

- **Runtime Information**: Include Vim settings, environment variables, or other runtime information that might be relevant to your query.

By understanding the context structure, you can craft more effective prompts that leverage the information already available to the LLM.


### Practical Context Management

The plugin is designed around a simple but powerful principle: **what you see is what the LLM sees**. This approach gives you precise control over what information is included in the context:

- Only buffers visible in the **current tab** are included in the context
- Temporary buffers are included, making them powerful tools for context injection
- Background buffers (not visible in current tab) are excluded
- Hidden buffers (loaded but not displayed) are excluded

This design lets you manage context deliberately, even when working with large projects that have thousands of files.

## Advanced Usage Techniques

### Session Management

The plugin offers robust session management capabilities, allowing you to save and restore your entire LLM workflow:

```vim
" Save your current LLM session (with auto-completion)
:SaveLLMSession my_project

" Load a previously saved session (with auto-completion)
:LoadLLMSession my_project
```

Session files are stored in `~/.vim/vim-llm-assistant/sessions/` by default. Each session saves:

- Complete conversation history from the LLM History buffer
- All defined snippets from the LLM Snippets buffer
- Current tab layout including opened files
- Window arrangement within tabs

This allows you to:
- Maintain long-running conversations across different Vim sessions
- Share LLM conversations with team members by sharing session files
- Create specialized environments for different projects or tasks
- Quickly switch between different conversation contexts

### Using Temporary Buffers for Context Injection

One of the most powerful techniques is using temporary buffers to feed specific information to the LLM:

```vim
" Include a file tree in the context
:vnew
:r!tree
" Now ask the LLM about the project structure

" Include git diff information for analysis
:new
:r!git diff
" Now ask the LLM to explain or summarize the changes

" Analyze changes from a specific branch
:vnew
:r!git diff origin/master
" Ask the LLM to analyze the PR changes

" Get more context in the diff with more unchanged lines
:r!git diff -U10 origin/master
" Now the LLM can better understand the surrounding code
```

These temporary buffers become part of the context only when they're visible, giving you precise control over what information is included.

### Build Output Analysis

You can easily include build errors or command output:

```vim
" Run a build and capture output
:new
:r!make 2>&1
" Now ask the LLM to explain errors or suggest fixes
```

### Switching Models Mid-Conversation

The plugin allows you to switch between different LLM models during a conversation:

```vim
" Start with a default model
:LLM What is the best way to implement this feature?

" Switch to a more capable model for complex tasks
:SetLLMModel claude-3-opus-20240229
:LLM Can you elaborate on the implementation details?

" Switch to a faster model for simpler follow-ups
:SetLLMModel claude-3-haiku-20240307
:LLM Great, now help me write a test for this feature.
```

### History Revision and Branching

Sometimes you need to explore different conversation paths or fix mistakes in the conversation history:

2. Write the history to a temporary file: `:w /tmp/llm_history.txt`
3. Edit the history as needed (remove unwanted parts, fix mistakes, etc.)
4. Load the modified history back: `:LLMLoadHistory /tmp/llm_history.txt`
5. Continue the conversation from the new state

This technique allows you to "branch" conversations, explore different approaches, or correct earlier misunderstandings without starting over.

### Context Size Management

When working with very large files or many buffers, be mindful of context size limits:

- Keep an eye on the token count displayed after LLM responses
- Close unnecessary buffers from the current tab view
- Use split windows judiciously to maintain only relevant context
- For large files, consider using smaller sections in temporary buffers

#### Snippet Management with LLMSnip

The plugin provides powerful snippet management capabilities that let you include only the most relevant portions of files in your context:

- Use `:LLMSnip` in visual mode to add the selected text as a snippet
- The `:ViewLLMSnippets` command shows all your currently defined snippets
- Edit the snippet list directly in the [LLM-Snippets] buffer
- Clear all snippets with `:ClearLLMSnippets` when you want to start fresh
- Add multiple snippets from the same file for precise context control
- Snippets are stored by filename and line range, making them easy to manage

Example workflow:

```vim
" Select important code in visual mode and add it as a snippet
:LLMSnip

" Add another important section from the same file
:LLMSnip

" View and edit your snippets
:ViewLLMSnippets

" Ask the LLM about just these specific sections
:LLM What does this code do?

" Start fresh with a clean snippet list
:ClearLLMSnippets
```

When snippets are defined for a file, only those snippets (not the entire file) will be included in the context, dramatically reducing token usage while focusing the LLM on exactly what matters.


## Code Structure

For a comprehensive explanation of the codebase, including detailed descriptions of each file and how they interact, please see [detailed-info.md](detailed-info.md).

## Requirements

This project requires the 'aichat' command-line tool to be installed and configured on your system.

## License

This project is licensed under the MIT License - see the [LICENSE.txt](./LICENSE.txt) file for details.