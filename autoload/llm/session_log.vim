" Session Status Logger - JSONL event writer for vim-llm-assistant
" Provides real-time session instrumentation via JSONL log files

let s:session_counter = 0

" Generate a unique session ID: <timestamp>-<counter>
function! llm#session_log#new_session_id() abort
  let s:session_counter += 1
  return strftime('%Y%m%d_%H%M%S') . '-' . s:session_counter
endfunction

" Get the session log directory (respects g:llm_session_log_dir)
function! llm#session_log#log_dir() abort
  if exists('g:llm_session_log_dir') && !empty(g:llm_session_log_dir)
    let l:dir = expand(g:llm_session_log_dir)
  else
    let l:dir = expand('~/.local/share/vim-llm-assistant/logs')
  endif
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

" Get the JSONL log file path for a session
function! llm#session_log#log_path(session_id) abort
  return llm#session_log#log_dir() . '/' . a:session_id . '_session.jsonl'
endfunction

" Get the per-session aichat log path (from AICHAT_LOG_PATH env var)
function! llm#session_log#aichat_log_path() abort
  return $AICHAT_LOG_PATH
endfunction

" Write a JSONL event to the session log
" All events share: {ts, session_id, event_type, ...payload}
function! llm#session_log#emit(session_id, event_type, payload) abort
  if exists('g:llm_session_log_enabled') && !g:llm_session_log_enabled
    return
  endif
  let l:event = copy(a:payload)
  let l:event.ts = strftime('%Y-%m-%dT%H:%M:%S')
  let l:event.session_id = a:session_id
  let l:event.event_type = a:event_type
  let l:log_path = llm#session_log#log_path(a:session_id)
  call writefile([json_encode(l:event)], l:log_path, 'a')
endfunction

" Emit session_start event
function! llm#session_log#start(session_id, prompt, model) abort
  call llm#session_log#emit(a:session_id, 'session_start', {
        \ 'prompt': a:prompt,
        \ 'model': a:model,
        \ 'aichat_log': llm#session_log#aichat_log_path(),
        \ })
endfunction

" Emit session_end event
function! llm#session_log#end(session_id, exit_status) abort
  call llm#session_log#emit(a:session_id, 'session_end', {
        \ 'exit_status': a:exit_status,
        \ })
endfunction

" Emit heartbeat event (from timer ticks)
function! llm#session_log#heartbeat(session_id, elapsed, job_count) abort
  call llm#session_log#emit(a:session_id, 'heartbeat', {
        \ 'elapsed_s': a:elapsed,
        \ 'active_jobs': a:job_count,
        \ })
endfunction

" Emit stream_event for ralph/subagent markers parsed from out_cb
function! llm#session_log#stream_event(session_id, sub_type, detail) abort
  call llm#session_log#emit(a:session_id, 'stream_event', {
        \ 'sub_type': a:sub_type,
        \ 'detail': a:detail,
        \ })
endfunction

" Invoke the aichat log parser after job completion (async via job_start)
" Appends token_usage and tool_call events to the JSONL log
function! llm#session_log#parse_aichat_log(session_id) abort
  let l:parser = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h') . '/scripts/parse_aichat_log.py'
  if !filereadable(l:parser)
    call llm#debug('session_log: parser not found at ' . l:parser)
    return
  endif
  let l:aichat_log = llm#session_log#aichat_log_path()
  if empty(l:aichat_log) || !filereadable(l:aichat_log)
    call llm#debug('session_log: no aichat log at ' . l:aichat_log)
    return
  endif
  let l:jsonl_path = llm#session_log#log_path(a:session_id)
  let l:cmd = ['python3', l:parser,
        \ '--aichat-log', l:aichat_log,
        \ '--session-id', a:session_id,
        \ '--output', l:jsonl_path]
  call job_start(l:cmd, {
        \ 'in_io': 'null',
        \ 'out_io': 'null',
        \ 'err_cb': {ch, msg -> llm#debug('session_log parser err: ' . msg)},
        \ })
endfunction
