" LLMAdapter - Implementation of the adapter interface for Simon Willison's `llm` CLI

let s:llm_adapter = {}

" Internal: Load role/system prompt text from a role file on &runtimepath
function! s:load_role_text() abort
  let l:role_name = exists('g:llm_role') ? g:llm_role : 'default-vim-role'
  let l:pattern = l:role_name =~# '\.md$' ? l:role_name : l:role_name . '.md'
  let l:matches = split(globpath(&runtimepath, l:pattern), "\n")
  if !empty(l:matches)
    try
      return join(readfile(l:matches[0]), "\n")
    catch
      return ''
    endtry
  endif
  return ''
endfunction

" Process text with `llm`
function! s:llm_adapter.process(json_filename, prompt, model) abort
  " Resolve model
  let l:model = empty(a:model) ? g:llm_default_model : a:model

  " Read JSON context produced by core
  let l:json_lines = readfile(a:json_filename)

  " Build a composed prompt file:
  " - Context JSON (l:data)
  " - Optional "User request:" section
  let l:prompt_lines = ['Context JSON (l:data):']
  call extend(l:prompt_lines, l:json_lines)

  if !empty(a:prompt)
    call add(l:prompt_lines, '')
    call add(l:prompt_lines, 'User request:')
    call extend(l:prompt_lines, split(a:prompt, "\n"))
  endif

  let l:prompt_file = tempname()
  call writefile(l:prompt_lines, l:prompt_file)

  " Load role/system prompt text if available
  let l:role_text = s:load_role_text()

  " Build llm command
  let l:cmd = 'llm -m ' . shellescape(l:model) . ' -f ' . shellescape(l:prompt_file)
  if !empty(l:role_text)
    let l:cmd .= ' -s ' . shellescape(l:role_text)
  endif

  " Execute and capture response
  let l:response = system(l:cmd)
  let l:err = v:shell_error

  " Cleanup temp file
  call delete(l:prompt_file)

  " Return stdout (consistent with aichat adapter behavior)
  return l:response
endfunction

" Get available models from `llm`
function! s:llm_adapter.get_available_models() abort
  let l:models_response = system('llm models')
  let l:lines = split(l:models_response, "\n")
  let l:models = []
  for l:line in l:lines
    let l:line = trim(l:line)
    if empty(l:line)
      continue
    endif
    " Extract text after the last colon as the model id (e.g., "OpenAI Chat: gpt-4o" -> "gpt-4o")
    let l:idx = strridx(l:line, ':')
    let l:model = l:idx >= 0 ? trim(strpart(l:line, l:idx + 1)) : l:line
    if !empty(l:model)
      call add(l:models, l:model)
    endif
  endfor
  return l:models
endfunction

" Check if `llm` is available
function! s:llm_adapter.check_availability() abort
  let l:_ = system('which llm >/dev/null 2>&1')
  return v:shell_error == 0
endfunction

" Get adapter name
function! s:llm_adapter.get_name() abort
  return 'llm'
endfunction

" Register the adapter
call llm#adapter#register('llm', s:llm_adapter)
