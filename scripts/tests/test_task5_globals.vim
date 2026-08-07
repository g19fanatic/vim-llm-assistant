set nocompatible
let s:errors = 0
let s:tests = 0

" Source the autoload file
let s:plugin_path = expand('<sfile>:p:h:h:h') . '/autoload/llm.vim'
execute 'source ' . s:plugin_path

function! s:assert(cond, msg) abort
  let s:tests += 1
  if !a:cond
    let s:errors += 1
    echom 'FAIL: ' . a:msg
  else
    echom 'PASS: ' . a:msg
  endif
endfunction

" Build a call marker with ACTUAL ~~ tildes (not the regex pattern [~][~])
" This is what real assistant responses contain.
let s:marker = '**~~ Call native.fs_read {"path": "/tmp/x"} ~~**'

" Helper: join lines into a single text block
function! s:lines(...) abort
  return join(a:000, "\n")
endfunction

" ===== TEST 1: Default value of g:llm_prune_recency =====
call s:assert(get(g:, 'llm_prune_recency', 3) == 3, 'g:llm_prune_recency default is 3')

" ===== TEST 2: Default value of g:llm_prune_enabled =====
call s:assert(get(g:, 'llm_prune_enabled', 1) == 1, 'g:llm_prune_enabled default is 1')

" ===== TEST 3: Default value of g:llm_prune_min_chars =====
call s:assert(get(g:, 'llm_prune_min_chars', 200) == 200, 'g:llm_prune_min_chars default is 200')

" ===== TEST 4: Kill switch (llm_prune_enabled=0) returns text unchanged =====
let g:llm_prune_enabled = 0
let s:big_output = repeat('This is output line that should be pruned. ', 10)
let s:text_big = s:lines('Preamble', s:marker, s:big_output, '')
let s:result = llm#prune_tool_outputs(s:text_big, 0)
call s:assert(s:result ==# s:text_big, 'Kill switch g:llm_prune_enabled=0 returns text unchanged')

" ===== TEST 5: Re-enable (llm_prune_enabled=1) and verify pruning works =====
let g:llm_prune_enabled = 1
let g:llm_prune_min_chars = 50
let s:big_output2 = repeat('Output line that should be pruned. ', 5)
let s:text2 = s:lines('Preamble text here.', s:marker, s:big_output2, '')
let s:pruned = llm#prune_tool_outputs(s:text2, 0)
call s:assert(s:pruned !=# s:text2, 'Pruning fires when enabled=1')
call s:assert(s:pruned =~# '\[Tool: native\.fs_read', 'Pruned result has Tool placeholder')

" ===== TEST 6: g:llm_prune_min_chars threshold - small block not pruned =====
let g:llm_prune_min_chars = 999999
let s:small_output = 'Just a few chars'
let s:text3 = s:lines('Before', s:marker, s:small_output, '')
let s:result3 = llm#prune_tool_outputs(s:text3, 0)
call s:assert(s:result3 ==# s:text3, 'Small block below min_chars threshold is NOT pruned')

" ===== TEST 7: is_recent=1 always returns unchanged =====
let g:llm_prune_enabled = 1
let g:llm_prune_min_chars = 0
let s:big3 = repeat('Recent output. ', 20)
let s:text4 = s:lines(s:marker, s:big3, '')
let s:result4 = llm#prune_tool_outputs(s:text4, 1)
call s:assert(s:result4 ==# s:text4, 'is_recent=1 always returns text unchanged')

" ===== TEST 8: Override g:llm_prune_recency value =====
let g:llm_prune_recency = 5
call s:assert(get(g:, 'llm_prune_recency', 3) == 5, 'g:llm_prune_recency override to 5 works')

" ===== Summary =====
echom 'Tests run: ' . s:tests . ', errors: ' . s:errors
if s:errors > 0
  cquit
else
  qall!
endif
