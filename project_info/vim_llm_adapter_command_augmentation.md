# vim-llm-assistant Command Augmentation Feature

## Overview
This document details the implementation of a command augmentation feature for the vim-llm-assistant plugin. This feature allows users to define functions that return shell commands or environment variables to be prepended to adapter process calls.

## Implementation Details

### Purpose
The primary purpose of this feature is to allow users to modify the environment for command execution, particularly setting environment variables, before the adapter's process function runs.

### How It Works
1. Users define a function in their vimrc that returns a string to be prepended to the command
2. This function is registered in a dictionary mapping adapters to their respective functions
3. When the adapter's process function is called, it checks for and executes this function
4. The returned string is prepended to the command, allowing it to set environment variables or perform other shell operations

### Code Changes
The implementation adds functionality to the `aichat.vim` adapter to check for a command augmentation function and prepend its output to the command:

```vim
" Check for command augmentation function
let l:cmd_extra = ''
if exists('g:llm_adapter_cmd_extra') && has_key(g:llm_adapter_cmd_extra, 'aichat')
  let l:cmd_extra_func = g:llm_adapter_cmd_extra.aichat
  if exists('*'.l:cmd_extra_func)
    " Call the function with parameters so it can make decisions
    let l:cmd_extra = call(l:cmd_extra_func, [a:json_filename, a:prompt, l:model])
    " Add space if not empty and doesn't end with space
    if !empty(l:cmd_extra) && l:cmd_extra !~ '\s$'
      let l:cmd_extra .= ' '
    endif
  endif
endif

" Use the prefix in the command
let l:cmd = l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' --file ' . shellescape(a:json_filename)
```

## User Configuration

Users can configure this feature by adding the following to their vimrc:

```vim
" Command augmentation function for aichat adapter
function! SetAIChatEnvironment(json_filename, prompt, model) abort
  " Example: Set different API keys based on model type
  if a:model =~ 'aws:anthropic'
    return 'ANTHROPIC_API_KEY=$(aws secretsmanager get-secret-value --secret-id anthropic-api-key --query SecretString --output text)'
  elseif a:model =~ 'gpt-4'
    return 'OPENAI_API_KEY=$(aws secretsmanager get-secret-value --secret-id openai-api-key --query SecretString --output text)'
  else
    return 'MODEL_TYPE=' . a:model
  endif
endfunction

" Register the command augmentation function
let g:llm_adapter_cmd_extra = {
  \ 'aichat': 'SetAIChatEnvironment'
  \ }
```

## Benefits

This implementation provides several benefits:
1. Dynamic environment variable setting based on model type
2. Ability to execute shell commands before the adapter process
3. Flexibility to customize the command execution environment
4. Clean separation between adapter code and user configuration
5. Support for conditional logic in command preparation

## Use Cases

Common use cases include:
- Setting different API keys for different models
- Loading environment variables from credential managers
- Configuring proxy settings for specific requests
- Setting up authentication tokens dynamically