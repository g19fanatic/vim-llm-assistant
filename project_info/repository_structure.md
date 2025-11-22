# Repository Structure

## Directory Structure

```
vim-llm-assistant/
├── autoload/
│   ├── llm.vim               # Core plugin functionality
│   └── llm/                  # Namespace for plugin components
│       ├── adapter.vim       # Adapter interface and registry
│       └── adapters/         # Concrete adapter implementations
│           └── aichat.vim    # aichat CLI adapter
│
├── doc/
│   └── llm.txt               # Plugin documentation
│
├── plugin/
│   └── llm.vim               # Plugin initialization and commands
│
├── default-vim-role.md       # Default system prompt for LLM
├── LICENSE.txt               # License information
└── README.md                 # Project overview and documentation
```

## Key Files Explained

### Plugin Initialization and Commands
- **`plugin/llm.vim`**: Entry point for the plugin
  - Defines Vim commands (`:LLM`, `:SetLLMModel`, etc.)
  - Sets up default configuration values
  - Loads adapters from configuration
  - Registers command completion functions

### Core Functionality
- **`autoload/llm.vim`**: Main implementation file
  - Contains core functionality like context gathering
  - Implements buffer management for history and snippets
  - Handles JSON processing for LLM interaction
  - Manages session saving and loading
  - Implements snippet functionality

### Adapter System
- **`autoload/llm/adapter.vim`**: Adapter interface and registry
  - Defines the adapter protocol
  - Implements adapter registration system
  - Provides functions to get/set the current adapter
  - Lists available adapters and their status

### Adapter Implementations
- **`autoload/llm/adapters/aichat.vim`**: aichat adapter implementation
  - Implements adapter interface for aichat CLI tool
  - Handles model listing and availability checks
  - Processes LLM requests via aichat
  - Self-registers with adapter registry

### Documentation
- **`doc/llm.txt`**: Vim help documentation
  - Command reference and usage instructions
  - Configuration options and examples
  - Troubleshooting information

### Configuration Files
- **`default-vim-role.md`**: Default system prompt
  - Defines default behavior for LLM interactions
  - Explains context structure to the LLM
  - Sets expectations for response format and behavior

## File Relationships

1. **Command Flow**:
   - Commands registered in `plugin/llm.vim`
   - Command implementations in `autoload/llm.vim`
   - Commands delegate to adapter functions in `autoload/llm/adapter.vim`
   - Adapter interface calls concrete implementation in `autoload/llm/adapters/aichat.vim`

2. **Initialization Sequence**:
   - `plugin/llm.vim` loaded when Vim starts or plugin activated
   - Default configuration established
   - Adapters loaded and registered
   - Commands made available to user

3. **Processing Flow**:
   - User invokes `:LLM` command
   - `llm#run()` in `autoload/llm.vim` gathers context
   - Context passed to current adapter via `llm#process()`
   - Adapter processes request and returns response
   - Response displayed in scratch buffer

4. **Session Management**:
   - Session commands defined in `plugin/llm.vim`
   - Implementation in `autoload/llm.vim`
   - Reads/writes session files from disk
   - Restores buffer contents and window layout

## Autoload Organization

The plugin makes extensive use of Vim's autoload mechanism to:

1. **Improve Performance**: Code is only loaded when needed
2. **Organize Namespace**: Functions grouped by component
3. **Prevent Pollution**: Global namespace kept clean

Functions follow naming conventions:
- `llm#function_name()`: Core functionality
- `llm#adapter#function_name()`: Adapter framework
- `llm#adapters#adaptertype#function_name()`: Specific adapter implementations

## Configuration Files

### System Prompt (default-vim-role.md)
This file contains the default system prompt that instructs the LLM on how to:
- Interpret the JSON context structure
- Process requests appropriately
- Format responses for Vim environment
- Handle specialized tasks like code explanation

Users can customize this file or specify a different one through the `g:llm_role` configuration variable.

## Directory Organization Rationale

- **`autoload/`**: Contains implementation code loaded on-demand
- **`plugin/`**: Contains initialization code loaded at startup
- **`doc/`**: Contains documentation accessible via Vim's help system
- **Root directory**: Contains configuration files and main documentation

This structure follows Vim plugin conventions and allows for efficient loading and organization of code.