" Debug logging helper
function! llm#debug(msg) abort
  if exists('g:llm_debug') && g:llm_debug
    echom '[LLM DEBUG ' . strftime('%H:%M:%S') . '] ' . a:msg
  endif
endfunction

" Request registry: tracks all active LLM requests and last-known dir
let s:active_requests = []
let s:last_request_dir = ''

" Script-level dict storing per-turn and totals from the most recent prune pass
let s:last_prune_stats = {}

" Cursor position at time of last llm#run() call (passed to adapter via env vars)
let s:last_cursor_pos = [0, 0]

" Tool-output pruning config globals (set in vimrc to override defaults):
"   g:llm_prune_enabled    (default 1)   — set to 0 to disable pruning entirely
"   g:llm_prune_recency    (default 3)   — number of recent turns to keep intact
"   g:llm_prune_min_chars  (default 200) — skip pruning blocks smaller than N chars

" Backward-compat shim: returns log_paths of the most recent active request
" (used by aichat adapter at adapters/aichat.vim:134)
function! llm#get_current_log_paths() abort
  if !empty(s:active_requests)
    return s:active_requests[-1].log_paths
  endif
  return {}
endfunction

" Return list of all active (running) requests
function! llm#get_active_requests() abort
  return s:active_requests
endfunction

" Return the directory of the most recently started request (persists after completion)
function! llm#get_last_request_dir() abort
  return s:last_request_dir
endfunction

" Return cursor position from the most recently started llm#run() call
function! llm#get_cursor_pos() abort
  return s:last_cursor_pos
endfunction


" Helper: JSON encoding wrapper.
" For llm#run context payloads, enforce deterministic top-level key order
" so prompt-caching prefix stability does not depend on Vim dict ordering.
function! llm#encode(obj) abort
  if type(a:obj) == type({})
    let l:ordered_keys = [
          \ 'llm_history',
          \ 'llm_history_turns',
          \ 'buffers',
          \ 'file_arguments',
          \ 'cwd',
          \ 'active_buffer',
          \ 'prompt',
          \ '_cache_hints',
          \ ]

    " Only apply ordered top-level emission for the llm#run context shape.
    if has_key(a:obj, 'buffers') && has_key(a:obj, 'active_buffer')
      let l:parts = []
      let l:seen = {}

      for l:key in l:ordered_keys
        if has_key(a:obj, l:key)
          call add(l:parts, json_encode(l:key) . ':' . json_encode(a:obj[l:key]))
          let l:seen[l:key] = 1
        endif
      endfor

      " Preserve any unexpected extra keys deterministically as well.
      let l:remaining = []
      for l:key in keys(a:obj)
        if !has_key(l:seen, l:key)
          call add(l:remaining, l:key)
        endif
      endfor
      call sort(l:remaining)
      for l:key in l:remaining
        call add(l:parts, json_encode(l:key) . ':' . json_encode(a:obj[l:key]))
      endfor

      return '{' . join(l:parts, ',') . '}'
    endif
  endif

  return json_encode(a:obj)
endfunction

" Parse [LLM-Scratch] buffer history into structured turn array.
" Each turn is a dict: {'timestamp': '...', 'user': '...', 'assistant': '...'}
" The scratch buffer format is:
"   ==== <timestamp> ====
"   Prompt: <user message>
"   <assistant response lines...>
"   <blank line>
" Returns: List of turn dicts (empty list if no scratch buffer or no turns)
function! llm#parse_history_turns() abort
  if !exists('g:llm_scratch_bufnr') || !bufexists(g:llm_scratch_bufnr)
    return []
  endif

  let l:lines = getbufline(g:llm_scratch_bufnr, 1, '$')
  let l:turns = []
  let l:current_turn = {}
  let l:collecting = ''
  let l:content = []

  for l:line in l:lines
    if l:line =~# '^==== .* ====$'
      " Save previous turn if exists
      if !empty(l:current_turn)
        if l:collecting ==# 'assistant' && !empty(l:content)
          let l:current_turn.assistant = s:trim_blank_lines(join(l:content, "\n"))
        endif
        call add(l:turns, l:current_turn)
      endif
      " Start new turn
      let l:timestamp = matchstr(l:line, '^==== \zs.*\ze ====$')
      let l:current_turn = {'timestamp': l:timestamp, 'user': '', 'assistant': ''}
      let l:content = []
      let l:collecting = ''
    elseif l:line =~# '^Prompt: ' && !empty(l:current_turn) && l:collecting ==# ''
      let l:current_turn.user = l:line[8:]
      let l:collecting = 'assistant'
      let l:content = []
    else
      if l:collecting ==# 'assistant'
        call add(l:content, l:line)
      endif
    endif
  endfor

  " Don't forget last turn
  if !empty(l:current_turn)
    if l:collecting ==# 'assistant' && !empty(l:content)
      let l:current_turn.assistant = s:trim_blank_lines(join(l:content, "\n"))
    endif
    call add(l:turns, l:current_turn)
  endif

  " Apply pruning to older turns if enabled (g:llm_prune_enabled, g:llm_prune_recency)
  if get(g:, 'llm_prune_enabled', 1)
    let l:recency = get(g:, 'llm_prune_recency', 3)
    let l:num_turns = len(l:turns)
    let l:i = 0
    let l:stats_turns = []
    let l:total_before = 0
    let l:total_after = 0
    while l:i < l:num_turns
      let l:is_recent = (l:i >= l:num_turns - l:recency)
      let l:before_len = len(l:turns[l:i].assistant)
      let l:turns[l:i].assistant = llm#prune_tool_outputs(l:turns[l:i].assistant, l:is_recent)
      let l:after_len = len(l:turns[l:i].assistant)
      let l:pct = (l:before_len > 0)
            \ ? (100 * (l:before_len - l:after_len) / l:before_len)
            \ : 0
      if get(g:, 'llm_debug', 0)
        call llm#debug('[LLM Prune] Turn ' . l:i . ': '
              \ . l:before_len . '->' . l:after_len
              \ . ' chars (' . l:pct . '% reduction)'
              \ . (l:is_recent ? ' [recent]' : ''))
      endif
      call add(l:stats_turns, {
            \ 'index':     l:i,
            \ 'before':    l:before_len,
            \ 'after':     l:after_len,
            \ 'pct':       l:pct,
            \ 'is_recent': l:is_recent,
            \ })
      let l:total_before += l:before_len
      let l:total_after  += l:after_len
      let l:i += 1
    endwhile
    let s:last_prune_stats = {
          \ 'turns':        l:stats_turns,
          \ 'total_before': l:total_before,
          \ 'total_after':  l:total_after,
          \ }
    if get(g:, 'llm_debug', 0)
      let l:total_pct = (l:total_before > 0)
            \ ? (100 * (l:total_before - l:total_after) / l:total_before)
            \ : 0
      call llm#debug('[LLM Prune] Total: '
            \ . l:total_before . '->' . l:total_after
            \ . ' chars (' . l:total_pct . '% reduction across '
            \ . l:num_turns . ' turn(s))')
    endif
  endif

  return l:turns
endfunction

" Helper: trim leading and trailing blank lines from a string
function! s:trim_blank_lines(text) abort
  let l:result = substitute(a:text, '^\n\+', '', '')
  let l:result = substitute(l:result, '\n\+$', '', '')
  return l:result
endfunction

" Detect tool output blocks in assistant response text.
" Scans a multiline string for tool call markers of the form:
"   **~~ Call <tool_name> {<json_args>} ~~**
" Returns a list of dicts: [{'start': N, 'end': M, 'name': 'tool_name', 'chars': K}]
" where start/end are 0-based line indices within the split text.
"   start = index of the Call marker line itself
"   end   = index of the last output line (before next marker, or last line)
"   chars = character count of the output lines (after marker up to end inclusive)
"
" Base detection for tool call markers only.
" Tasks 2 and 3 extend detection with safe_script_executor and ERROR blocks.
function! llm#detect_tool_blocks(text) abort
  " Thin wrapper: delegates to the unified single-pass detector (Epic 3) and
  " returns only the tool-block portion. Output is byte-identical to the former
  " standalone implementation. See llm#detect_all_blocks() for the state machine.
  return llm#detect_all_blocks(a:text).tool_blocks
endfunction

" Detect ERROR output blocks in assistant response text.
" Handles two patterns:
"   ERROR: tool execution failed: <name>
"   ERROR (exit code N): ...
"
" Blocks end at:
"   - A blank line followed by non-error, non-marker narrative text
"   - A **~~ Call <name> ~~** marker (tool call marker from detect_tool_blocks)
"   - Another ERROR marker (starts a new block)
"   - End of text
"
" Returns same [{start, end, name, chars}] format as llm#detect_tool_blocks().
function! llm#detect_error_blocks(text) abort
  " Thin wrapper: delegates to the unified single-pass detector (Epic 3) and
  " returns only the error-block portion. Output is byte-identical to the former
  " standalone implementation. See llm#detect_all_blocks() for the state machine.
  return llm#detect_all_blocks(a:text).error_blocks
endfunction

" Unified single-pass block detection (Epic 3 refactor foundation).
" Splits the text ONCE and runs BOTH the tool-block and error-block state
" machines simultaneously over the same lines, returning both result lists:
"   {'tool_blocks': [...], 'error_blocks': [...]}
" Each list uses the identical [{start, end, name, chars}] format produced by
" llm#detect_tool_blocks() and llm#detect_error_blocks() respectively.
"
" The two machines are independent (each appends only to its own list); a Call
" marker starts a tool block AND finalizes any open error block but never starts
" an error block. Merging them into one pass yields byte-identical output while
" splitting the text a single time. Tasks 8/9 wire the public functions to this.
function! llm#detect_all_blocks(text) abort
  let l:lines = split(a:text, "\n", 1)

  " --- Tool-block state (mirrors llm#detect_tool_blocks) ---
  let l:t_blocks = []
  let l:t_state = 'idle'
  let l:t_start = -1
  let l:t_name = ''

  " --- Error-block state (mirrors llm#detect_error_blocks) ---
  let l:e_blocks = []
  let l:e_state = 'idle'
  let l:e_start = -1
  let l:e_name = ''
  let l:e_blank_pending = 0

  let l:idx = 0
  for l:line in l:lines
    " Shared line classification
    let l:is_call_marker = (l:line =~# '^\*\*[~][~] Call \S\+ {')
    let l:is_blank = (l:line =~# '^\s*$')
    let l:is_error1 = (l:line =~# '^ERROR: tool execution failed:')
    let l:is_error2 = (l:line =~# '^ERROR (exit code \d\+):')
    let l:is_any_start = l:is_call_marker || l:is_error1 || l:is_error2

    " ===== ERROR machine (llm#detect_error_blocks logic) =====
    " Terminate current error block when a blank line is followed by non-blank
    " narrative that is NOT another error/call marker.
    if l:e_state ==# 'in_block' && l:e_blank_pending && !l:is_blank && !l:is_any_start
      let l:end_idx = l:idx - 2
      if l:end_idx < l:e_start
        let l:end_idx = l:e_start
      endif
      let l:output_lines = l:lines[(l:e_start + 1) : l:end_idx]
      let l:chars = len(join(l:output_lines, "\n"))
      call add(l:e_blocks, {
            \ 'start': l:e_start,
            \ 'end':   l:end_idx,
            \ 'name':  l:e_name,
            \ 'chars': l:chars
            \ })
      let l:e_state = 'idle'
    endif

    let l:e_blank_pending = l:is_blank

    if l:is_any_start
      if l:e_state ==# 'in_block'
        let l:end_idx = l:idx - 1
        let l:output_lines = l:lines[(l:e_start + 1) : l:end_idx]
        let l:chars = len(join(l:output_lines, "\n"))
        call add(l:e_blocks, {
              \ 'start': l:e_start,
              \ 'end':   l:end_idx,
              \ 'name':  l:e_name,
              \ 'chars': l:chars
              \ })
        let l:e_state = 'idle'
      endif

      if l:is_error1
        let l:e_name = matchstr(l:line, '^ERROR: tool execution failed: \zs\S\+')
        if empty(l:e_name)
          let l:e_name = 'error_unknown'
        endif
        let l:e_start = l:idx
        let l:e_state = 'in_block'
      elseif l:is_error2
        let l:exit_code = matchstr(l:line, '^ERROR (exit code \zs\d\+')
        let l:e_name = 'error_exit_' . (empty(l:exit_code) ? 'N' : l:exit_code)
        let l:e_start = l:idx
        let l:e_state = 'in_block'
      endif
      " is_call_marker: do NOT start an error block; detect_tool_blocks handles it.
    endif

    " ===== TOOL machine (llm#detect_tool_blocks logic) =====
    if l:is_call_marker
      if l:t_state !=# 'idle'
        let l:end_idx = l:idx - 1
        let l:output_lines = l:lines[(l:t_start + 1) : l:end_idx]
        let l:chars = len(join(l:output_lines, "\n"))
        call add(l:t_blocks, {
              \ 'start': l:t_start,
              \ 'end':   l:end_idx,
              \ 'name':  l:t_name,
              \ 'chars': l:chars
              \ })
      endif
      let l:t_name = matchstr(l:line, '^\*\*[~][~] Call \zs\S\+\ze {')
      let l:t_start = l:idx
      let l:t_state = 'in_block'

    elseif l:t_state ==# 'idle' && l:line =~# '^╔'
      let l:t_name = 'safe_script_executor'
      let l:t_start = l:idx
      let l:t_state = 'in_box'

    elseif l:t_state ==# 'in_box' && l:line =~# '^╚'
      let l:end_idx = l:idx
      let l:output_lines = l:lines[(l:t_start + 1) : l:end_idx]
      let l:chars = len(join(l:output_lines, "\n"))
      call add(l:t_blocks, {
            \ 'start': l:t_start,
            \ 'end':   l:end_idx,
            \ 'name':  l:t_name,
            \ 'chars': l:chars
            \ })
      let l:t_state = 'idle'

    elseif l:t_state ==# 'idle' && l:line =~# '^\[..\:..\:..\] Running direct task'
      let l:t_name = 'safe_script_executor'
      let l:t_start = l:idx
      let l:t_state = 'in_timestamp'

    elseif l:t_state ==# 'in_timestamp' && l:line =~# '^\[..\:..\:..\] Completed direct task'
      let l:end_idx = l:idx
      let l:output_lines = l:lines[(l:t_start + 1) : l:end_idx]
      let l:chars = len(join(l:output_lines, "\n"))
      call add(l:t_blocks, {
            \ 'start': l:t_start,
            \ 'end':   l:end_idx,
            \ 'name':  l:t_name,
            \ 'chars': l:chars
            \ })
      let l:t_state = 'idle'
    endif

    let l:idx += 1
  endfor

  " Finalize any still-open TOOL block (no trailing close marker)
  if l:t_state !=# 'idle'
    let l:end_idx = l:idx - 1
    let l:output_lines = l:lines[(l:t_start + 1) : l:end_idx]
    let l:chars = len(join(l:output_lines, "\n"))
    call add(l:t_blocks, {
          \ 'start': l:t_start,
          \ 'end':   l:end_idx,
          \ 'name':  l:t_name,
          \ 'chars': l:chars
          \ })
  endif

  " Finalize any still-open ERROR block at end of text
  if l:e_state ==# 'in_block'
    let l:end_idx = l:idx - 1
    let l:output_lines = l:lines[(l:e_start + 1) : l:end_idx]
    let l:chars = len(join(l:output_lines, "\n"))
    call add(l:e_blocks, {
          \ 'start': l:e_start,
          \ 'end':   l:end_idx,
          \ 'name':  l:e_name,
          \ 'chars': l:chars
          \ })
  endif

  if get(g:, 'llm_debug', 0)
    call llm#debug('[LLM Detect] Unified: ' . len(l:t_blocks) . ' tool block(s), '
          \ . len(l:e_blocks) . ' error block(s) in ' . len(l:lines) . ' lines')
  endif

  return {'tool_blocks': l:t_blocks, 'error_blocks': l:e_blocks}
endfunction

" Prune tool output blocks from assistant response text.
"
" If is_recent is true, returns the text unchanged (recent turns preserved).
" If is_recent is false, replaces the OUTPUT lines of each detected tool block
" (i.e., everything AFTER the Call/ERROR marker line through the end of the block)
" with a compact summary line:
"   [Tool: <name> — <N> chars removed]
" The marker line itself (Call or ERROR header) is always preserved.
" All non-tool narrative text is preserved verbatim.
"
" Detects blocks via:
"   llm#detect_tool_blocks()  - Call marker and safe_script_executor/box blocks
"   llm#detect_error_blocks() - ERROR: and ERROR (exit code N): blocks
"
" Config:
"   g:llm_prune_enabled    (default 1) - set to 0 to disable entirely
"   g:llm_prune_min_chars  (default 200) - only prune blocks larger than N chars
"
" Returns: pruned (or unchanged) assistant text string.
function! llm#prune_tool_outputs(assistant_text, is_recent) abort
  " Short-circuit: recent turns are returned untouched
  if a:is_recent
    return a:assistant_text
  endif

  " Kill switch
  if !get(g:, 'llm_prune_enabled', 1)
    return a:assistant_text
  endif

  " Detect tool call blocks (Call markers, safe_script_executor boxes, timestamps)
  " Detect tool + error blocks in a single pass (splits text once internally)
  let l:detected = llm#detect_all_blocks(a:assistant_text)

  " Combine tool and error blocks into one list
  let l:all_blocks = l:detected.tool_blocks + l:detected.error_blocks

  " Nothing to prune
  if empty(l:all_blocks)
    return a:assistant_text
  endif

  " Overlap safety: blocks may overlap (e.g. an ERROR block nested inside a
  " tool Call block's output range). This is safe by suppression — the outer
  " block's skip_set marks ALL of its output lines (including the inner block's
  " marker line), so the inner block's placeholder_after entry is never emitted
  " during reconstruction. No duplicate "chars removed" line results.
  " Sort blocks by ascending start-line index
  call sort(l:all_blocks, {a, b -> a.start - b.start})

  " Split text preserving empty lines (keepempty=1 keeps line indices intact)
  let l:lines = split(a:assistant_text, "\n", 1)
  let l:min_chars = get(g:, 'llm_prune_min_chars', 200)

  " Build skip_set: line indices to suppress in output
  " Build placeholder_after: line index -> replacement summary string
  let l:skip_set = {}
  let l:placeholder_after = {}

  for l:block in l:all_blocks
    let l:output_start = l:block.start + 1
    let l:output_end   = l:block.end

    " Skip degenerate blocks with no output lines
    if l:output_start > l:output_end
      continue
    endif

    " Compute actual byte-length of output lines to be removed
    let l:output_lines = l:lines[l:output_start : l:output_end]
    let l:output_chars = len(join(l:output_lines, "\n"))

    " Respect minimum-chars threshold - small blocks are not worth pruning
    if l:output_chars < l:min_chars
      continue
    endif

    " Mark output lines for skipping
    let l:i = l:output_start
    while l:i <= l:output_end
      let l:skip_set[l:i] = 1
      let l:i += 1
    endwhile

    " Record the one-line placeholder to insert after the marker line
    let l:placeholder_after[l:block.start] =
          \ '[Tool: ' . l:block.name . ' — ' . l:output_chars . ' chars removed]'
  endfor

  " Reconstruct the text line by line
  let l:result_lines = []
  let l:idx = 0
  for l:line in l:lines
    if !has_key(l:skip_set, l:idx)
      call add(l:result_lines, l:line)
      if has_key(l:placeholder_after, l:idx)
        call add(l:result_lines, l:placeholder_after[l:idx])
      endif
    endif
    let l:idx += 1
  endfor

  if get(g:, 'llm_debug', 0)
    let l:orig_len = len(a:assistant_text)
    let l:pruned_text = join(l:result_lines, "\n")
    let l:pruned_len = len(l:pruned_text)
    let l:pct = (l:orig_len > 0) ? (100 * (l:orig_len - l:pruned_len) / l:orig_len) : 0
    call llm#debug('[LLM Prune] ' . l:orig_len . '->' . l:pruned_len
          \ . ' chars (' . l:pct . '% reduction)')
  endif

  return join(l:result_lines, "\n")
endfunction


" Helper: Open or reuse a global scratch buffer for LLM responses
function! llm#open_scratch_buffer() abort
  " If our scratch buffer (LLM history) already exists...
  if exists('g:llm_scratch_bufnr')
    " If the buffer happens to be loaded, try to bring it into view.
    if bufloaded(g:llm_scratch_bufnr)
      " Check if it's visible in any window.
      for win in range(1, winnr('$'))
        if winbufnr(win) == g:llm_scratch_bufnr
          execute win . "wincmd w"
          return g:llm_scratch_bufnr
        endif
      endfor
      " Not visible? Open it in a vertical split.
      execute 'vertical sbuffer ' . g:llm_scratch_bufnr
      return g:llm_scratch_bufnr
    endif
  endif

  " Otherwise, create a new scratch buffer in a vertical split.
  execute 'vertical new'
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  file [LLM-Scratch]
  
  " Add syntax highlighting for the LLM chat
  if !exists("b:llm_syntax_loaded")
    syntax clear
    syntax match LLMPromptHeader /^Prompt: .*$/
    syntax match LLMTimestamp /^==== .*====$/
    syntax region LLMPrompt start=/^Prompt: / end=/^$/ contains=LLMPromptHeader
    syntax region LLMResponse start=/^Response:/ end=/^\s*$/ contains=LLMResponseHeader
    syntax match LLMResponseHeader /^Response:$/
    
    highlight LLMPromptHeader ctermfg=green guifg=green
    highlight LLMPrompt ctermfg=cyan guifg=cyan
    highlight LLMResponseHeader ctermfg=yellow guifg=yellow
    highlight LLMResponse ctermfg=white guifg=white
    highlight LLMTimestamp ctermfg=magenta guifg=magenta
    
    let b:llm_syntax_loaded = 1
  endif
  
  let g:llm_scratch_bufnr = bufnr('%')
  return g:llm_scratch_bufnr
endfunction

" Functions for the Snippet Scratch Buffer (for context snippets)

" Open or reuse the snippet scratch buffer
function! llm#open_snippet_buffer() abort
  if exists('g:llm_snippet_bufnr')
    if bufloaded(g:llm_snippet_bufnr)
      " If visible, bring to focus; otherwise, open in a vertical split.
      for win in range(1, winnr('$'))
        if winbufnr(win) == g:llm_snippet_bufnr
          execute win . "wincmd w"
          return g:llm_snippet_bufnr
        endif
      endfor
      execute 'vertical sbuffer ' . g:llm_snippet_bufnr
      return g:llm_snippet_bufnr
    endif
  endif
  execute 'vertical new'
  enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  file [LLM-Snippets]
  let g:llm_snippet_bufnr = bufnr('%')
  return g:llm_snippet_bufnr
endfunction

" Clear the snippet scratch buffer explicitly
function! llm#clear_snippet_buffer() abort
  if exists('g:llm_snippet_bufnr') && bufexists(g:llm_snippet_bufnr)
    call setbufline(g:llm_snippet_bufnr, 1, [])
    echo "[LLM-Snippets] cleared."
  else
    echo "No snippet buffer exists."
  endif
endfunction

" Add a snippet from the current visual selection to the snippet scratch buffer -- storing only filename and start,end meta info
function! llm#add_snippet() abort
  " Get the current buffer's filename
  let l:filename = bufname('%')
  if l:filename == ""
    let l:filename = "[No Name]"
  endif

  " Get the visual selection's start and end line numbers
  let l:start = getpos("'<")[1]
  let l:end   = getpos("'>")[1]

  " Construct an entry in the form: filename: start,end (only meta info)
  let l:entry = l:filename . ": " . l:start . "," . l:end

  " Open (or create) the snippet scratch buffer and append the entry
  let l:bufnr = llm#open_snippet_buffer()
  call append(line('$'), l:entry)
  echo "Snippet meta info added for " . l:filename
endfunction

" Helper: Get buffer content, using snippets if available
function! llm#get_buffer_content(bufnr, filename) abort
  " Default to full buffer content
  let l:contents = join(getbufline(a:bufnr, 1, '$'), "\n")
  
  " If the snippet buffer exists, check for override entries for this file
  if exists('g:llm_snippet_bufnr') && bufexists(g:llm_snippet_bufnr)
    let l:snip_lines = getbufline(g:llm_snippet_bufnr, 1, '$')
    let l:found_snippets = []
    
    " First pass: collect all snippets for this file
    for l:snip in l:snip_lines
      " CRITICAL-2 FIX: Escape all regex special chars: \^$.*[]~ (Vim magic mode specials)
      if l:snip =~# '^' . escape(a:filename, '\^$.*[]~') . ':\s'
        " Expected format: filename: start,end
        let l:parts = split(l:snip, ':\s\+')
        if len(l:parts) >= 2
          let l:meta = l:parts[1]
          let l:range = split(l:meta, ',')
          if len(l:range) == 2
            let l:snip_start = str2nr(l:range[0])
            let l:snip_end   = str2nr(l:range[1])
            " Store snippet info for later processing
            call add(l:found_snippets, {'start': l:snip_start, 'end': l:snip_end})
          endif
        endif
      endif
    endfor
    
    " If we found snippets, replace contents with concatenated snippets
    if !empty(l:found_snippets)
      let l:snippets_content = []
      for l:snippet in l:found_snippets
        let l:snippet_text = join(getbufline(a:bufnr, l:snippet.start, l:snippet.end), "\n")
        let l:snippet_header = "--- Snippet from lines " . l:snippet.start . "-" . l:snippet.end . " ---"
        call add(l:snippets_content, l:snippet_header)
        call add(l:snippets_content, l:snippet_text)
      endfor
      " Join all snippets with newlines and a separator
      let l:contents = join(l:snippets_content, "\n\n")
    endif
  endif
  
  return l:contents
endfunction

" Process text with an external LLM tool using the current adapter
function! llm#process(json_filename, prompt, model) abort
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  
  " Use the adapter to process the request
  return l:adapter.process(a:json_filename, a:prompt, a:model)
endfunction

" Async process with callback
function! llm#process_async(json_filename, prompt, model, callback) abort
  call llm#debug('llm#process_async: ENTER (json=' . a:json_filename . ', prompt="' . a:prompt . '", model="' . a:model . '")')
  
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  call llm#debug('llm#process_async: Adapter=' . llm#adapter#get_current_name())
  
  " Check if async is enabled AND adapter supports it
  let l:has_async = has_key(l:adapter, 'process_async')
  call llm#debug('llm#process_async: g:llm_use_async=' . g:llm_use_async . ', adapter.has_async=' . l:has_async)
  
  if g:llm_use_async && has_key(l:adapter, 'process_async')
    call llm#debug('llm#process_async: -> USING ASYNC PATH')
    return l:adapter.process_async(a:json_filename, a:prompt, a:model, a:callback)
  else
    call llm#debug('llm#process_async: -> FALLBACK TO SYNC PATH')
    " Fallback to synchronous processing
    let l:result = l:adapter.process(a:json_filename, a:prompt, a:model)
    call a:callback(l:result)
  endif
endfunction

" Function to get the list of available models from the current adapter
function! llm#get_available_models() abort
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  
  " Use the adapter to get available models
  return l:adapter.get_available_models()
endfunction

" Function to set the default model
function! llm#set_default_model(model) abort
  let g:llm_default_model = a:model
  let @" = a:model
endfunction

" Function to set the default adapter
function! llm#set_default_adapter(adapter) abort
  let g:llm_default_adapter = a:adapter
  call llm#adapter#set_current(a:adapter)
endfunction

" List all active LLM jobs
function! llm#list_jobs() abort
  " Get the current adapter
  let l:adapter = llm#adapter#get_current()
  
  " Check if adapter supports job listing
  if !has_key(l:adapter, 'list_jobs')
    echo '[LLM] Current adapter does not support job listing'
    return []
  endif
  
  let l:jobs = l:adapter.list_jobs()
  
  if empty(l:jobs)
    echo '[LLM] No active jobs'
    return []
  endif
  
  " Build display lines
  let l:lines = ['[LLM] Active Jobs:', '']
  for l:job in l:jobs
    let l:elapsed_str = l:job.elapsed . 's'
    call add(l:lines, printf('  %d: "%s" [%s] (%s elapsed, %s)', 
          \ l:job.id, l:job.prompt, l:job.model, l:elapsed_str, l:job.status))
  endfor
  call add(l:lines, '')
  call add(l:lines, 'Press q or <Esc> to close')
  
  " Use appropriate display method based on capabilities
  if has('popupwin')
    " Vim 8.2+ popup window
    call s:show_jobs_popup(l:lines)
  elseif has('nvim')
    " Neovim floating window
    call s:show_jobs_float(l:lines)
  else
    " Fallback to split window for older Vim
    call s:show_jobs_split(l:lines)
  endif
  
  return l:jobs
endfunction

" Show pruning stats for the last llm#parse_history_turns() call.
" Reads s:last_prune_stats and displays turn-by-turn reduction metrics.
"
" Public accessor for the last-computed prune stats (used by tests and callers
" that need the raw metrics dict without opening the display popup). Returns
" the internal s:last_prune_stats ({} if no parse has run yet).
function! llm#get_prune_stats() abort
  return s:last_prune_stats
endfunction

function! llm#show_prune_stats() abort
  if empty(s:last_prune_stats)
    echo '[LLM Prune] No stats available — run :LLM first'
    return
  endif

  let l:stats = s:last_prune_stats
  let l:total_before = l:stats.total_before
  let l:total_after  = l:stats.total_after
  let l:total_saved  = l:total_before - l:total_after
  let l:total_pct    = (l:total_before > 0)
        \ ? (100 * l:total_saved / l:total_before)
        \ : 0

  let l:lines = ['[LLM Prune Stats]', '']
  for l:t in l:stats.turns
    let l:flag = l:t.is_recent ? ' [recent,kept]' : ''
    call add(l:lines, printf('  Turn %-3d  %6d -> %6d chars  (%3d%% saved)%s',
          \ l:t.index, l:t.before, l:t.after, l:t.pct, l:flag))
  endfor
  call add(l:lines, '')
  call add(l:lines, printf('  TOTAL   %7d -> %7d chars  (%3d%% saved, %d chars removed)',
        \ l:total_before, l:total_after, l:total_pct, l:total_saved))
  call add(l:lines, '')
  call add(l:lines, 'Press q or <Esc> to close')

  if has('popupwin')
    call popup_create(l:lines, {
          \ 'title': ' LLM Prune Stats ',
          \ 'border': [],
          \ 'padding': [0, 1, 0, 1],
          \ 'close': 'button',
          \ 'filter': {id, key -> (key ==# 'q' || key ==# "\<Esc>") ? popup_close(id) == 0 : 0},
          \ })
  elseif has('nvim')
    call s:show_jobs_float(l:lines)
  else
    call s:show_jobs_split(l:lines)
  endif
endfunction

" Show jobs in Vim popup window (Vim 8.2+)
function! s:show_jobs_popup(lines) abort
  call popup_create(a:lines, {
        \ 'title': ' LLM Jobs ',
        \ 'border': [],
        \ 'padding': [0, 1, 0, 1],
        \ 'close': 'button',
        \ 'filter': {id, key -> (key == 'q' || key == "\<Esc>") ? popup_close(id) == 0 : 0},
        \ })
endfunction

" Show jobs in Neovim floating window
function! s:show_jobs_float(lines) abort
  " Create scratch buffer
  let l:buf = nvim_create_buf(v:false, v:true)
  call nvim_buf_set_lines(l:buf, 0, -1, v:true, a:lines)
  
  " Calculate window size
  let l:width = max(map(copy(a:lines), 'len(v:val)')) + 2
  let l:height = len(a:lines)
  
  " Center the window
  let l:opts = {
        \ 'relative': 'editor',
        \ 'width': l:width,
        \ 'height': l:height,
        \ 'col': (&columns - l:width) / 2,
        \ 'row': (&lines - l:height) / 2,
        \ 'border': 'rounded',
        \ 'style': 'minimal',
        \ }
  
  let l:win = nvim_open_win(l:buf, v:true, l:opts)
  
  " Set buffer options
  call nvim_buf_set_option(l:buf, 'modifiable', v:false)
  call nvim_buf_set_option(l:buf, 'bufhidden', 'wipe')
  
  " Add keybindings to close
  nnoremap <buffer> q :close<CR>
  nnoremap <buffer> <Esc> :close<CR>
endfunction

" Show jobs in split window (fallback for older Vim)
function! s:show_jobs_split(lines) abort
  let l:bufname = '[LLM Jobs]'
  let l:bufnr = bufnr(l:bufname)
  
  if l:bufnr == -1
    " Create new buffer
    execute 'botright 10split ' . l:bufname
    setlocal buftype=nofile bufhidden=wipe noswapfile nowrap
    setlocal nomodifiable
    nnoremap <buffer> q :close<CR>
    nnoremap <buffer> <Esc> :close<CR>
  else
    " Reuse existing buffer
    let l:winid = bufwinid(l:bufnr)
    if l:winid != -1
      " Window is open, just switch to it
      call win_gotoid(l:winid)
    else
      " Window is closed, open it again
      execute 'botright 10split +buffer' . l:bufnr
    endif
  endif
  
  " Update buffer content
  setlocal modifiable
  silent %delete _
  call setline(1, a:lines)
  setlocal nomodifiable
  
  " Resize window to fit content
  let l:desired_height = len(a:lines)
  if l:desired_height < 10
    execute 'resize ' . l:desired_height
  endif
endfunction


" Stop a specific LLM job (interactive selection when no arg)
function! llm#stop_job(arg) abort
  let l:adapter = llm#adapter#get_current()

  if !has_key(l:adapter, 'stop_job')
    echom '[LLM] Current adapter does not support job stopping'
    return 0
  endif

  " If a job ID was provided, stop it directly
  if !empty(a:arg)
    return l:adapter.stop_job(str2nr(a:arg))
  endif

  " No argument — interactive selection
  if !has_key(l:adapter, 'list_jobs')
    echom '[LLM] Current adapter does not support job listing'
    return 0
  endif

  let l:jobs = l:adapter.list_jobs()

  if empty(l:jobs)
    echom '[LLM] No active jobs'
    return 0
  endif

  " Single job — stop it automatically
  if len(l:jobs) == 1
    echom '[LLM] Stopping only active job #' . l:jobs[0].id
    return l:adapter.stop_job(str2nr(l:jobs[0].id))
  endif

  " Multiple jobs — present inputlist() menu
  let l:choices = ['Select job to stop:']
  for l:i in range(len(l:jobs))
    let l:j = l:jobs[l:i]
    call add(l:choices, (l:i + 1) . ': [#' . l:j.id . '] "' . l:j.prompt . '" [' . l:j.model . '] (' . l:j.elapsed . 's)')
  endfor

  let l:pick = inputlist(l:choices)
  if l:pick < 1 || l:pick > len(l:jobs)
    echom '[LLM] Cancelled'
    return 0
  endif

  return l:adapter.stop_job(str2nr(l:jobs[l:pick - 1].id))
endfunction

" Function to handle LLM queries with attached files
function! llm#run_with_files(args) abort
  " Arguments: single string containing: file1 file2 ... [--] [prompt]
  " Parse arguments to separate files from optional prompt
  
  " If called with no arguments, show usage
  if a:args == ''
    echoerr "LLMFile: Usage: LLMFile <file1> [file2 ...] [-- prompt]"
    return
  endif
  
  let l:files = []
  let l:prompt = ''
  
  " Split the string on '--' first to separate files from prompt
  let l:parts = split(a:args, '\s\+--\s\+', 1)
  
  if len(l:parts) == 0
    echoerr "LLMFile: No arguments provided"
    return
  endif
  
  " Parse file arguments (before --)
  let l:file_args = l:parts[0]
  
  " Parse prompt (after --)
  if len(l:parts) > 1
    let l:prompt = trim(l:parts[1])
    " Remove surrounding quotes if present
    if l:prompt =~ '^\(".*"\|' . "'.*" . '\)$'
      let l:prompt = l:prompt[1:-2]
    endif
  endif
  
  " Now parse file arguments - handle quoted paths and escaped spaces
  let l:file_args = trim(l:file_args)
  let l:current_arg = ''
  let l:in_quotes = 0
  let l:i = 0
  
  while l:i < len(l:file_args)
    let l:char = l:file_args[l:i]
    
    if l:char == '"' || l:char == "'"
      let l:in_quotes = !l:in_quotes
    elseif l:char == ' ' && !l:in_quotes
      " Space outside quotes - end of current argument
      if l:current_arg != ''
        let l:expanded = expand(l:current_arg)
        let l:fullpath = fnamemodify(l:expanded, ':p')
        
        if filereadable(l:fullpath) || isdirectory(l:fullpath)
          call add(l:files, l:fullpath)
        else
          echoerr "LLMFile: File not found or not readable: " . l:current_arg
          return
        endif
        let l:current_arg = ''
      endif
    else
      if l:char == '\' && l:i + 1 < len(l:file_args) && l:file_args[l:i + 1] == ' '
        " Escaped space - skip backslash, add space
        let l:i += 1
        let l:current_arg .= ' '
      else
        let l:current_arg .= l:char
      endif
    endif
    
    let l:i += 1
  endwhile
  
  " Don't forget the last argument
  if l:current_arg != ''
    let l:expanded = expand(l:current_arg)
    let l:fullpath = fnamemodify(l:expanded, ':p')
    
    if filereadable(l:fullpath) || isdirectory(l:fullpath)
      call add(l:files, l:fullpath)
    else
      echoerr "LLMFile: File not found or not readable: " . l:current_arg
      return
    endif
  endif
  
  " Check if at least one file was provided
  if empty(l:files)
    echoerr "LLMFile: No valid files provided"
    return
  endif
  
  " Display confirmation of attached files
  echo "LLMFile: Attaching " . len(l:files) . " file(s)"
  
  " Call main LLM function with file list
  call llm#run(l:prompt, 0, l:files)
endfunction

" Main LLM function that gathers context and processes input (now async-capable)
function! llm#run(...) abort
  call llm#debug('llm#run: ENTER (args=' . a:0 . ')')
  
  " Optional prompt argument; if supplied, this is the extra user prompt.
  let l:prompt = (a:0 >= 1 ? a:1 : '')
  " Optional model argument; if supplied, this is a boolean to choose the model.
  let l:choose_model = (a:0 >= 2 ? a:2 : 0)
  " Optional file list argument; if supplied, these are files to attach.
  let l:file_list = (a:0 >= 3 ? a:3 : [])
  let l:model = ''
  if l:choose_model
    let l:models = llm#get_available_models()
    echo "Choose a model:"
    for i in range(len(l:models))
      echo i + 1 . ". " . l:models[i]
    endfor
    let l:choice = input("Enter the model number: ")
    let l:model = l:models[l:choice - 1]
    call llm#set_default_model(l:model)
  endif

  " Get the current window's cursor location.
  let l:cursor_line = line('.')
  let l:cursor_col  = col('.')

  " Get a list of buffer numbers in the current tab.
  let l:buf_list = tabpagebuflist(tabpagenr())

  " Get the currently active buffer number.
  let l:active_bufnr = bufnr('%')

  " Build a list for buffers' information, skipping:
  "   a) the active buffer (stored separately)
  "   b) the scratch buffer (the llm_history, which is added separately)
  "   c) the snippet buffer
  let l:buffers = []
  for l:bufnr in l:buf_list
    if l:bufnr == l:active_bufnr
      continue
    endif
    if (exists('g:llm_scratch_bufnr') && l:bufnr == g:llm_scratch_bufnr) || (exists('g:llm_snippet_bufnr') && l:bufnr == g:llm_snippet_bufnr)
      continue
    endif
    let l:filename = bufname(l:bufnr)
    if empty(l:filename)
      let l:filename = "[No Name]"
    endif
    let l:contents = llm#get_buffer_content(l:bufnr, l:filename)
    call add(l:buffers, {'filename': l:filename, 'contents': l:contents})
  endfor

  " Gather details for the active buffer.
  let l:active_filename = bufname(l:active_bufnr)
  " If the active buffer IS the scratch buffer, don't duplicate its contents
  " here — it is already sent as llm_history below.
  if exists('g:llm_scratch_bufnr') && l:active_bufnr == g:llm_scratch_bufnr
    let l:active_contents = ''
  else
    let l:active_contents = llm#get_buffer_content(l:active_bufnr, l:active_filename)
  endif

  " Assemble the data dictionary in cache-optimized order:
  "   stable (large) → variable (small) for maximum prefix cache hits.
  "   1. llm_history    — large, stable prefix (earlier turns never change)
  "   2. buffers[]      — stable across requests in same session
  "   3. active_buffer  — stable most of the time
  "   4. file_arguments — stable per session
  "   5. prompt         — changes per request
  "   Note: cursor_line/cursor_col removed from JSON — passed via env vars
  "   (AICHAT_CURSOR_LINE, AICHAT_CURSOR_COL) for cache prefix stability.
  let l:data = {}

  " Structured history turns (parsed from scratch buffer).
  let l:history_turns = llm#parse_history_turns()
  if !empty(l:history_turns)
    let l:data.llm_history_turns = l:history_turns
  endif

  " Add flat history text (legacy). When g:llm_multiturn_mode is 1 and
  " structured turns are available, skip flat history to avoid redundancy
  " and save tokens — the backend uses llm_history_turns directly.
  let l:skip_flat_history = get(g:, 'llm_multiturn_mode', 0) && !empty(l:history_turns)
  if exists('g:llm_scratch_bufnr') && !l:skip_flat_history
    let l:data.llm_history = join(getbufline(g:llm_scratch_bufnr, 1, '$'), "\n")
  endif

  let l:data.buffers = l:buffers
  let l:data.active_buffer = {
        \ 'filename': l:active_filename,
        \ 'contents': l:active_contents,
        \ }

  if !empty(l:file_list)
    let l:data.file_arguments = l:file_list
  endif

  " Working directory — stable per session; enables log-analysis tooling to
  " attribute a request to a project (nearest git root) after the fact.
  let l:data.cwd = getcwd()

  if l:prompt != ''
    let l:data.prompt = l:prompt
  endif

  " Cache optimization hints for the aichat consumer.
  " Tells the backend where to place cache breakpoints. aichat now owns
  " ALL cache_control enforcement (4-block cap, non-increasing TTL,
  " tool_result pairing/ordering) -- do NOT re-add defensive breakpoint
  " math here. stable_fields/dynamic_fields were never read by aichat.
  let l:data._cache_hints = {
        \ 'breakpoint_after': ['llm_history', 'buffers'],
        \ }

  " Store cursor position for adapter to pass as env vars
  let s:last_cursor_pos = [l:cursor_line, l:cursor_col]

  " Convert the data dictionary to JSON.
  let l:json_data = llm#encode(l:data)
  
  call llm#debug('llm#run: JSON data size=' . len(l:json_data) . ' bytes, files=' . len(l:file_list))
  
  " Create log request dir if logging enabled
  let l:log_paths = (g:llm_log_level !=# 'none') ? llm#log#create_request() : {}

  " Register this request in the active requests list
  if !empty(l:log_paths)
    let l:request_entry = {'dir': l:log_paths.dir, 'log_paths': l:log_paths,
          \ 'model': l:model, 'prompt': strpart(l:prompt, 0, 60),
          \ 'start_time': strftime('%H:%M:%S')}
    call add(s:active_requests, l:request_entry)
    let s:last_request_dir = l:log_paths.dir
  endif

  " Write the JSON data to a file (persist at debug level, temp otherwise)
  if g:llm_log_level ==# 'debug' && !empty(l:log_paths)
    let l:tempfile = l:log_paths.input
  else
    let l:tempfile = tempname()
  endif
  call writefile(split(l:json_data, "\n"), l:tempfile)
  
  call llm#debug('llm#run: Created tempfile=' . l:tempfile)

  " Define callback to handle async completion
  function! OnLLMComplete(output) closure
    call llm#debug('OnLLMComplete: ENTER (output length=' . len(a:output) . ' chars)')
    
    " Open (or reuse) the scratch buffer and switch to it.
    let l:scratch_buf = llm#open_scratch_buffer()
    execute 'buffer ' . l:scratch_buf
    " Append a header with the current timestamp.
    let l:last_line = line('$')
    call append(l:last_line, '==== ' . strftime("%c") . ' ====')

    " Immediately after the timestamp, append the prompt if provided.
    if l:prompt != ''
      call append(l:last_line + 1, 'Prompt: ' . l:prompt)
      let l:last_line += 1
    endif

    " Append the LLM response line by line.
    for l:line in split(substitute(a:output, "\r", '', 'g'), "\n")
      call append(l:last_line + 1, l:line)
      let l:last_line += 1
    endfor

    " Append a blank line after the entry.
    call append(l:last_line + 1, '')

    " Scroll to the bottom of the scratch buffer.
    execute 'normal! G'
   
    " Return focus to the previous window.
    wincmd p
    " Clean up temp file (skip if persisted as log input)
    if g:llm_log_level ==# 'debug' && !empty(l:log_paths)
      " Input JSON already at its final log path — don't delete
    else
      call delete(l:tempfile)
    endif

    " Deregister this request from active list
    call filter(s:active_requests, 'v:val.dir !=# l:log_paths.dir')
    
    call llm#debug('OnLLMComplete: EXIT (buffer operations complete)')
    echom '[LLM] Complete!'
    call llm#maybe_notify({'prompt': l:prompt, 'model': l:model, 'tmux_window': l:tmux_window})
  endfunction
  
  
  " Show initial status and start async processing
  echom '[LLM] Request sent, processing...'
  call llm#debug('llm#run: Calling process_async with model="' . l:model . '"')
  " Capture tmux window name at kick-off time so notify func can use it later
  let l:tmux_window = !empty($TMUX) ? substitute(system('tmux display-message -p "#W"'), '\n\+$', '', '') : ''
  call llm#process_async(l:tempfile, l:prompt, l:model, function('OnLLMComplete'))
endfunction

" Warm the Anthropic cache with current context (no output generated).
" Builds context exactly as llm#run() but signals aichat to use max_tokens:1
" and suppresses normal output. Reports cache_creation metrics on completion.
function! llm#warm_cache() abort
  call llm#debug('llm#warm_cache: ENTER')

  " Get the current window's cursor location (for env vars).
  let l:cursor_line = line('.')
  let l:cursor_col  = col('.')

  " Get a list of buffer numbers in the current tab.
  let l:buf_list = tabpagebuflist(tabpagenr())

  " Get the currently active buffer number.
  let l:active_bufnr = bufnr('%')

  " Build buffer list (same logic as llm#run).
  let l:buffers = []
  for l:bufnr in l:buf_list
    if l:bufnr == l:active_bufnr
      continue
    endif
    if (exists('g:llm_scratch_bufnr') && l:bufnr == g:llm_scratch_bufnr) || (exists('g:llm_snippet_bufnr') && l:bufnr == g:llm_snippet_bufnr)
      continue
    endif
    let l:filename = bufname(l:bufnr)
    if empty(l:filename)
      let l:filename = "[No Name]"
    endif
    let l:contents = llm#get_buffer_content(l:bufnr, l:filename)
    call add(l:buffers, {'filename': l:filename, 'contents': l:contents})
  endfor

  " Gather active buffer details.
  let l:active_filename = bufname(l:active_bufnr)
  if exists('g:llm_scratch_bufnr') && l:active_bufnr == g:llm_scratch_bufnr
    let l:active_contents = ''
  else
    let l:active_contents = llm#get_buffer_content(l:active_bufnr, l:active_filename)
  endif

  " Assemble the data dictionary (same structure as llm#run).
  let l:data = {}

  if exists('g:llm_scratch_bufnr')
    let l:data.llm_history = join(getbufline(g:llm_scratch_bufnr, 1, '$'), "\n")
  endif

  let l:history_turns = llm#parse_history_turns()
  if !empty(l:history_turns)
    let l:data.llm_history_turns = l:history_turns
  endif

  let l:data.buffers = l:buffers
  let l:data.active_buffer = {
        \ 'filename': l:active_filename,
        \ 'contents': l:active_contents,
        \ }

  let l:data.cwd = getcwd()

  " Minimal prompt — signals intent without adding dynamic content.
  let l:data.prompt = 'cache warm'

  " Cache hints and warm signal.
  let l:data._cache_hints = {
        \ 'breakpoint_after': ['llm_history', 'buffers'],
        \ }
  let l:data._cache_warm = 1

  " Store cursor position for adapter env vars.
  let s:last_cursor_pos = [l:cursor_line, l:cursor_col]

  " Encode and write to tempfile.
  let l:json_data = llm#encode(l:data)
  let l:tempfile = tempname()
  call writefile(split(l:json_data, "\n"), l:tempfile)

  " Fire async with a lightweight callback (no scratch buffer write).
  echom '[LLM] Cache warming...'
  call llm#process_async(l:tempfile, 'cache warm', '', {output -> execute("echom '[LLM] Cache warmed (' . len(output) . ' bytes)' | call delete('" . l:tempfile . "')", '')})
endfunction

" Ensure session directory exists
function! llm#ensure_session_dir() abort
  let l:session_dir = expand('~/.vim/vim-llm-assistant/sessions')
  if !isdirectory(l:session_dir)
    call mkdir(l:session_dir, 'p')
  endif
  return l:session_dir
endfunction

" List available session files for completion
function! llm#complete_sessions(arglead, cmdline, cursorpos) abort
  let l:session_dir = llm#ensure_session_dir()
  let l:files = readdir(l:session_dir)
  return filter(l:files, 'v:val =~ ''^'' . a:arglead')
endfunction

" Save current LLM session including history, snippets, and tab layout
function! llm#save_session(filename) abort
  " Get session directory
  let l:session_dir = llm#ensure_session_dir()
  
  " If no filename provided, prompt for one
  let l:filename = a:filename
  if l:filename == ""
    let l:filename = input('Enter filename to save LLM session: ')
    if l:filename == ""
      echo "No filename provided, aborting session save."
      return
    endif
  endif
  
  " Ensure filename has .json extension
  if l:filename !~ '\.json$'
    let l:filename .= '.json'
  endif
  
  " If not absolute path, prepend session directory
  if l:filename !~ '^/'
    let l:filepath = l:session_dir . '/' . l:filename
  else
    let l:filepath = l:filename
  endif
  
  " Build session dictionary
  let l:session = {}
  
  " CRITICAL-1 FIX: Save history buffer content if it exists
  " Use global variable for consistency with llm#run(), fallback to name lookup
  let l:history_bufnr = exists('g:llm_scratch_bufnr') && bufexists(g:llm_scratch_bufnr)
        \ ? g:llm_scratch_bufnr : bufnr('[LLM-Scratch]')
  if l:history_bufnr != -1
    let l:session.history = getbufline(l:history_bufnr, 1, '$')
  else
    let l:session.history = []
  endif
  
  " CRITICAL-1 FIX: Save snippet buffer content if it exists
  " Use global variable for consistency with llm#get_buffer_content(), fallback to name lookup
  " Defensively initialize snippets to [] to prevent any variable leakage
  let l:session.snippets = []
  let l:snippet_bufnr = exists('g:llm_snippet_bufnr') && bufexists(g:llm_snippet_bufnr)
        \ ? g:llm_snippet_bufnr : bufnr('[LLM-Snippets]')
  if l:snippet_bufnr != -1
    " Ensure we never save history content as snippets (guard against bufnr collision)
    if l:snippet_bufnr != l:history_bufnr
      let l:session.snippets = getbufline(l:snippet_bufnr, 1, '$')
    endif
  else
    let l:session.snippets = []
  endif
  
  " Collect all visible files across all tabs
  let l:session.visible_files = []
  for l:tab in gettabinfo()
    for l:winid in l:tab.windows
      call win_execute(l:winid, 'let g:llm_temp_fname = expand("%:p")')
      if g:llm_temp_fname != ""
        " Handle special buffers - store just the name for LLM-Scratch and LLM-Snippets
        let l:fname_to_store = g:llm_temp_fname
        if g:llm_temp_fname =~ '\[LLM-\(Scratch\|Snippets\)\]$'
          let l:fname_to_store = fnamemodify(g:llm_temp_fname, ':t')
        endif
        if index(l:session.visible_files, l:fname_to_store) == -1
          call add(l:session.visible_files, l:fname_to_store)
        endif
      endif
    endfor
  endfor
  
  " Save tab and window layout
  let l:session.tabs = []
  for l:tab in gettabinfo()
    let l:tab_entry = {}
    let l:tab_entry.windows = []
    for l:winid in l:tab.windows
      call win_execute(l:winid, 'let g:llm_temp_fname = expand("%:p")')
      if g:llm_temp_fname != "" 
        " Handle special buffers - store just the name for LLM-Scratch and LLM-Snippets
        let l:fname_to_store = g:llm_temp_fname
        if g:llm_temp_fname =~ '\[LLM-\(Scratch\|Snippets\)\]$'
          let l:fname_to_store = fnamemodify(g:llm_temp_fname, ':t')
        endif

        call add(l:tab_entry.windows, l:fname_to_store)
      endif
    endfor
    call add(l:session.tabs, l:tab_entry)
  endfor
  
  " Save to file
  let l:json = json_encode(l:session)
  call writefile(split(l:json, "\n"), l:filepath)
  echo "LLM session saved to " . l:filepath
endfunction

" Load LLM session from file
function! llm#load_session(filename) abort
  " Get session directory
  let l:session_dir = llm#ensure_session_dir()
  
  " If no filename provided, abort
  if a:filename == ""
    echo "No filename provided, aborting session load."
    return
  endif
  
  " If not absolute path, prepend session directory
  if a:filename !~ '^/'
    let l:filepath = l:session_dir . '/' . a:filename
    if !filereadable(l:filepath) && filereadable(l:session_dir . '/' . a:filename . '.json')
      let l:filepath .= '.json'
    endif
  else
    let l:filepath = a:filename
  endif
  
  " Check if file exists
  if !filereadable(l:filepath)
    echoerr "Session file " . l:filepath . " not found!"
    return
  endif
  
  " Read and decode the JSON file
  let l:lines = readfile(l:filepath)
  let l:session = json_decode(join(l:lines, "\n"))
  
  " MINOR-2 FIX: Validate session structure
  if type(l:session) != v:t_dict
    echoerr "Invalid session file: expected JSON object"
    call llm#debug("load_session: invalid JSON type - " . type(l:session))
    return
  endif
  
  " CRITICAL-3 FIX: Only open scratch buffer when history has content to restore
  if has_key(l:session, 'history') && !empty(l:session.history)
    let l:history_bufnr = llm#open_scratch_buffer()
    call setbufvar(l:history_bufnr, '&buftype', 'nofile')
    call setbufvar(l:history_bufnr, '&swapfile', 0)
    call deletebufline(l:history_bufnr, 1, '$')
    call llm#debug("load_session: restoring " . len(l:session.history) . " history lines")
    call setbufline(l:history_bufnr, 1, l:session.history)
    call setbufvar(l:history_bufnr, '&modified', 0)
  elseif has_key(l:session, 'history')
    call llm#debug("load_session: history key present but empty - skipping buffer creation")
  endif
  
  " Only open snippet buffer when snippets has content to restore
  if has_key(l:session, 'snippets') && !empty(l:session.snippets)
    let l:snippet_bufnr = llm#open_snippet_buffer()
    call setbufvar(l:snippet_bufnr, '&buftype', 'nofile')
    call setbufvar(l:snippet_bufnr, '&swapfile', 0)
    call deletebufline(l:snippet_bufnr, 1, '$')
    call llm#debug("load_session: restoring " . len(l:session.snippets) . " snippet lines")
    call setbufline(l:snippet_bufnr, 1, l:session.snippets)
    call setbufvar(l:snippet_bufnr, '&modified', 0)
  elseif has_key(l:session, 'snippets')
    call llm#debug("load_session: snippets key present but empty - skipping buffer creation")
  endif
  
  " Add all visible files to the argument list
  if has_key(l:session, 'visible_files') && !empty(l:session.visible_files)
    " Add all files to the argument list (without clearing first)
    for l:file in l:session.visible_files
      execute 'argadd ' . fnameescape(l:file)
    endfor
  endif
  
  " Restore the tab and window layout
  if has_key(l:session, 'tabs')
    " Close all current tabs
    silent! tabonly
    
    " Open each tab and its windows
    let l:tindex = 0
    for l:tab in l:session.tabs
      if l:tindex > 0
        tabnew
      endif
      
      let l:windex = 0
      for l:file in l:tab.windows
        if l:windex == 0
          " Special handling for LLM buffers
          if l:file == '[LLM-Scratch]'
            call llm#open_scratch_buffer()
          elseif l:file == '[LLM-Snippets]'
            call llm#open_snippet_buffer()
          else
            execute 'edit ' . fnameescape(l:file)
          endif
        else
          execute 'vsplit ' . fnameescape(l:file)
        endif
        let l:windex += 1
      endfor
      let l:tindex += 1
    endfor
  endif
  
  echo "LLM session loaded from " . l:filepath
endfunction

" Call user-defined notification hook if configured after LLM/LLMFile completes.
" Context dict: {'prompt': '...', 'model': '...'}
function! llm#maybe_notify(context) abort
  if exists('g:Llm_notify_func') && !empty(g:Llm_notify_func)
    call call(g:Llm_notify_func, [a:context])
  endif
endfunction
