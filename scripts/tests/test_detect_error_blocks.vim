set nocompatible
" Test: llm#detect_error_blocks() — Task 3 verification
" Run: vim --not-a-term -u NONE -S scripts/tests/test_detect_error_blocks.vim

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
echo '=== TEST 1: No error blocks ==='
let s:lines1 = ['This is normal narrative text.', 'No errors here.', 'Just plain conversation.']
let s:text1 = join(s:lines1, "\n")
let s:blocks1 = llm#detect_error_blocks(s:text1)
call s:assert_len('no-errors text', 0, s:blocks1)

echo ''
echo '=== TEST 2: Single ERROR: tool execution failed block ==='
let s:lines2 = [
      \ '**~~ Call safe_script_executor {args} ~~**',
      \ 'ERROR: tool execution failed: safe_script_executor',
      \ '  Stack trace line 1',
      \ '  Stack trace line 2',
      \ '  Exit code: 1',
      \ '']
let s:text2 = join(s:lines2, "\n")
let s:blocks2 = llm#detect_error_blocks(s:text2)
call s:assert_len('single-error-1', 1, s:blocks2)
if len(s:blocks2) >= 1
  call s:assert('single-error-1 name', 'safe_script_executor', s:blocks2[0]['name'])
  call s:assert('single-error-1 start', 1, s:blocks2[0]['start'])
endif

echo ''
echo '=== TEST 3: ERROR (exit code N) block ==='
let s:lines3 = [
      \ 'Some narrative before the error.',
      \ 'ERROR (exit code 127): command not found',
      \ '  /bin/bash: foo: command not found',
      \ '  Additional error details here',
      \ '']
let s:text3 = join(s:lines3, "\n")
let s:blocks3 = llm#detect_error_blocks(s:text3)
call s:assert_len('exit-code-error', 1, s:blocks3)
if len(s:blocks3) >= 1
  call s:assert('exit-code-error name', 'error_exit_127', s:blocks3[0]['name'])
  call s:assert('exit-code-error start', 1, s:blocks3[0]['start'])
endif

echo ''
echo '=== TEST 4: Error block terminated by blank + narrative ==='
let s:lines4 = [
      \ 'ERROR: tool execution failed: fs_cat',
      \ '  No such file or directory',
      \ '  at path /tmp/missing.txt',
      \ '',
      \ 'This is narrative text after the error.',
      \ 'It should NOT be part of the error block.']
let s:text4 = join(s:lines4, "\n")
let s:blocks4 = llm#detect_error_blocks(s:text4)
call s:assert_len('blank-terminated', 1, s:blocks4)
if len(s:blocks4) >= 1
  call s:assert('blank-terminated name', 'fs_cat', s:blocks4[0]['name'])
  " Block should end at line 2 (last error output before blank line at idx 3)
  call s:assert('blank-terminated end', 2, s:blocks4[0]['end'])
endif

echo ''
echo '=== TEST 5: Error block terminated by Call marker ==='
let s:lines5 = [
      \ 'ERROR: tool execution failed: safe_script_executor',
      \ '  Error output line 1',
      \ '  Error output line 2',
      \ '**~~ Call fs_cat {args} ~~**',
      \ '  /etc/hosts contents here']
let s:text5 = join(s:lines5, "\n")
let s:blocks5 = llm#detect_error_blocks(s:text5)
call s:assert_len('call-marker-terminated', 1, s:blocks5)
if len(s:blocks5) >= 1
  call s:assert('call-marker-terminated name', 'safe_script_executor', s:blocks5[0]['name'])
  " Block ends at line 2 (line before the Call marker at idx 3)
  call s:assert('call-marker-terminated end', 2, s:blocks5[0]['end'])
endif

echo ''
echo '=== TEST 6: Multiple consecutive error blocks ==='
let s:lines6 = [
      \ 'ERROR: tool execution failed: tool_a',
      \ '  First error output',
      \ 'ERROR: tool execution failed: tool_b',
      \ '  Second error output',
      \ 'ERROR (exit code 2):',
      \ '  Third error output']
let s:text6 = join(s:lines6, "\n")
let s:blocks6 = llm#detect_error_blocks(s:text6)
call s:assert_len('multi-error', 3, s:blocks6)
if len(s:blocks6) >= 3
  call s:assert('multi-error[0] name', 'tool_a', s:blocks6[0]['name'])
  call s:assert('multi-error[1] name', 'tool_b', s:blocks6[1]['name'])
  call s:assert('multi-error[2] name', 'error_exit_2', s:blocks6[2]['name'])
endif

echo ''
echo '=== TEST 7: chars field reflects output size ==='
let s:lines7 = [
      \ 'ERROR: tool execution failed: my_tool',
      \ 'line one of output',
      \ 'line two of output']
let s:text7 = join(s:lines7, "\n")
let s:blocks7 = llm#detect_error_blocks(s:text7)
call s:assert_len('chars-check', 1, s:blocks7)
if len(s:blocks7) >= 1
  " Output lines: "line one of output\nline two of output"
  let s:expected_chars = len("line one of output\nline two of output")
  call s:assert('chars-check chars', s:expected_chars, s:blocks7[0]['chars'])
endif

echo ''
echo '=== TEST 8: Zero-char block (ERROR marker followed by blank + narrative) ==='
" ERROR marker immediately followed by a blank line then narrative.
" The blank terminates the block with NO output lines -> chars == 0.
" prune_tool_outputs must then emit NO placeholder (min_chars filter).
let s:lines8 = [
      \ 'ERROR: tool execution failed: zero_tool',
      \ '',
      \ 'This is narrative that follows immediately after the error marker.',
      \ 'It is ordinary conversation, not part of the error output.']
let s:text8 = join(s:lines8, "\n")
let s:blocks8 = llm#detect_error_blocks(s:text8)
call s:assert_len('zero-char', 1, s:blocks8)
if len(s:blocks8) >= 1
  call s:assert('zero-char name', 'zero_tool', s:blocks8[0]['name'])
  call s:assert('zero-char start', 0, s:blocks8[0]['start'])
  call s:assert('zero-char chars', 0, s:blocks8[0]['chars'])
endif
" prune_tool_outputs: chars=0 < min_chars(200) -> no placeholder emitted.
let s:pruned8 = llm#prune_tool_outputs(s:text8, 0)
call s:assert('zero-char no placeholder', -1, stridx(s:pruned8, 'chars removed'))
call s:assert('zero-char text preserved', 1, s:pruned8 ==# s:text8)

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
