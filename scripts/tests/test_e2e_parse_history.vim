set nocompatible
" End-to-End Test: llm#parse_history_turns() with tool output pruning
" Tests the full pipeline: scratch buffer → parse_history_turns() → pruned results
" Assertions:
"   (a) Recent turns unchanged (last K=3 turns have full content)
"   (b) Old turns pruned ≥40% (per-turn and total reduction)
"   (c) Narrative text preserved in old turns (text BEFORE tool calls)
"   (d) Call markers preserved in old turns
" Run: vim --not-a-term -u NONE -S scripts/tests/test_e2e_parse_history.vim

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

function! s:assert_contains(label, needle, haystack)
  if stridx(a:haystack, a:needle) >= 0
    echo '  PASS: ' . a:label
    let s:pass += 1
  else
    echo '  FAIL: ' . a:label
    echo '    expected to find: ' . a:needle
    echo '    in:               ' . a:haystack[:80]
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
    echo '    in: ' . a:haystack[:80]
    let s:fail += 1
  endif
endfunction

" Create a scratch buffer with mock history content and set g:llm_scratch_bufnr
function! s:setup_scratch(lines)
  let l:buf = bufadd('[LLM-Scratch]')
  call bufload(l:buf)
  call setbufvar(l:buf, '&buftype', 'nofile')
  call deletebufline(l:buf, 1, '$')
  call setbufline(l:buf, 1, a:lines)
  let g:llm_scratch_bufnr = l:buf
  return l:buf
endfunction

" ============================================================
" Build the mock agentic session history — 5 turns total
" Turns 0 and 1 = old (will be pruned)
" Turns 2, 3, 4 = recent (recency=3, kept intact)
" ============================================================

" Large tool outputs (500 chars each) — distinct per turn to verify independently
let s:out_t0_a = repeat('A', 500)
let s:out_t0_b = repeat('B', 500)
let s:out_t1_a = repeat('C', 500)
let s:out_t1_b = repeat('D', 500)
let s:out_t1_c = repeat('E', 500)
let s:out_t2   = repeat('F', 500)
let s:out_t3   = repeat('G', 500)
let s:out_t4   = repeat('H', 500)

" Narrative text for old turn 0 (placed BEFORE tool calls so it survives pruning)
let s:narrative_0 = 'PRESERVED-NARRATIVE-TURN-ZERO'

" Build 5-turn scratch buffer content
" Turn 0 (old): narrative + 2 tool calls
" Turn 1 (old): 3 tool calls (no narrative)
" Turns 2,3,4 (recent): 1 tool call each

let s:history = []

" --- Turn 0 (old): narrative before tool calls ---
call add(s:history, '==== Thu 01 Jan 2026 09:00:00 AM EDT ====')
call add(s:history, 'Prompt: First user question here')
call add(s:history, s:narrative_0)
call add(s:history, '**~~ Call tool_read {"path":"/tmp/a.txt"} ~~**')
call add(s:history, s:out_t0_a)
call add(s:history, '**~~ Call tool_write {"path":"/tmp/b.txt"} ~~**')
call add(s:history, s:out_t0_b)
call add(s:history, '')

" --- Turn 1 (old): three tool calls, no narrative ---
call add(s:history, '==== Thu 01 Jan 2026 10:00:00 AM EDT ====')
call add(s:history, 'Prompt: Second user question here')
call add(s:history, '**~~ Call safe_script_executor {"script":"ls -la"} ~~**')
call add(s:history, s:out_t1_a)
call add(s:history, '**~~ Call fs_cat {"path":"/tmp/c.txt"} ~~**')
call add(s:history, s:out_t1_b)
call add(s:history, '**~~ Call fs_write {"path":"/tmp/d.txt"} ~~**')
call add(s:history, s:out_t1_c)
call add(s:history, '')

" --- Turn 2 (recent): one large tool call ---
call add(s:history, '==== Thu 01 Jan 2026 11:00:00 AM EDT ====')
call add(s:history, 'Prompt: Third user question here')
call add(s:history, '**~~ Call fs_read {"path":"/tmp/e.txt"} ~~**')
call add(s:history, s:out_t2)
call add(s:history, '')

" --- Turn 3 (recent): one large tool call ---
call add(s:history, '==== Thu 01 Jan 2026 12:00:00 PM EDT ====')
call add(s:history, 'Prompt: Fourth user question here')
call add(s:history, '**~~ Call fs_info {"path":"/tmp/f.txt"} ~~**')
call add(s:history, s:out_t3)
call add(s:history, '')

" --- Turn 4 (recent): one large tool call ---
call add(s:history, '==== Thu 01 Jan 2026 01:00:00 PM EDT ====')
call add(s:history, 'Prompt: Fifth user question here')
call add(s:history, '**~~ Call fs_ls {"path":"/tmp"} ~~**')
call add(s:history, s:out_t4)
call add(s:history, '')

call s:setup_scratch(s:history)

" Configure pruning
let g:llm_prune_recency = 3
let g:llm_prune_enabled = 1
let g:llm_prune_min_chars = 200

" Reset stats so we can verify they get populated
" Run parse_history_turns()
let s:turns = llm#parse_history_turns()

" ============================================================
echo ''
echo '=== TEST 1: Correct number of turns parsed ==='
" ============================================================
call s:assert('5 turns parsed', 5, len(s:turns))

" ============================================================
echo ''
echo '=== TEST 2: Old turns — Call markers preserved (criterion d) ==='
" ============================================================
call s:assert_contains('turn 0: tool_read marker preserved', '**~~ Call tool_read', s:turns[0].assistant)
call s:assert_contains('turn 0: tool_write marker preserved', '**~~ Call tool_write', s:turns[0].assistant)
call s:assert_contains('turn 1: safe_script_executor marker preserved', '**~~ Call safe_script_executor', s:turns[1].assistant)
call s:assert_contains('turn 1: fs_cat marker preserved', '**~~ Call fs_cat', s:turns[1].assistant)
call s:assert_contains('turn 1: fs_write marker preserved', '**~~ Call fs_write', s:turns[1].assistant)

" ============================================================
echo ''
echo '=== TEST 3: Old turns — verbose output removed (criterion b) ==='
" ============================================================
call s:assert_not_contains('turn 0: out_t0_a removed', s:out_t0_a, s:turns[0].assistant)
call s:assert_not_contains('turn 0: out_t0_b removed', s:out_t0_b, s:turns[0].assistant)
call s:assert_not_contains('turn 1: out_t1_a removed', s:out_t1_a, s:turns[1].assistant)
call s:assert_not_contains('turn 1: out_t1_b removed', s:out_t1_b, s:turns[1].assistant)
call s:assert_not_contains('turn 1: out_t1_c removed', s:out_t1_c, s:turns[1].assistant)

" Placeholder tokens should be present
call s:assert_contains('turn 0: placeholder for tool_read', '[Tool: tool_read', s:turns[0].assistant)
call s:assert_contains('turn 0: placeholder for tool_write', '[Tool: tool_write', s:turns[0].assistant)
call s:assert_contains('turn 1: placeholder for safe_script_executor', '[Tool: safe_script_executor', s:turns[1].assistant)

" ============================================================
echo ''
echo '=== TEST 4: Old turns — narrative text preserved (criterion c) ==='
" ============================================================
call s:assert_contains('turn 0: narrative preserved', s:narrative_0, s:turns[0].assistant)

" ============================================================
echo ''
echo '=== TEST 5: Recent turns unchanged (criterion a) ==='
" ============================================================
call s:assert_contains('turn 2: full output intact', s:out_t2, s:turns[2].assistant)
call s:assert_contains('turn 3: full output intact', s:out_t3, s:turns[3].assistant)
call s:assert_contains('turn 4: full output intact', s:out_t4, s:turns[4].assistant)

" Also verify recent turn markers are still present (they should be — not pruned)
call s:assert_contains('turn 2: marker present', '**~~ Call fs_read', s:turns[2].assistant)
call s:assert_contains('turn 3: marker present', '**~~ Call fs_info', s:turns[3].assistant)
call s:assert_contains('turn 4: marker present', '**~~ Call fs_ls', s:turns[4].assistant)

" ============================================================
echo ''
echo '=== TEST 6: Per-turn reduction ≥40% for old turns (criterion b) ==='
" ============================================================
" Verify per-turn stats are populated
let s:stats = llm#get_prune_stats()
call s:assert_true('stats populated', !empty(s:stats))
call s:assert_true('stats has turns', has_key(s:stats, 'turns'))

if !empty(s:stats) && has_key(s:stats, 'turns')
  let s:t0_stats = s:stats.turns[0]
  let s:t1_stats = s:stats.turns[1]
  let s:t2_stats = s:stats.turns[2]

  " Old turns should show ≥40% reduction
  call s:assert_true('turn 0 reduction ≥40%', s:t0_stats.pct >= 40)
  call s:assert_true('turn 1 reduction ≥40%', s:t1_stats.pct >= 40)

  " Recent turns should have 0% reduction (is_recent=1)
  call s:assert('turn 2 is_recent=1', 1, s:t2_stats.is_recent)
  call s:assert('turn 2 unchanged (0% reduction)', 0, s:t2_stats.pct)

  echo '    turn 0 reduction: ' . s:t0_stats.pct . '%'
  echo '    turn 1 reduction: ' . s:t1_stats.pct . '%'
  echo '    turn 2 reduction: ' . s:t2_stats.pct . '% (should be 0)'
endif

" ============================================================
echo ''
echo '=== TEST 7: Total reduction ≥40% across full session (criterion b overall) ==='
" ============================================================
if !empty(s:stats)
  let s:total_before = s:stats.total_before
  let s:total_after  = s:stats.total_after
  let s:total_pct = (s:total_before > 0)
        \ ? (100 * (s:total_before - s:total_after) / s:total_before)
        \ : 0
  call s:assert_true('total reduction ≥40%', s:total_pct >= 40)
  echo '    total before: ' . s:total_before
  echo '    total after:  ' . s:total_after
  echo '    total reduction: ' . s:total_pct . '%'
endif

" ============================================================
echo ''
echo '=== TEST 8: Kill switch — g:llm_prune_enabled=0 disables all pruning ==='
" ============================================================
let g:llm_prune_enabled = 0
call s:setup_scratch(s:history)
let s:turns_disabled = llm#parse_history_turns()
" When disabled, pruning block is skipped — old turns should still have full output
call s:assert_contains('disabled: turn 0 still has out_t0_a', s:out_t0_a, s:turns_disabled[0].assistant)
call s:assert_contains('disabled: turn 1 still has out_t1_a', s:out_t1_a, s:turns_disabled[1].assistant)
" Stats should not be overwritten when disabled — prior (enabled-run) stats remain intact
call s:assert_true('disabled: prior stats untouched (turns present)', has_key(llm#get_prune_stats(), 'turns'))
" Re-enable for subsequent tests
let g:llm_prune_enabled = 1

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
