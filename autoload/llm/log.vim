" autoload/llm/log.vim — Logging infrastructure for vim-llm-assistant

" Ensure log directory exists and return its path
function! llm#log#dir() abort
  let l:dir = expand(g:llm_log_dir)
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

" Create a new per-request log directory and return paths dict
" Returns: {'dir': path, 'input': path, 'response': path, 'tools': path, 'aichat': path, 'dirname': name}
function! llm#log#create_request() abort
  let l:base = llm#log#dir()
  let l:timestamp = strftime('%Y%m%d_%H%M%S')

  " Find next sequence number for this second
  let l:seq = 1
  while isdirectory(l:base . '/' . l:timestamp . '_' . printf('%03d', l:seq))
    let l:seq += 1
  endwhile

  let l:dirname = l:timestamp . '_' . printf('%03d', l:seq)
  let l:dir = l:base . '/' . l:dirname
  call mkdir(l:dir, 'p')

  " Update 'latest' symlink (atomic via ln -sfn)
  let l:latest = l:base . '/latest'
  call system('ln -sfn ' . shellescape(l:dirname) . ' ' . shellescape(l:latest))

  return {
        \ 'dir': l:dir,
        \ 'input': l:dir . '/input.json',
        \ 'response': l:dir . '/response.md',
        \ 'tools': l:dir . '/tools.log',
        \ 'aichat': l:dir . '/aichat.log',
        \ 'dirname': l:dirname
        \ }
endfunction

" Append a line to session.log
function! llm#log#session_append(entry) abort
  let l:logfile = llm#log#dir() . '/session.log'
  call writefile([a:entry], l:logfile, 'a')
endfunction

" Get the path to the latest response log (for status line)
function! llm#log#latest_response() abort
  return expand(g:llm_log_dir) . '/latest/response.md'
endfunction

" Complete function for log types
function! llm#log#complete_types(arglead, cmdline, cursorpos) abort
  return filter(['response', 'input', 'tools', 'aichat', 'session', 'dir'],
        \ 'v:val =~ "^" . a:arglead')
endfunction

" Resolve the request directory for :LLMLog and :LLMLogTail
" Strategy: active requests (pick/prompt if >1) → last_request_dir fallback
" Returns: directory path string, or '' if nothing available
function! s:resolve_request_dir() abort
  let l:requests = llm#get_active_requests()
  if len(l:requests) == 1
    return l:requests[0].dir
  elseif len(l:requests) > 1
    " Multiple active requests — let user pick
    let l:choices = ['[LLM] Multiple active requests:']
    let l:idx = 1
    for l:req in l:requests
      let l:label = l:idx . '. ' . l:req.model . ' (' . l:req.start_time . '): "' . l:req.prompt . '"'
      call add(l:choices, l:label)
      let l:idx += 1
    endfor
    let l:pick = inputlist(l:choices)
    if l:pick < 1 || l:pick > len(l:requests)
      " Default to most recent (last in list)
      return l:requests[-1].dir
    endif
    return l:requests[l:pick - 1].dir
  endif

  " No active requests — fall back to most recently started dir
  let l:last = llm#get_last_request_dir()
  return l:last
endfunction

" Helper: focus existing window showing file, or vsplit it
function! s:open_or_focus(file) abort
  let l:bufnr = bufnr(a:file)
  if l:bufnr != -1
    for l:win in range(1, winnr('$'))
      if winbufnr(l:win) == l:bufnr
        execute l:win . 'wincmd w'
        return
      endif
    endfor
  endif
  execute 'vsplit ' . fnameescape(a:file)
endfunction

" Open the most recent log file of a given type
" Usage: :LLMLog [response|input|tools|aichat|session]
function! llm#log#open(type) abort
  let l:type = empty(a:type) ? 'response' : a:type

  if l:type ==# 'session'
    let l:file = llm#log#dir() . '/session.log'
    if !filereadable(l:file)
      echom '[LLM] No session.log found'
      return
    endif
    " Open in vsplit for direct file access
    call s:open_or_focus(l:file)
    normal! G
    let @" = l:file
    let @+ = l:file
    return
  endif

  if l:type ==# 'dir'
    call llm#log#browse()
    let @" = llm#log#dir()
    let @+ = llm#log#dir()
    return
  endif

  " Find latest request directory (active requests → last_request_dir fallback)
  let l:latest_dir = s:resolve_request_dir()
  if empty(l:latest_dir)
    echom '[LLM] No log directories found in ' . g:llm_log_dir
    return
  endif

  " Map type to filename
  let l:filemap = {'response': 'response.md', 'input': 'input.json',
        \ 'tools': 'tools.log', 'aichat': 'aichat.log'}
  let l:filename = get(l:filemap, l:type, 'response.md')
  let l:file = l:latest_dir . '/' . l:filename

  if !filereadable(l:file)
    echom '[LLM] File not found: ' . l:file
    return
  endif

  " Open in vsplit for direct file access
  call s:open_or_focus(l:file)
  normal! G
  let @" = l:file
  let @+ = l:file
endfunction

" Browse the log directory in netrw
function! llm#log#browse() abort
  let l:dir = llm#log#dir()
  execute 'edit ' . fnameescape(l:dir)
  let @" = l:dir
  let @+ = l:dir
endfunction

" Tail the current/latest response log in a terminal split
" Usage: :LLMLogTail [response|aichat]
function! llm#log#tail(type) abort
  let l:type = empty(a:type) ? 'response' : a:type
  let l:filemap = {'response': 'response.md', 'aichat': 'aichat.log'}
  let l:filename = get(l:filemap, l:type, 'response.md')

  " Resolve request directory (active requests → last_request_dir fallback)
  let l:request_dir = s:resolve_request_dir()
  if empty(l:request_dir)
    echohl WarningMsg
    echom '[LLM] No log file to tail (run :LLM first)'
    echohl None
    return
  endif
  let l:latest = l:request_dir . '/' . l:filename

  " Touch file if missing so tail -F has something to follow
  if !filereadable(l:latest)
    call writefile([], l:latest)
  endif

  let @" = l:latest
  let @+ = l:latest
  if has('terminal')
    " Check if we already have a terminal tailing this exact file.
    " Use full path in term_name to distinguish different request directories.
    let l:term_name = 'tail: ' . l:latest
    for l:buf in term_list()
      if bufname(l:buf) ==# l:term_name
        let l:win = bufwinnr(l:buf)
        if l:win != -1
          execute l:win . 'wincmd w'
          echom '[LLM] Already tailing ' . l:latest
          return
        endif
      endif
    endfor
    " Use term_start() with a List command to execute tail directly without
    " a shell. This avoids shellescape() quoting issues — when Vim's :terminal
    " doesn't invoke a shell, shell-escaped quotes become literal characters
    " in the filename, causing tail to fail on a non-existent path.
    botright call term_start(['tail', '-F', l:latest], {
          \ 'term_finish': 'close',
          \ 'term_name': l:term_name,
          \ })
    wincmd p
    echom '[LLM] Tailing ' . l:latest . ' (close terminal to stop)'
  else
    " Fallback: open file with autoread
    call llm#log#open(l:type)
    setlocal autoread
    let b:llm_tail_timer = timer_start(1000, {-> execute('checktime')}, {'repeat': -1})
    augroup LLMTail
      autocmd! * <buffer>
      autocmd FileChangedShellPost <buffer> normal! G
      autocmd BufWinLeave <buffer> call timer_stop(b:llm_tail_timer)
      autocmd BufDelete <buffer> call timer_stop(b:llm_tail_timer)
      autocmd BufWipeout <buffer> call timer_stop(b:llm_tail_timer)
    augroup END
    echom '[LLM] Tailing ' . l:type . ' log (auto-refreshing)'
  endif
endfunction

" Clean old log directories
" Usage: :LLMLogClean [days]
function! llm#log#clean(days) abort
  let l:days = empty(a:days) ? g:llm_log_max_age_days : str2nr(a:days)
  let l:dir = llm#log#dir()
  let l:removed = 0

  " Get all request directories (match YYYYMMDD_HHMMSS_NNN pattern)
  let l:dirs = glob(l:dir . '/[0-9]*_[0-9]*_[0-9]*', 0, 1)

  " Apply count-based limit first
  if g:llm_log_keep_count > 0 && len(l:dirs) > g:llm_log_keep_count
    call sort(l:dirs)
    let l:excess = l:dirs[:len(l:dirs) - g:llm_log_keep_count - 1]
    for l:d in l:excess
      call delete(l:d, 'rf')
      let l:removed += 1
    endfor
    let l:dirs = l:dirs[len(l:excess):]
  endif

  " Apply age-based limit
  if l:days > 0
    let l:cutoff = localtime() - (l:days * 86400)
    for l:d in l:dirs
      if getftime(l:d) < l:cutoff
        call delete(l:d, 'rf')
        let l:removed += 1
      endif
    endfor
  endif

  if l:removed > 0
    echom '[LLM] Cleaned ' . l:removed . ' log directories'
  endif
endfunction

" Startup cleanup (called at VimEnter via timer)
function! llm#log#startup_cleanup() abort
  if g:llm_log_level ==# 'none'
    return
  endif
  silent call llm#log#clean('')
endfunction
