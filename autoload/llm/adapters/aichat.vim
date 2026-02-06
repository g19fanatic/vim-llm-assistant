" AIChatAdapter - Implementation of the adapter interface for aichat

let s:aichat_adapter = {}

" Helper for async status updates
function! s:show_status_message() abort
  echom '[LLM] Processing...'
endfunction

" Async process with callback
function! s:aichat_adapter.process_async(json_filename, prompt, model, callback) abort
  if empty(a:model)
    let l:model = g:llm_default_model
  else
    let l:model = a:model
  endif
  
  " Generate a unique temporary filename for tool output
  let l:temp_file = tempname()
  
  " Check for command augmentation function
  let l:cmd_extra = ''
  if exists('g:llm_adapter_cmd_extra') && has_key(g:llm_adapter_cmd_extra, 'aichat')
    let l:cmd_extra_func = g:llm_adapter_cmd_extra.aichat
    if exists('*'.l:cmd_extra_func)
      let l:cmd_extra = call(l:cmd_extra_func, [a:json_filename, a:prompt, l:model])
      if !empty(l:cmd_extra) && l:cmd_extra !~ '\s$'
        let l:cmd_extra .= ' '
      endif
    endif
  endif
  
  " Check if the JSON contains file_arguments
  let l:file_flags = ''
  if filereadable(a:json_filename)
    let l:json_lines = readfile(a:json_filename)
    let l:json_data = json_decode(join(l:json_lines, "\n"))
    
    if has_key(l:json_data, 'file_arguments')
      for l:file in l:json_data.file_arguments
        let l:file_flags .= '-f ' . shellescape(l:file) . ' '
      endfor
    endif
  endif
  
  " Construct command as a list for job_start
  let l:cmd_base = ['sh', '-c', l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename)]
  if !empty(a:prompt)
    let l:cmd_base[2] .= ' -- ' . shellescape(a:prompt)
  endif
  
  " Accumulate output
  let l:output = []
  
  " Start status timer (before job callbacks to capture in closure)
  let l:timer_id = timer_start(2000, function('s:show_status_message'), {'repeat': -1})
  
  " Job callbacks
  let l:job_opts = {
        \ 'out_cb': {channel, msg -> add(l:output, msg)},
        \ 'err_cb': {channel, msg -> add(l:output, msg)},
        \ 'exit_cb': {job, status -> s:on_job_complete(l:output, l:temp_file, l:timer_id, status, a:callback)},
        \ 'out_mode': 'nl',
        \ }
  
  " Start the job
  let l:job = job_start(l:cmd_base, l:job_opts)
  
  " Check if job started successfully
  if job_status(l:job) == 'fail'
    call timer_stop(l:timer_id)
    call a:callback("ERROR: Failed to start aichat process. Check that 'aichat' command is available.")
    return
  endif
endfunction

" Process text with aichat
function! s:aichat_adapter.process(json_filename, prompt, model) abort
  if empty(a:model)
    let l:model = g:llm_default_model
  else
    let l:model = a:model
  endif
  
  " Generate a unique temporary filename for tool output
  let l:temp_file = tempname()
  
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
  
  " Check if the JSON contains file_arguments
  let l:file_flags = ''
  if filereadable(a:json_filename)
    let l:json_lines = readfile(a:json_filename)
    let l:json_data = json_decode(join(l:json_lines, "\n"))
    
    if has_key(l:json_data, 'file_arguments')
      " Build -f flags for each file
      for l:file in l:json_data.file_arguments
        let l:file_flags .= '-f ' . shellescape(l:file) . ' '
      endfor
    endif
  endif
  
  " Construct command with file flags before the main --file flag
  if empty(a:prompt)
    let l:cmd = l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename)
  else
    let l:cmd = l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename) . ' -- ' . shellescape(a:prompt)
  endif

  " Execute aichat and get the standard response
  let l:aichat_response = system(l:cmd)
  
  " Clean up the temporary file
  if filereadable(l:temp_file)
    call delete(l:temp_file)
  endif
  
  return l:aichat_response
endfunction

" Helper function to handle job completion
function! s:on_job_complete(output, temp_file, timer_id, status, callback) abort
  " Stop the specific timer for this request
  call timer_stop(a:timer_id)
  
  " Clean up temp file
  call delete(a:temp_file)
  
  " Handle exit status
  let l:result = join(a:output, "\n")
  if a:status != 0
    let l:result = "ERROR (exit code " . a:status . "):\n" . l:result
  endif
  
  call a:callback(l:result)
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