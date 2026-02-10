" AIChatAdapter - Implementation of the adapter interface for aichat

let s:aichat_adapter = {}

" Job tracking dictionary: {job_id: {job: handle, timer_id: id, prompt: str, model: str, start_time: timestamp}}
let s:llm_jobs = {}
let s:next_job_id = 1

" Helper for async status updates
let s:timer_tick_count = {}
function! s:show_status_message(timer) abort
  if !has_key(s:timer_tick_count, a:timer)
    let s:timer_tick_count[a:timer] = 0
  endif
  let s:timer_tick_count[a:timer] += 1
  call llm#debug('s:show_status_message: Timer tick #' . s:timer_tick_count[a:timer] . ' (timer_id=' . a:timer . ')')
  let l:job_count = len(s:llm_jobs)
  let l:job_suffix = l:job_count > 1 ? ' (' . l:job_count . ' jobs)' : ''
  " Use echo instead of echom to avoid overwriting other messages
  echo '[LLM] Processing...' . l:job_suffix
endfunction

" Generate unique job ID
function! s:generate_job_id() abort
  let l:job_id = s:next_job_id
  let s:next_job_id += 1
  return l:job_id
endfunction

" List all active jobs
function! s:aichat_adapter.list_jobs() abort
  if empty(s:llm_jobs)
    return []
  endif
  
  let l:jobs = []
  for [l:job_id, l:job_info] in items(s:llm_jobs)
    let l:elapsed = localtime() - l:job_info.start_time
    let l:prompt_preview = len(l:job_info.prompt) > 50 ? l:job_info.prompt[:47] . '...' : l:job_info.prompt
    call add(l:jobs, {
          \ 'id': l:job_id,
          \ 'prompt': l:prompt_preview,
          \ 'model': l:job_info.model,
          \ 'elapsed': l:elapsed,
          \ 'status': job_status(l:job_info.job)
          \ })
  endfor
  
  return l:jobs
endfunction

" Stop a specific job
function! s:aichat_adapter.stop_job(job_id) abort
  let l:job_id_str = string(a:job_id)
  
  if !has_key(s:llm_jobs, l:job_id_str)
    echom '[LLM] Job ' . a:job_id . ' not found'
    return 0
  endif
  
  let l:job_info = s:llm_jobs[l:job_id_str]
  
  " Check if job is still running
  let l:status = job_status(l:job_info.job)
  if l:status != 'run'
    echom '[LLM] Job ' . a:job_id . ' is not running (status: ' . l:status . ')'
    call remove(s:llm_jobs, l:job_id_str)
    return 0
  endif
  
  " Stop the timer
  call timer_stop(l:job_info.timer_id)
  if has_key(s:timer_tick_count, l:job_info.timer_id)
    call remove(s:timer_tick_count, l:job_info.timer_id)
  endif
  
  " Stop the job (send SIGTERM)
  call job_stop(l:job_info.job, 'term')
  
  " Remove from tracking
  call remove(s:llm_jobs, l:job_id_str)
  
  echom '[LLM] Job ' . a:job_id . ' stopped'
  return 1
endfunction

" Async process with callback
function! s:aichat_adapter.process_async(json_filename, prompt, model, callback) abort
  call llm#debug('aichat.process_async: ENTER')
  
  " Generate unique job ID
  let l:job_id = s:generate_job_id()
  
  if empty(a:model)
    let l:model = g:llm_default_model
  else
    let l:model = a:model
  endif
  
  " Generate a unique temporary filename for tool output
  call llm#debug('aichat.process_async: Using model=' . l:model)
  
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
  
  call llm#debug('aichat.process_async: Parsed ' . (len(split(l:file_flags)) / 2) . ' file arguments')
  
  " Construct command as a list for job_start
  let l:cmd_base = ['bash', '-c', l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename)]
  if !empty(a:prompt)
    let l:cmd_base[2] .= ' -- ' . shellescape(a:prompt)
  endif
  
  " Accumulate output
  call llm#debug('aichat.process_async: Command=' . string(l:cmd_base))
  let l:output = []
  
  " Start status timer (before job callbacks to capture in closure)
  let l:timer_id = timer_start(2000, function('s:show_status_message'), {'repeat': -1})
  call llm#debug('aichat.process_async: Started timer_id=' . l:timer_id)
  
  " Job callbacks
  let l:job_opts = {
        \ 'in_io': 'null',
        \ 'out_cb': {channel, msg -> [add(l:output, msg), llm#debug('aichat.out_cb: Received ' . len(msg) . ' chars')]},
        \ 'err_cb': {channel, msg -> [add(l:output, msg), llm#debug('aichat.err_cb: ' . msg)]},
        \ 'exit_cb': {job, status -> s:on_job_complete(l:job_id, l:output, l:temp_file, l:timer_id, status, a:callback)},
        \ 'out_mode': 'nl',
        \ }
  
  call llm#debug('aichat.process_async: Starting job...')
  
  " Start the job
  let l:job = job_start(l:cmd_base, l:job_opts)
  
  let l:job_status = job_status(l:job)
  call llm#debug('aichat.process_async: Job started, status=' . l:job_status . ', job_id=' . string(l:job))
  
  " Check if job started successfully
  if job_status(l:job) == 'fail'
    call llm#debug('aichat.process_async: JOB START FAILED!')
    call timer_stop(l:timer_id)
    call a:callback("ERROR: Failed to start aichat process. Check that 'aichat' command is available.")
    return
  endif
  
  " Track the job
  let s:llm_jobs[string(l:job_id)] = {
        \ 'job': l:job,
        \ 'timer_id': l:timer_id,
        \ 'prompt': a:prompt,
        \ 'model': l:model,
        \ 'start_time': localtime()
        \ }
  
  call llm#debug('aichat.process_async: Job tracked with ID=' . l:job_id)
  echom '[LLM] Job ' . l:job_id . ' started'
  
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
    let l:cmd = 'bash -c ' . shellescape(l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename))
  else
    let l:cmd = 'bash -c ' . shellescape(l:cmd_extra . 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' ' . l:file_flags . '--file ' . shellescape(a:json_filename) . ' -- ' . shellescape(a:prompt))
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
function! s:on_job_complete(job_id, output, temp_file, timer_id, status, callback) abort
  call llm#debug('s:on_job_complete: ENTER (job_id=' . a:job_id . ', timer_id=' . a:timer_id . ', status=' . a:status . ', output_lines=' . len(a:output) . ')')
  
  " Remove job from tracking (only if it still exists)
  if has_key(s:llm_jobs, string(a:job_id))
    call remove(s:llm_jobs, string(a:job_id))
  endif
  
  " Stop the specific timer for this request
  call timer_stop(a:timer_id)
  
  " Clean up timer tick counter
  if has_key(s:timer_tick_count, a:timer_id)
    call remove(s:timer_tick_count, a:timer_id)
  endif
  
  call llm#debug('s:on_job_complete: Timer stopped, total output=' . len(join(a:output, "\n")) . ' chars')
  
  " Clean up temp file
  call delete(a:temp_file)
  
  " Handle exit status
  let l:result = join(a:output, "\n")
  if a:status != 0
    let l:result = "ERROR (exit code " . a:status . "):\n" . l:result
  endif
  
  call llm#debug('s:on_job_complete: Calling final callback')
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