set nocompatible
" Test: llm#prune_tool_outputs() — Task 4 verification
" Run: vim --not-a-term -u NONE -S scripts/tests/test_prune_tool_outputs.vim

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

echo ''
echo '=== TEST 1: is_recent=1 returns text unchanged ==='
let s:lines1 = [
      \ '**~~ Call fs_cat {args} ~~**',
      \ repeat('x', 250),
      \ 'Some narrative text.']
let s:text1 = join(s:lines1, "\n")
let s:result1 = llm#prune_tool_outputs(s:text1, 1)
call s:assert('is_recent returns unchanged', s:text1, s:result1)

echo ''
echo '=== TEST 2: is_recent=0 with tool block — Call marker preserved, output replaced ==='
let s:big2 = repeat('o', 250)
let s:lines2 = [
      \ '**~~ Call fs_cat {"path":"/tmp/test"} ~~**',
      \ s:big2,
      \ 'more output here']
let s:text2 = join(s:lines2, "\n")
let s:result2 = llm#prune_tool_outputs(s:text2, 0)
call s:assert_contains('call-marker preserved', '**~~ Call fs_cat', s:result2)
call s:assert_not_contains('output removed', s:big2, s:result2)
call s:assert_contains('placeholder present', '[Tool: fs_cat', s:result2)
call s:assert_contains('placeholder has chars removed', 'chars removed]', s:result2)

echo ''
echo '=== TEST 3: Narrative text BEFORE tool block and BETWEEN two calls is preserved ==='
" detect_tool_blocks terminates a block when a new Call marker is found.
" Narrative BEFORE all tool calls is preserved (not part of any block).
" Narrative BETWEEN two call blocks is preserved (between block1.end and block2.start).
let s:big3a = repeat('z', 250)
let s:big3b = repeat('y', 250)
let s:lines3 = [
      \ 'This is narrative BEFORE any tool call.',
      \ '**~~ Call tool_alpha {args} ~~**',
      \ s:big3a,
      \ '**~~ Call tool_beta {args} ~~**',
      \ s:big3b]
let s:text3 = join(s:lines3, "\n")
let s:result3 = llm#prune_tool_outputs(s:text3, 0)
call s:assert_contains('narrative before preserved', 'narrative BEFORE', s:result3)
call s:assert_contains('tool_alpha marker preserved', 'Call tool_alpha', s:result3)
call s:assert_contains('tool_beta marker preserved', 'Call tool_beta', s:result3)
call s:assert_not_contains('tool_alpha output pruned', s:big3a, s:result3)
call s:assert_not_contains('tool_beta output pruned', s:big3b, s:result3)
call s:assert_contains('placeholder alpha', '[Tool: tool_alpha', s:result3)
call s:assert_contains('placeholder beta', '[Tool: tool_beta', s:result3)

echo ''
echo '=== TEST 4: Error block — ERROR line preserved, output replaced ==='
let s:err_output = repeat('e', 250)
let s:lines4 = [
      \ 'ERROR: tool execution failed: my_tool',
      \ s:err_output,
      \ 'error line 2']
let s:text4 = join(s:lines4, "\n")
let s:result4 = llm#prune_tool_outputs(s:text4, 0)
call s:assert_contains('error marker preserved', 'ERROR: tool execution failed: my_tool', s:result4)
call s:assert_not_contains('error output removed', s:err_output, s:result4)
call s:assert_contains('error placeholder present', '[Tool: my_tool', s:result4)

echo ''
echo '=== TEST 5: Small output (<200 chars) NOT pruned ==='
let s:small_output = repeat('s', 50)
let s:lines5 = [
      \ '**~~ Call fs_read {args} ~~**',
      \ s:small_output]
let s:text5 = join(s:lines5, "\n")
let s:result5 = llm#prune_tool_outputs(s:text5, 0)
call s:assert_contains('small output preserved', s:small_output, s:result5)

echo ''
echo '=== TEST 6: g:llm_prune_enabled=0 disables pruning ==='
let g:llm_prune_enabled = 0
let s:large_output = repeat('L', 300)
let s:lines6 = [
      \ '**~~ Call fs_cat {args} ~~**',
      \ s:large_output]
let s:text6 = join(s:lines6, "\n")
let s:result6 = llm#prune_tool_outputs(s:text6, 0)
call s:assert_contains('kill-switch: output preserved', s:large_output, s:result6)
unlet g:llm_prune_enabled

echo ''
echo '=== TEST 7: Multiple tool blocks with narrative BEFORE each — all pruned ==='
" Narrative before the first call is always preserved.
" Between the two Call markers, the first block ends when the second starts.
let s:big7a = repeat('A', 250)
let s:big7b = repeat('B', 250)
let s:lines7 = [
      \ 'Narrative before first call.',
      \ '**~~ Call tool_one {args} ~~**',
      \ s:big7a,
      \ '**~~ Call tool_two {args} ~~**',
      \ s:big7b]
let s:text7 = join(s:lines7, "\n")
let s:result7 = llm#prune_tool_outputs(s:text7, 0)
call s:assert_contains('narrative before preserved', 'Narrative before first call.', s:result7)
call s:assert_contains('tool_one marker preserved', 'Call tool_one', s:result7)
call s:assert_contains('tool_two marker preserved', 'Call tool_two', s:result7)
call s:assert_not_contains('tool_one output removed', s:big7a, s:result7)
call s:assert_not_contains('tool_two output removed', s:big7b, s:result7)

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
