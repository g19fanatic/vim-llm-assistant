" Adapter interface and registry for LLM backends

" Registry of available adapters
let s:adapters = {}
let s:current_adapter = ''

" Register an adapter
function! llm#adapter#register(name, adapter) abort
  let s:adapters[a:name] = a:adapter
  
  " If this adapter matches the default adapter, make it current
  if exists('g:llm_default_adapter') && a:name ==# g:llm_default_adapter
    let s:current_adapter = a:name
  " Otherwise, if no current adapter is set, make this one current
  elseif empty(s:current_adapter)
    let s:current_adapter = a:name
  endif
endfunction

" Get the current adapter
function! llm#adapter#get_current() abort
  if empty(s:current_adapter) || !has_key(s:adapters, s:current_adapter)
    throw "No LLM adapter is currently selected"
  endif
  return s:adapters[s:current_adapter]
endfunction

" Set the current adapter
function! llm#adapter#set_current(name) abort
  if !has_key(s:adapters, a:name)
    throw "Adapter '" . a:name . "' is not registered"
  endif
  let s:current_adapter = a:name
endfunction

" List all registered adapters
function! llm#adapter#list() abort
  return keys(s:adapters)
endfunction

" Define the adapter interface (documentation only)
" Each adapter must implement the following functions:
"
" process(json_filename, prompt, model): Process a request with the LLM
" get_available_models(): Return a list of available models
" check_availability(): Check if the adapter is available/installed
" get_name(): Return the name of the adapter