# Plan Breakdown: LLMLog Toolset Enhancement

## Summary
- Epics: 2 | Milestones: 4 | Tasks: 7
- Estimated iterations: 10 (7 tasks × 1.3 retry buffer)
- Suggested max_parallel: 1 (all code tasks touch same files: autoload/llm/log.vim, plugin/llm.vim)
- Sequential execution order optimized for: foundational fixes first, new features second, documentation last

## Dependency Graph
```
Task 1 (fix 'none')  ──────────────┐
Task 2 (error msgs)  ──┐           │
Task 3 (tail types)  ──┤ independent│
Task 5 (history)     ──┤           │
Task 6 (search)      ──┘           │
                                   ▼
Task 4 (debug toggle) ────── depends on Task 1
Task 7 (documentation) ────── last (documents final state)
```

---

## L1: Epic 1 — Code Changes (Log Toolset Features)

### L2: Milestone A — Foundation Fixes

| # | Task | Files | Depends |
|---|------|-------|---------|
| 1 | Fix g:llm_log_level='none' override | plugin/llm.vim:45-47, autoload/llm/log.vim:199 | [] |
| 2 | Improve error messaging for debug-only log access | autoload/llm/log.vim:96-130 | [] |

### L2: Milestone B — Extend Existing Commands

| # | Task | Files | Depends |
|---|------|-------|---------|
| 3 | Add :LLMLogTail tools and :LLMLogTail session support | autoload/llm/log.vim:138-169, autoload/llm/log.vim:56-63 | [] |
| 4 | Add :LLMLogDebug toggle command | autoload/llm/log.vim (new func ~line 196), plugin/llm.vim:87-90 | [1] |

### L2: Milestone C — New Commands

| # | Task | Files | Depends |
|---|------|-------|---------|
| 5 | Add :LLMLogHistory [N] to browse past request directories | autoload/llm/log.vim (new func), plugin/llm.vim:87-90 | [] |
| 6 | Add :LLMLogSearch <pattern> for session.log grep | autoload/llm/log.vim (new func), plugin/llm.vim:87-90 | [] |

---

## L1: Epic 2 — Documentation

### L2: Milestone D — User Documentation

| # | Task | Files | Depends |
|---|------|-------|---------|
| 7 | Add comprehensive "Log Access & Debugging" section to build_run_test.md | project_info/build_run_test.md | [1,2,3,4,5,6] |

---

## Parallelism Map
- Round 1: Task 1 (foundational fix)
- Round 2: Tasks 2, 3 (independent, but same file — sequential)
- Round 3: Task 4 (depends on 1)
- Round 4: Tasks 5, 6 (independent, but same file — sequential)
- Round 5: Task 7 (depends on all code tasks)

**Note**: Since all code tasks modify `autoload/llm/log.vim`, they MUST execute sequentially to avoid merge conflicts. max_parallel=1 is required.
