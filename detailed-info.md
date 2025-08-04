# VIM-LLM-ASSISTANT CODEBASE EXPLANATION

## Overview
The `vim-llm-assistant` is a Vim plugin that seamlessly integrates Large Language Models (LLMs) into the Vim workflow. It provides a way to interact with LLMs directly from Vim, maintain conversation history, and customize the experience through different models and adapters.

## File-by-File Explanation

### plugin/llm.vim
This file initializes the plugin and sets up global variables and commands.

**Key Functions:**
- **Plugin Initialization**: Checks if plugin is already loaded and sets default settings
- **Command Definitions**: Creates the `:LLM`, `:SetLLMModel`, `:SetLLMAdapter`, `:ListLLMModels`, and `:ListLLMAdapters` commands
- **Completion Functions**: `llm#complete_models` and `llm#complete_adapters` provide command completion for the respective commands

**Global Variables:**
- `g:llm_default_model`: Default LLM model (defaults to 'claude-3-7-sonnet-20250219')
- `g:llm_role`: Default LLM role (defaults to 'default-vim-role')
- `g:llm_default_adapter`: Default LLM adapter (defaults to 'aichat')
- `g:llm_adapters`: List of adapters to load (defaults to ['aichat'])

**Initialization Sequence:**
1. Checks if the plugin is already loaded via `g:loaded_llm_plugin`
2. Sets up default values for all configuration variables if not already defined
3. Loads specified adapters from the `g:llm_adapters` list
4. Registers commands with appropriate completion functions
5. Sets `g:loaded_llm_plugin` to prevent reloading

### autoload/llm.vim
This is the core of the plugin, implementing the main functionality.

**Key Functions:**
- **`llm#encode`**: Encodes data as JSON with proper escaping and formatting
- **`llm#open_scratch_buffer`**: Creates or reuses a buffer for LLM history/responses with:
  - Custom syntax highlighting for timestamps
  - Non-modifiable settings
  - Special buffer configuration (no file, no swap file)
- **`llm#open_snippet_buffer`**: Creates or reuses a dedicated buffer for storing snippet metadata
- **`llm#add_snippet`**: Adds metadata about a visual selection to the snippet buffer
- **`llm#clear_snippet_buffer`**: Clears all snippets from the buffer
- **`llm#process`**: Delegates processing to the current adapter, handling any errors
- **`llm#get_available_models`**: Returns list of available models from the current adapter
- **`llm#set_default_model`**: Sets the default model and validates it against available options
- **`llm#set_default_adapter`**: Sets the default adapter and validates its availability
- **`llm#run`**: Main function that:
  1. Gathers context (cursor position, active buffer, other buffers)
  2. Checks for snippets and uses them when available
  3. Builds JSON data structure with timestamps and conversation history
  4. Creates temporary files for data exchange with the adapter
  5. Calls the adapter to process the request
  6. Displays the response in a scratch buffer with timestamps
  7. Maintains conversation history for subsequent requests

**Response Handling:**
1. The response from the adapter is read from a temporary file
2. A timestamp is added to track the conversation flow
3. The response is appended to the scratch buffer with proper formatting
4. The cursor is positioned at the end of the buffer for easy reading
5. The scratch buffer is displayed in a window sized to fit the content

### autoload/llm/adapter.vim
Defines the adapter interface and registry for LLM backends.

**Key Functions:**
- **`llm#adapter#register`**: Registers a new adapter in the global adapter registry
- **`llm#adapter#get_current`**: Returns the current adapter object from the registry
- **`llm#adapter#set_current`**: Changes the current adapter and validates it exists
- **`llm#adapter#list`**: Lists all registered adapters with their availability status

**Adapter Interface:**
Each adapter must implement:
- `process(json_filename, prompt, model)`: Process a request with the LLM
  - `json_filename`: Path to file containing the context JSON
  - `prompt`: The user's query/prompt
  - `model`: The specific model to use
- `get_available_models()`: Return a list of available models
- `check_availability()`: Check if the adapter is available/installed
- `get_name()`: Return the name of the adapter

**Adapter Registry:**
- Stored in script-local variable `s:adapters`
- Maps adapter names to adapter objects
- Provides lookup by name for command completion and adapter switching

### autoload/llm/adapters/aichat.vim
Implementation of the adapter interface for the 'aichat' CLI tool.

**Key Functions:**
- **`process`**: 
  - Constructs a command line for the aichat CLI tool
  - Passes the JSON context via a file
  - Redirects output to a temporary file
  - Handles execution errors and timeouts
- **`get_available_models`**: 
  - Calls `aichat --list-models`
  - Parses the output to extract available model names
- **`check_availability`**: 
  - Checks if the aichat executable exists in PATH
  - Verifies it responds to basic commands
- **`get_name`**: Returns the adapter name ('aichat')

**Self-Registration:**
- Uses `llm#adapter#register()` at load time to register itself
- Makes the adapter available immediately after loading

### default-vim-role.md
Contains the default system prompt/role for the LLM. This defines how the LLM should behave when processing requests.

**Key Instructions:**
1. Parse and understand the JSON context structure
2. Reference relevant parts of the context in responses
3. Use appropriate tools when requested or necessary
4. Be concise for coding-related requests
5. Follow a three-stage development cycle for file modifications:
   - PLAN STAGE: Outline changes without modifying files
   - REVIEW STAGE: Present diffs/previews for user approval
   - APPLY STAGE: Only modify files when explicitly directed

**Role Customization:**
- The role file can be customized by setting `g:llm_role` to a different path
- This allows for specialized behavior for different tasks or workflows

### doc/llm.txt
Standard Vim documentation file explaining:
1. Introduction to the plugin
2. Available commands and their usage
3. Configuration options and default values
4. Basic usage instructions and examples
5. Troubleshooting and FAQs

## JSON Context Structure

The plugin builds a rich JSON context structure that provides the LLM with detailed information about the current Vim session:

```json
{
  "cursor_line": <current line number>,
  "cursor_col": <current column number>,
  "active_buffer": {
    "filename": "<path to current buffer>",
    "contents": "<entire content of current buffer>"
  },
  "buffers": [
    {
      "filename": "<path to buffer 1>",
      "contents": "<content of buffer 1>"
    },
    ...
  ],
  "history": [
    {
      "timestamp": "<timestamp>",
      "type": "request",
      "content": "<user prompt>"
    },
    {
      "timestamp": "<timestamp>",
      "type": "response",
      "content": "<LLM response>"
    },
    ...
  ],
  "prompt": "<current user prompt>"
}
```

This structure allows the LLM to:
1. Understand the current editing context (file, position)
2. See the content of other open buffers for reference
3. Access the conversation history for continuity
4. Provide contextually relevant responses

## Snipping Capabilities

The plugin includes a powerful snipping system that allows you to be more precise and selective about what context is sent to the LLM. This feature is particularly useful when:

1. Working with large files where you only want the LLM to focus on specific sections
2. Creating a custom context from multiple files without sending entire file contents
3. Reducing token usage by limiting the context to just what's relevant

### How Snippet Functionality Works

The plugin implements a dedicated snippet buffer system with these key functions:

1. `llm#open_snippet_buffer()`: Opens or reuses a dedicated buffer for storing snippet metadata
2. `llm#add_snippet()`: Adds metadata about a visual selection to the snippet buffer
3. `llm#clear_snippet_buffer()`: Clears all snippets from the buffer

### Using Snippets

Here's how to use the snippet functionality:

1. **Create a snippet**: Visually select text in any buffer (using `v`, `V`, or `Ctrl+v`), then call the snippet addition function (typically mapped to a command)
2. **View snippets**: Open the snippet buffer to see all your current snippets
3. **Clear snippets**: Use the clear function to remove all stored snippets
4. **Context processing**: When you run the `:LLM` command, the plugin automatically checks for snippets and uses them instead of entire file contents when applicable

### How Snippets Are Stored

The snippet system uses a clever approach:
- Rather than storing the actual content, it stores metadata in the format: `filename: start_line,end_line`
- When building context for the LLM, the plugin checks if a snippet exists for a given file
- If a snippet exists, it only sends the lines within that range instead of the entire file

### Integration with Context Building

When the `llm#run()` function builds context data, it:
1. Checks if the snippet buffer exists
2. For each buffer in the current tab, looks for a matching snippet entry
3. If found, replaces the full file contents with just the snippet selection
4. This modified context is then sent to the LLM

### Benefits of Using Snippets

1. **Precision**: Focus the LLM's attention exactly where it matters
2. **Efficiency**: Reduce token usage by eliminating irrelevant content
3. **Clarity**: Create custom contexts that combine specific parts of different files
4. **Control**: Maintain explicit control over what the LLM can and cannot see

### Example Workflow

1. Open multiple files in a Vim session
2. Select important sections in each file and add them as snippets
3. Run the `:LLM` command with a prompt
4. The LLM receives only the specific sections you selected, not the entire files

This snipping capability provides fine-grained control over the context, making your interactions with the LLM more focused and effective.

## How Everything is Connected

1. **Plugin Initialization Flow**:
   - `plugin/llm.vim` loads first, setting up global variables and commands
   - It loads the adapters specified in `g:llm_adapters`
   - Each adapter registers itself with the adapter registry in `autoload/llm/adapter.vim`
   - Commands are set up with appropriate completion functions

2. **Command Flow**:
   - When `:LLM` is called, it invokes `llm#run()`
   - `llm#run()` gathers context and builds a JSON structure
   - If snippets are defined, they're used instead of full file contents
   - It writes the JSON to a temporary file
   - It calls `llm#process()` which delegates to the current adapter
   - The adapter processes the request and writes the response to another temporary file
   - The response is read, timestamped, and displayed in a scratch buffer
   - The history is updated for future requests

3. **Adapter System**:
   - The adapter interface in `autoload/llm/adapter.vim` defines a common API
   - Adapters implement this interface and register themselves
   - The plugin can switch between different adapters through the `:SetLLMAdapter` command
   - Currently only 'aichat' is implemented, but the architecture allows for easy addition of new adapters
   - Adapters can be implemented for different LLM backends (API-based, local models, etc.)
   - The adapter system abstracts away the details of how the LLM is called

4. **Response Handling**:
   - Responses are displayed in a dedicated scratch buffer
   - Timestamps are added to both requests and responses
   - The buffer is formatted for readability with syntax highlighting
   - The conversation history is maintained for context in future requests
   - The scratch buffer is non-modifiable to preserve the conversation history

5. **Extensibility Points**:
   - New adapters can be added by implementing the adapter interface
   - The role/system prompt can be customized
   - Default models and adapters can be configured
   - The JSON context structure provides a standardized way to pass information to any LLM
   - The snippet system allows for precise context control

This architecture provides flexibility and extensibility while maintaining a simple user interface. The adapter pattern allows for supporting different LLM backends, and the JSON context provides the LLM with rich information about the current Vim session.