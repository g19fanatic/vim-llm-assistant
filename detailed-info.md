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

### autoload/llm.vim
This is the core of the plugin, implementing the main functionality.

**Key Functions:**
- **`llm#encode`**: Encodes data as JSON
- **`llm#open_scratch_buffer`**: Creates or reuses a buffer for LLM history/responses with syntax highlighting
- **`llm#process`**: Delegates processing to the current adapter
- **`llm#get_available_models`**: Returns list of available models from the current adapter
- **`llm#set_default_model`**: Sets the default model
- **`llm#set_default_adapter`**: Sets the default adapter
- **`llm#run`**: Main function that:
  1. Gathers context (cursor position, active buffer, other buffers)
  2. Builds JSON data structure
  3. Calls the adapter to process the request
  4. Displays the response in a scratch buffer with timestamps

### autoload/llm/adapter.vim
Defines the adapter interface and registry for LLM backends.

**Key Functions:**
- **`llm#adapter#register`**: Registers a new adapter
- **`llm#adapter#get_current`**: Returns the current adapter
- **`llm#adapter#set_current`**: Changes the current adapter
- **`llm#adapter#list`**: Lists all registered adapters

**Adapter Interface:**
Each adapter must implement:
- `process(json_filename, prompt, model)`: Process a request with the LLM
- `get_available_models()`: Return a list of available models
- `check_availability()`: Check if the adapter is available/installed
- `get_name()`: Return the name of the adapter

### autoload/llm/adapters/aichat.vim
Implementation of the adapter interface for the 'aichat' CLI tool.

**Key Functions:**
- **`process`**: Calls the aichat CLI tool with appropriate parameters
- **`get_available_models`**: Gets list of models from aichat
- **`check_availability`**: Checks if aichat is installed
- **`get_name`**: Returns the adapter name
- Registers itself with the adapter registry

### default-vim-role.md
Contains the default system prompt/role for the LLM. This defines how the LLM should behave when processing requests. It instructs the LLM to:
1. Use the provided JSON context to understand the current Vim session
2. Reference relevant parts of the context when responding
3. Use tools when necessary
4. Be concise for coding-related requests
5. Follow a three-stage development cycle (Plan, Review, Apply) for file modifications

### doc/llm.txt
Standard Vim documentation file explaining:
1. Introduction to the plugin
2. Available commands
3. Configuration options
4. Basic usage instructions

## How Everything is Connected

1. **Plugin Initialization Flow**:
   - `plugin/llm.vim` loads first, setting up global variables and commands
   - It loads the adapters specified in `g:llm_adapters`
   - Each adapter registers itself with the adapter registry in `autoload/llm/adapter.vim`

2. **Command Flow**:
   - When `:LLM` is called, it invokes `llm#run()`
   - `llm#run()` gathers context and builds a JSON structure
   - It calls `llm#process()` which delegates to the current adapter
   - The adapter processes the request and returns the response
   - The response is displayed in a scratch buffer

3. **Adapter System**:
   - The adapter interface in `autoload/llm/adapter.vim` defines a common API
   - Adapters implement this interface and register themselves
   - The plugin can switch between different adapters (currently only 'aichat' is implemented)
   - This architecture allows for easy addition of new adapters for different LLM backends

4. **Context Structure**:
   The plugin passes a rich context to the LLM, including:
   - Cursor position
   - Active buffer contents
   - Other visible buffers
   - Conversation history
   - User prompt

This architecture provides flexibility and extensibility while maintaining a simple user interface. The adapter pattern allows for supporting different LLM backends, and the JSON context provides the LLM with rich information about the current Vim session.
