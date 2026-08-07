set nocompatible
" Test: llm#detect_tool_blocks() — Task 4 edge cases
" Run: vim --not-a-term -u NONE -S scripts/tests/test_detect_tool_blocks.vim

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

function! s:assert_len(label, expected, actual_list)
  call s:assert(a:label . ' count', a:expected, len(a:actual_list))
endfunction

echo ''
echo '=== TEST 1: Orphaned box opener finalizes at EOF ==='
" A box opener (U+2554 ╔) with no closer (╚) and no subsequent Call marker.
" The open box block must be finalized at end of text.
let s:lines1 = [
      \ 'Some narrative before the box.',
      \ '╔══════════════════════════════════╗',
      \ '║ safe_script_executor output line 1 ║',
      \ '║ safe_script_executor output line 2 ║']
let s:text1 = join(s:lines1, "\n")
let s:blocks1 = llm#detect_tool_blocks(s:text1)
call s:assert_len('orphan-box', 1, s:blocks1)
if len(s:blocks1) >= 1
  call s:assert('orphan-box name', 'safe_script_executor', s:blocks1[0]['name'])
  " Opener is line index 1 (0-based)
  call s:assert('orphan-box start', 1, s:blocks1[0]['start'])
  " No closer: finalizes at last line index 3
  call s:assert('orphan-box end', 3, s:blocks1[0]['end'])
endif

echo ''
echo '=== TEST 2: Box opener interrupted by Call marker — Call wins ==='
" A box opener with no closer, then a Call marker appears. The Call marker
" branch is checked before all states, so it finalizes the open box block
" and starts a new Call block. Expect 2 blocks.
let s:lines2 = [
      \ '╔══════════════════════════════════╗',
      \ '║ box output line 1                  ║',
      \ '║ box output line 2                  ║',
      \ '**~~ Call fs_cat {args} ~~**',
      \ '  /etc/hosts contents here']
let s:text2 = join(s:lines2, "\n")
let s:blocks2 = llm#detect_tool_blocks(s:text2)
call s:assert_len('box-then-call', 2, s:blocks2)
if len(s:blocks2) >= 2
  " First block: the box, finalized when Call marker fires (ends line before marker)
  call s:assert('box-then-call[0] name', 'safe_script_executor', s:blocks2[0]['name'])
  call s:assert('box-then-call[0] start', 0, s:blocks2[0]['start'])
  call s:assert('box-then-call[0] end', 2, s:blocks2[0]['end'])
  " Second block: the Call, starts at marker (line 3), finalizes at EOF (line 4)
  call s:assert('box-then-call[1] name', 'fs_cat', s:blocks2[1]['name'])
  call s:assert('box-then-call[1] start', 3, s:blocks2[1]['start'])
  call s:assert('box-then-call[1] end', 4, s:blocks2[1]['end'])
endif

echo ''
echo '=== TEST 3: Timestamp Running/Completed pair detected ==='
" [HH:MM:SS] Running direct task ... [HH:MM:SS] Completed direct task
" forms a single safe_script_executor block.
let s:lines3 = [
      \ 'Narrative before task.',
      \ '[12:34:56] Running direct task',
      \ '  command output line 1',
      \ '  command output line 2',
      \ '[12:34:58] Completed direct task',
      \ 'Narrative after task.']
let s:text3 = join(s:lines3, "\n")
let s:blocks3 = llm#detect_tool_blocks(s:text3)
call s:assert_len('timestamp-pair', 1, s:blocks3)
if len(s:blocks3) >= 1
  call s:assert('timestamp-pair name', 'safe_script_executor', s:blocks3[0]['name'])
  " Running line is index 1
  call s:assert('timestamp-pair start', 1, s:blocks3[0]['start'])
  " Completed line is index 4 (inclusive end for box/timestamp close)
  call s:assert('timestamp-pair end', 4, s:blocks3[0]['end'])
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
