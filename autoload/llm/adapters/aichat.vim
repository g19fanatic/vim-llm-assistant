" AIChatAdapter - Implementation of the adapter interface for aichat

let s:aichat_adapter = {}

" Process text with aichat
function! s:aichat_adapter.process(json_filename, prompt, model) abort
  if empty(a:model)
    let l:model = g:llm_default_model
  else
    let l:model = a:model
  endif
  
  if empty(a:prompt)
    let l:cmd= 'aichat --role ' . g:llm_role . ' --model ' . l:model . ' --file ' . shellescape(a:json_filename)
  else
    let l:cmd= 'aichat --role ' . g:llm_role . ' --model ' . l:model . ' --file ' . shellescape(a:json_filename) . ' -- ' . shellescape(a:prompt)
  endif

  let l:aichat_response = system(l:cmd)
  return l:aichat_response
endfunction

" Get available models from aichat
function! s:aichat_adapter.get_available_models() abort
  let l:cmd = 'aichat --list-models'
  let l:models_response = system(l:cmd)
  return split(l:models_response, "\n")
endfunction

" Check if aichat is available
function! s:aichat_adapter.check_availability() abort
  let l:check_cmd = 'which aichat >/dev/null 2>&1'
  let l:exit_code = system(l:check_cmd)
  return v:shell_error == 0
endfunction

" Get adapter name
function! s:aichat_adapter.get_name() abort
  return 'aichat'
endfunction

" Register the adapter
call llm#adapter#register('aichat', s:aichat_adapter)