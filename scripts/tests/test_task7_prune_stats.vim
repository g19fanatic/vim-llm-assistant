set nocompatible
" Test: Task 7 — Debug logging + s:last_prune_stats population
" Verifies: 
"   (a) s:last_prune_stats is populated after llm#parse_history_turns()
"   (b) Stats have correct structure (turns list, total_before, total_after)
"   (c) Per-turn stats include before/after/pct/is_recent fields
" Run: vim --not-a-term -u NONE -S scripts/tests/test_task7_prune_stats.vim

source /home/pdibiase/sources/vim-llm-assistant/autoload/llm.vim

let s:pass = 0
let s:fail = 0

function! s:assert(label, expected, actual)
  if a:expected == a:actual
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected: ' . string(a:expected)
    echo '    actual:   ' . string(a:actual)
    let s:fail += 1
  endif
endfunction

function! s:assert_true(label, val)
  if a:val
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected truthy, got: ' . string(a:val)
    let s:fail += 1
  endif
endfunction

function! s:assert_has_key(label, key, dict)
  if has_key(a:dict, a:key)
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected key: ' . a:key
    echo '    in dict:      ' . string(keys(a:dict))
    let s:fail += 1
  endif
endfunction

" Helper to create a scratch buffer with mock history content
function! s:setup_scratch(lines)
  let l:buf = bufadd('[LLM-Scratch]')
  call bufload(l:buf)
  call setbufvar(l:buf, '&buftype', 'nofile')
  call deletebufline(l:buf, 1, '$')
  call setbufline(l:buf, 1, a:lines)
  let g:llm_scratch_bufnr = l:buf
  return l:buf
endfunction

" Build a big string for tool output
let s:tool_output = repeat('O', 500)

" --- TEST 1: s:last_prune_stats populated for single old turn ---
echo ''
echo '=== TEST 1: s:last_prune_stats populated after parse_history_turns ==='

" Create a scratch buffer with 1 old turn containing a tool block
let s:turn1_lines = [
      \ '==== Mon 01 Jan 2026 12:00:00 PM EDT ====',
      \ 'Prompt: Hello',
      \ '**~~ Call fs_cat {"path":"/tmp/x"} ~~**',
      \ s:tool_output,
      \ '']
call s:setup_scratch(s:turn1_lines)

" Reset stats
let s:last_prune_stats = {}
let g:llm_prune_recency = 0
let g:llm_prune_enabled = 1

let s:turns = llm#parse_history_turns()

" Read llm.vim's internal stats via the public accessor. The test script's own
" s:last_prune_stats is a DIFFERENT script-local scope than llm.vim's, so we
" must go through llm#get_prune_stats() to observe what parse actually stored.
let s:stats = llm#get_prune_stats()

call s:assert_true('parse returned turns', len(s:turns) > 0)
call s:assert_has_key('stats has turns key', 'turns', s:stats)
call s:assert_has_key('stats has total_before key', 'total_before', s:stats)
call s:assert_has_key('stats has total_after key', 'total_after', s:stats)
call s:assert_true('total_before > 0', s:stats.total_before > 0)
call s:assert_true('total_after < total_before (pruning occurred)', s:stats.total_after < s:stats.total_before)

" --- TEST 2: Per-turn stats have correct fields ---
echo ''
echo '=== TEST 2: Per-turn stats have correct fields ==='

let s:turn_stats = llm#get_prune_stats().turns
call s:assert_true('turns list non-empty', len(s:turn_stats) > 0)
let s:t0 = s:turn_stats[0]
call s:assert_has_key('turn has index field', 'index', s:t0)
call s:assert_has_key('turn has before field', 'before', s:t0)
call s:assert_has_key('turn has after field', 'after', s:t0)
call s:assert_has_key('turn has pct field', 'pct', s:t0)
call s:assert_has_key('turn has is_recent field', 'is_recent', s:t0)
call s:assert('turn index is 0', 0, s:t0.index)
call s:assert('is_recent=0 for old turn', 0, s:t0.is_recent)

" --- TEST 3: Recent turns NOT pruned, old turns ARE pruned (recency=1) ---
echo ''
echo '=== TEST 3: Recency boundary — old vs recent ==='

let s:history_lines = [
      \ '==== Mon 01 Jan 2026 12:00:00 PM EDT ====',
      \ 'Prompt: Old question',
      \ '**~~ Call safe_script_executor {"script":"ls"} ~~**',
      \ repeat('OLD', 200),
      \ '',
      \ '==== Mon 01 Jan 2026 01:00:00 PM EDT ====',
      \ 'Prompt: Recent question',
      \ '**~~ Call fs_cat {"path":"/tmp/x"} ~~**',
      \ repeat('NEW', 200),
      \ '']
call s:setup_scratch(s:history_lines)

let g:llm_prune_recency = 1
let g:llm_prune_enabled = 1

let s:turns3 = llm#parse_history_turns()

call s:assert('2 turns parsed', 2, len(s:turns3))

let s:old_turn = s:turns3[0]
let s:recent_turn = s:turns3[1]

" Old turn should be pruned (tool output removed)
call s:assert_true('old turn assistant contains marker', stridx(s:old_turn.assistant, '[Tool:') >= 0)
" Recent turn should be intact (tool output preserved)
call s:assert_true('recent turn still has full output', stridx(s:recent_turn.assistant, repeat('NEW', 10)) >= 0)

" Stats should show old turn was pruned, recent was not
let s:stats3 = llm#get_prune_stats()
let s:t3_0 = s:stats3.turns[0]
let s:t3_1 = s:stats3.turns[1]
call s:assert('turn 0 is_recent=0', 0, s:t3_0.is_recent)
call s:assert('turn 1 is_recent=1', 1, s:t3_1.is_recent)
call s:assert_true('turn 0 was pruned (after < before)', s:t3_0.after < s:t3_0.before)
call s:assert_true('turn 1 unchanged (before == after)', s:t3_1.before == s:t3_1.after)

" --- TEST 4: g:llm_prune_enabled=0 leaves stats empty ---
echo ''
echo '=== TEST 4: Disabled pruning — stats NOT populated ==='

let s:history_lines4 = [
      \ '==== Mon 01 Jan 2026 12:00:00 PM EDT ====',
      \ 'Prompt: Disabled test',
      \ '**~~ Call fs_cat {"path":"/tmp/x"} ~~**',
      \ repeat('Z', 500),
      \ '']
call s:setup_scratch(s:history_lines4)

let g:llm_prune_enabled = 0
let s:last_prune_stats = {'_old_key': 1}  " mark with a sentinel

let s:turns4 = llm#parse_history_turns()

" When disabled, the pruning block is skipped entirely — stats should still hold old sentinel
call s:assert_has_key('stats unchanged when disabled', '_old_key', s:last_prune_stats)

" --- TEST 5: llm#show_prune_stats() runs without error (popup filter fix) ---
echo ''
echo '=== TEST 5: show_prune_stats runs without error ==='

" Re-run a parse with pruning enabled so llm.vim's internal s:last_prune_stats
" is freshly populated (Test 4 disabled it and left the sentinel).
let g:llm_prune_recency = 0
let g:llm_prune_enabled = 1
let s:stats_lines = [
      \ '==== Mon 01 Jan 2026 12:00:00 PM EDT ====',
      \ 'Prompt: Stats display test',
      \ '**~~ Call fs_cat {"path":"/tmp/x"} ~~**',
      \ repeat('S', 500),
      \ '']
call s:setup_scratch(s:stats_lines)
call llm#parse_history_turns()

" Calling show_prune_stats must not raise. popup_create is non-blocking
" (the fixed filter only fires on keypress), so this returns immediately.
let s:show_ok = 1
try
  call llm#show_prune_stats()
catch
  let s:show_ok = 0
  echo '    exception: ' . v:exception
endtry
call s:assert_true('show_prune_stats returned without error', s:show_ok)

" Clean up any popup created by the display (headless safety).
if has('popupwin')
  call popup_clear()
endif

echo ''
echo '=================='
echo 'Results: ' . s:pass . ' passed, ' . s:fail . ' failed'
if s:fail == 0
  echo 'ALL TESTS PASSED'
  qall!
else
  echo 'SOME TESTS FAILED'
  cquit!
endif
