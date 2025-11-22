# Architecture Overview

## Core Architecture

The vim-llm-assistant plugin follows a modular, layered architecture that separates concerns between user interface, core functionality, and LLM interaction:

```
┌─────────────────────────────────────────┐
│            Command Interface            │
│       (:LLM, :SetLLMModel, etc.)       │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            Core Functionality           │
│   (Context gathering, history mgmt)     │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│             Adapter Layer               │
│    (Abstract interface to LLM APIs)     │
└───────────────────┬─────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│          LLM Implementation             │
│        (aichat, future adapters)        │
└─────────────────────────────────────────┘
```

## Key Components

### 1. Command Interface
- Entry points through Vim commands
- Command registration and argument handling
- Tab completion for commands and options

### 2. Core Functionality
- Context gathering from Vim environment
- JSON construction for LLM queries
- Conversation history management
- Buffer management (scratch buffer, snippets)
- Session persistence

### 3. Adapter Layer
- Abstract interface to LLM implementations
- Registry of available adapters
- Common operations like model listing and selection

### 4. LLM Implementation
- Concrete implementations for specific LLM tools
- Currently supports 'aichat' with plugin architecture for adding more

## Data Flow

1. **User Input**:
   - User invokes `:LLM` command with optional prompt
   - Command is processed by command handlers in plugin/llm.vim

2. **Context Gathering**:
   - Collect cursor position, active buffer content, and other visible buffers
   - Check for and apply snippets if defined
   - Add conversation history from previous interactions

3. **JSON Construction**:
   - Build structured JSON context with all relevant information
   - Include metadata like timestamps for history tracking

4. **Adapter Processing**:
   - Pass JSON context to current adapter
   - Adapter transforms and sends to actual LLM
   - LLM processes request and returns response

5. **Response Handling**:
   - Response is captured and timestamped
   - Added to conversation history
   - Displayed in scratch buffer for user

6. **Session Management** (when used):
   - Save/load entire conversation state including:
     - History buffer content
     - Snippet definitions
     - Tab/window layout

## Key Design Patterns

1. **Adapter Pattern**:
   - Abstract adapter interface separates LLM implementation details
   - New LLM backends can be added without changing core code
   - Common operations standardized across adapters

2. **Registry Pattern**:
   - Adapters self-register with central registry
   - Allows dynamic discovery of available adapters
   - User can select and configure adapters at runtime

3. **Facade Pattern**:
   - Provides simple command interface to complex underlying functionality
   - Hides implementation details behind clear commands

4. **Observer Pattern**:
   - History buffer updates in response to new interactions
   - Session state responds to changes in buffers and layout

## File Organization

```
vim-llm-assistant/
├── autoload/
│   ├── llm.vim                  # Core functionality
│   └── llm/
│       ├── adapter.vim          # Adapter interface
│       └── adapters/
│           └── aichat.vim       # aichat implementation
├── doc/
│   └── llm.txt                  # Documentation
├── plugin/
│   └── llm.vim                  # Commands and initialization
└── default-vim-role.md          # Default system prompt
```

This architecture provides several benefits:

1. **Extensibility**: New LLM backends can be added with minimal code changes
2. **Separation of Concerns**: Clear boundaries between layers of functionality
3. **Maintainability**: Modular design makes updates and fixes easier
4. **User Control**: Architecture exposes customization points for users