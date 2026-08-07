set nocompatible
" Test: llm#prune_tool_outputs() overlap handling — Task 5 verification
" A Call block whose output range CONTAINS an ERROR block must emit only ONE
" placeholder (the outer Call block's). The inner ERROR marker line is part of
" the Call block's output range, so it is suppressed by skip_set and its
" placeholder_after entry is never emitted. No duplicate "chars removed" lines.
" Run: vim --not-a-term -u NONE -S scripts/tests/test_prune_overlap.vim

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

function! s:assert_contains(label, needle, haystack)
  if stridx(a:haystack, a:needle) >= 0
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected to find: ' . a:needle
    echo '    in: ' . a:haystack
    let s:fail += 1
  endif
endfunction

function! s:assert_not_contains(label, needle, haystack)
  if stridx(a:haystack, a:needle) < 0
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected NOT to find: ' . a:needle
    echo '    in: ' . a:haystack
    let s:fail += 1
  endif
endfunction

" Count non-overlapping occurrences of a:needle in a:haystack
function! s:count_occurrences(needle, haystack)
  let l:count = 0
  let l:pos = 0
  let l:nlen = len(a:needle)
  while 1
    let l:found = stridx(a:haystack, a:needle, l:pos)
    if l:found < 0
      break
    endif
    let l:count += 1
    let l:pos = l:found + l:nlen
  endwhile
  return l:count
endfunction

function! s:assert_count(label, expected_count, needle, haystack)
  let l:actual = s:count_occurrences(a:needle, a:haystack)
  if l:actual == a:expected_count
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected count: ' . a:expected_count . ' of ' . a:needle
    echo '    actual count:   ' . l:actual
    let s:fail += 1
  endif
endfunction

echo ''
echo '=== TEST 1: Call block containing an ERROR block emits ONE placeholder ==='
" The Call block spans from its marker to EOF (no subsequent Call marker), so
" the inner ERROR marker + its output are all inside the Call output range.
let s:call_out = repeat('x', 250)
let s:err_out  = repeat('e', 250)
let s:lines1 = [
      \ 'Narrative BEFORE the tool call.',
      \ '**~~ Call fs_cat {"path":"/tmp/x"} ~~**',
      \ s:call_out,
      \ 'ERROR: tool execution failed: inner_tool',
      \ s:err_out]
let s:text1 = join(s:lines1, "\n")
let s:result1 = llm#prune_tool_outputs(s:text1, 0)

call s:assert_contains('narrative before preserved', 'Narrative BEFORE the tool call.', s:result1)
call s:assert_contains('outer Call marker preserved', '**~~ Call fs_cat', s:result1)
call s:assert_contains('outer Call placeholder present', '[Tool: fs_cat', s:result1)
call s:assert_not_contains('inner ERROR marker suppressed', 'ERROR: tool execution failed: inner_tool', s:result1)
call s:assert_not_contains('inner error placeholder NOT emitted', '[Tool: inner_tool', s:result1)
call s:assert_not_contains('outer Call output pruned', s:call_out, s:result1)
call s:assert_not_contains('inner error output pruned', s:err_out, s:result1)
call s:assert_count('exactly ONE chars-removed placeholder', 1, 'chars removed]', s:result1)

echo ''
echo '=== TEST 2: No duplicate placeholders even when both blocks are large ==='
" Sanity check: detect_tool_blocks and detect_error_blocks each report a block,
" but reconstruction emits a single placeholder because the inner marker line
" is inside the outer block's skip_set.
let s:tool_blocks = llm#detect_tool_blocks(s:text1)
let s:error_blocks = llm#detect_error_blocks(s:text1)
call s:assert('detect_tool_blocks finds outer Call block', 1, len(s:tool_blocks))
call s:assert('detect_error_blocks finds inner ERROR block', 1, len(s:error_blocks))
call s:assert('outer block starts at Call marker (idx 1)', 1, s:tool_blocks[0].start)
call s:assert('inner error block starts at ERROR marker (idx 3)', 3, s:error_blocks[0].start)
" Inner error start must fall within outer block output range [start+1 .. end]
let s:outer = s:tool_blocks[0]
let s:inner = s:error_blocks[0]
if s:inner.start > s:outer.start && s:inner.start <= s:outer.end
  echo '  PASS: inner ERROR marker lies inside outer Call output range'
  let s:pass += 1
else
  echo '  FAIL: inner ERROR marker not inside outer Call output range'
  let s:fail += 1
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
