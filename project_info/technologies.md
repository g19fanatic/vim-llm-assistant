# Technologies and Frameworks

## Core Technologies

### Vim/Neovim
- **Role**: Host editor environment
- **Usage**: The plugin integrates with Vim's buffer management, command system, and autoload functionality
- **Requirements**: Vim 8.0+ or Neovim (for proper JSON support)

### VimScript
- **Role**: Primary implementation language
- **Usage**: All plugin code is written in VimScript
- **Key Features Used**:
  - Autoload functions for lazy loading
  - Command definitions and completion
  - Buffer manipulation and window management
  - JSON encoding/decoding
  - System command execution

### JSON
- **Role**: Data interchange format
- **Usage**: Used for:
  - Structured communication with LLM adapters
  - Session storage and retrieval
  - Context building for LLM queries
- **Implementation**: Uses Vim's built-in JSON functions for encoding/decoding

## External Dependencies

### aichat CLI Tool
- **Role**: Default adapter for LLM interaction
- **Usage**: Called as external process to communicate with LLMs
- **Integration**: Adapter in `autoload/llm/adapters/aichat.vim` wraps this tool
- **Features Used**:
  - Model listing
  - Context-aware LLM queries
  - Role-based system prompts

### Large Language Models (LLMs)
- **Role**: AI processing engines
- **Usage**: Process queries and generate responses based on context
- **Default Model**: claude-3-7-sonnet-20250219 
- **Integration**: Accessed through adapter layer, currently via aichat

## Plugin Architecture Components

### Command System
- Implements custom Vim commands with completion support
- Handles command-line parsing and argument validation
- Provides discoverability through `:help` documentation

### Buffer Management
- Custom non-file buffers for history and snippets
- Buffer-local settings for specialized behavior
- Window sizing and positioning for optimal display

### Adapter Framework
- Extensible interface for multiple LLM backends
- Self-registration mechanism for adapters
- Common operations abstracted across implementations

### Session Management
- JSON-based storage of session state
- Tab and window layout persistence
- History and snippet restoration

### Context Building
- Structured gathering of editing context
- Snippet application for targeted context
- History tracking with timestamps

## Implementation Details

### File I/O
- Temporary files for data exchange with external processes
- Session files for persistence across Vim instances
- Role files for system prompt definition

### Error Handling
- Graceful handling of adapter failures
- User feedback for processing issues
- Fallback behaviors when services are unavailable

### Performance Considerations
- Asynchronous processing where possible
- Lazy loading through autoload mechanism
- Efficient context building with snippets

## Technology Choices and Rationale

1. **VimScript vs External Languages**:
   - VimScript chosen for maximum compatibility
   - Avoids external runtime dependencies
   - Leverages built-in Vim functionality

2. **External Process vs API Libraries**:
   - External process approach provides flexibility
   - Adapter pattern allows for future direct API integration
   - Simplifies dependency management

3. **JSON as Data Format**:
   - Universal support across tools and languages
   - Built-in Vim support in modern versions
   - Human-readable for debugging and session inspection

4. **aichat as Default Adapter**:
   - CLI tool with straightforward interface
   - Supports multiple LLM providers
   - Handles authentication and API complexity