" AIChatAdapter - Implementation of the adapter interface for aichat

" Debug logging functionality
function! s:debug_log(message) abort
  let l:debug_file = expand('~/.vim/llm_debug.log')
  let l:timestamp = strftime("%Y-%m-%d %H:%M:%S")
  let l:log_line = l:timestamp . " - " . a:message
  
  " Append to log file
  call writefile([l:log_line], l:debug_file, "a")
endfunction

let s:aichat_adapter = {}

" Append text to the scratch buffer
function! s:append_to_scratch_buffer(bufnr, text) abort
  if a:bufnr == -1 || !bufexists(a:bufnr)
    " Buffer doesn't exist, can't append
    return
  endif
  call s:debug_log("Attempting to append to buffer " . a:bufnr . " (exists: " . bufexists(a:bufnr) . ", loaded: " . bufloaded(a:bufnr) . ")")
  
  " Check if the buffer is loaded
  if !bufloaded(a:bufnr)
    " Load the buffer if it's not loaded
    execute 'buffer ' . a:bufnr
    let l:switched_buffer = 1
  else
    let l:switched_buffer = 0
  endif
  
  " Get the last line number
  let l:last_line = getbufinfo(a:bufnr)[0].linecount
  
  " Append the text to the buffer
  call appendbufline(a:bufnr, l:last_line, split(a:text, "\n"))
  
  " If we're in the scratch buffer, scroll to the bottom
  if bufnr('%') == a:bufnr
    normal! G
    redraw
  endif
  
  call s:debug_log("Text appended to buffer " . a:bufnr . ", lines: " . len(split(a:text, "\n")))
endfunction

" Callback for standard output (and redirected stderr)
function! s:aichat_output_callback(channel, msg) abort
  call s:debug_log("Output callback triggered with message length: " . len(a:msg))
  " Get the scratch buffer number from job options
  let l:job = ch_getjob(a:channel)
  let l:job_info = job_info(l:job)
  let l:scratch_bufnr = l:job_info.options.scratch_bufnr
  call s:debug_log("Retrieved scratch_bufnr from job options: " . l:scratch_bufnr . " (exists: " . bufexists(l:scratch_bufnr) . ")")
  
  " Append the message to the scratch buffer
  call s:append_to_scratch_buffer(l:scratch_bufnr, a:msg)
  
  call s:debug_log("Redrawing screen after output callback")
  " Force redraw to show updates as they come in
  redraw
endfunction

" Callback when the job exits
function! s:aichat_exit_callback(job, status) abort
  let l:job_info = job_info(a:job)
  let l:scratch_bufnr = l:job_info.options.scratch_bufnr
  let l:temp_file = l:job_info.options.temp_file
  
  " Add a blank line at the end to separate from next response
  call s:append_to_scratch_buffer(l:scratch_bufnr, "")
  
  " Calculate and show processing time
  let l:start_time = l:job_info.options.start_time
  let l:elapsed = localtime() - l:start_time
  call s:append_to_scratch_buffer(l:scratch_bufnr, "Processing completed in " . l:elapsed . " seconds.")
  
  " Clean up the temporary file
  if filereadable(l:temp_file)
    call delete(l:temp_file)
  endif
  
  " Release the global job reference
  let g:llm_current_job = 0
endfunction

" Process text with aichat
function! s:aichat_adapter.process(json_filename, prompt, model) abort
  if empty(a:model)
    let l:model = g:llm_default_model
  else
    let l:model = a:model
  endif
  
  " Generate a unique temporary filename for tool output
  " This triggers a custom version of aichat to keep toolcalls in the chat
  " response for CMD style calls
  let l:temp_file = tempname()
  
  " Prepare the command with stderr redirected to stdout
  if empty(a:prompt)
    let l:cmd = 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' --file ' . shellescape(a:json_filename) . ' 2>&1'
  else
    let l:cmd = 'LLM_OUTPUT=' . shellescape(l:temp_file) . ' aichat --role ' . g:llm_role . ' --model ' . l:model . ' --file ' . shellescape(a:json_filename) . ' -- ' . shellescape(a:prompt) . ' 2>&1'
  endif

  " Set up job options with callbacks
  let l:job_options = {
        \ 'out_cb': function('s:aichat_output_callback'),
        \ 'err_io': 'out',
        \ 'exit_cb': function('s:aichat_exit_callback'),
        \ 'mode': 'nl',
        \ 'scratch_bufnr': exists('g:llm_scratch_bufnr') ? g:llm_scratch_bufnr : -1,
        \ 'start_time': localtime(),
        \ 'temp_file': l:temp_file
        \ }
  
  " Start the job and return the job object
  let l:job = job_start(l:cmd, l:job_options)
  return l:job
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
