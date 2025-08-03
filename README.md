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
Plug 'yourusername/vim-llm-assistant'
```

### Using Vundle

```vim
Plugin 'yourusername/vim-llm-assistant'
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
let g:llm_default_model = 'Alfred:o3-mini'

" Set LLM role
let g:llm_role = 'default-vim-role'
```

## Requirements

This plugin requires the 'aichat' command-line tool to be installed and configured on your system.

## License

MIT License