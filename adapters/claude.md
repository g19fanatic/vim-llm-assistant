<!-- BEGIN: preamble -->
> Loaded automatically by Claude Code at every session start. Adapted from `role-core.md` + `adapters/claude.md`. Project-local `CLAUDE.md` files (when present) layer on top of this one.
<!-- END: preamble -->

<!-- BEGIN: section-0 -->
**MANDATORY — NEVER SKIP — Execute before generating ANY response content.**

This protocol fires once: at the very first user message of a conversation. Complete ALL steps IN ORDER before writing any other output.

### Step 1: Memory Load + Transition Detection (Priority: HIGHEST)

The `agent-memory` skill lives outside Claude Code's plugin system. To execute its Auto-Load Protocol:

1. `Read /home/pdibiase/sources/llm-functions/skills/memory/agent-memory/SKILL.md` (full content, on every first message — it is the spec)
2. Follow its **§1 Auto-Load Protocol**:
   - **Tier 1 (Core, ≤3 calls)**: Read `/home/pdibiase/.config/aichat/memory/.memory-manifest.json`; load `tier1.files[]`. Fallback: list `~/.config/aichat/memory/global/core/` and Read up to 5 entries.
   - **Detect transition**: CONTINUE | RESUME | RETURN | PIVOT | SWITCH | FIRST (per the skill's table)
   - **Tier 2 (Project Context, ≤5 calls)**: From the manifest's `tier2_projects[<current-project>].files[]` if present, else `cat <project>/memory/project/toc.md` and load high-importance entries.
3. **Budget**: ≤8 tool calls total for Steps 1-2. Stop if exceeded.
4. **Auto-bootstrap** (per skill §1.5): if memory infrastructure is missing for the current project, silently create the directory tree.

### Step 2: Skills Warm (Priority: NORMAL)

Claude Code already injects available skills via a `<system-reminder>` at session start (the `available-skills` list). Read those names and trigger descriptions into active awareness. **Do NOT load full skill content** — only names and triggers.

For llm-functions skills (which Claude Code does NOT auto-list), keep this index in mind and Read the relevant `SKILL.md` only when a trigger matches:

| Trigger keywords | Skill path |
|---|---|
| "remember", "save this", "recall", "memory" | `/home/pdibiase/sources/llm-functions/skills/memory/agent-memory/SKILL.md` |
| commit message drafting | `/home/pdibiase/sources/llm-functions/skills/git/git-commit-helper/SKILL.md` |
| organize files / Johnny.Decimal | `/home/pdibiase/sources/llm-functions/skills/organize/file-organizer/SKILL.md` |
| CircleCI status / pipeline failures | `/home/pdibiase/sources/llm-functions/skills/circleci/circleci-monitor/SKILL.md` |
| sourcegraph search | `/home/pdibiase/sources/llm-functions/skills/sourcegraph/sourcegraph-search/SKILL.md` |
| graphify / large-file analysis | `/home/pdibiase/sources/llm-functions/skills/analysis/graphify/SKILL.md`, `large-file-introspection/SKILL.md` |
| diagrams (lucidchart CSV, SVG) | `/home/pdibiase/sources/llm-functions/skills/draw/*/SKILL.md` |

If a user's request matches a trigger and no Claude-Code-native skill covers it better, Read the SKILL.md and apply its guidance. If the user types a literal `@<name>` invocation, treat it as an explicit request to load that skill.

### Step 3: Status Checkpoint + Returning Briefing (Priority: CRITICAL)

**Your response MUST begin with a memory status line.** Format:

```
🧠 [core: N files loaded] | 📋 [project: N memories, {transition_qualifier}] | 🔧 [N skills available]
```

Transition qualifiers:
- CONTINUE: `[project: continuing]`
- RESUME: `[project: N memories, resuming <topic>]`
- RETURN: `[project: N memories, returning after <duration>]`
- PIVOT: `[project: N memories, pivoting to <topic>]`
- SWITCH: `[project: N memories for <project-name>]`
- FIRST: `[new project — no memories yet]`

Failure variants:
```
🧠 ⚠️ No core memories found | 📋 [project: N memories] | 🔧 [N skills]
🧠 [core: N files] | 📋 ⚠️ No project memories | 🔧 [N skills]
🧠 ⚠️ Memory loading failed — operating without context | 🔧 [N skills]
```

The skill count includes BOTH Claude Code's native skills (from the `<system-reminder>` `available-skills` list) AND the llm-functions skills index above.

**After status line**: Emit returning briefing (variable depth per transition type):
- CONTINUE: No briefing
- RESUME: Quick reminder (2-4 lines: last state + next step + unresolved count)
- RETURN: Full briefing (8-15 lines: changes + active work + unresolved + suggestions)
- PIVOT: Topic switch note (3-5 lines: previous work + new context)
- SWITCH: Project switch notification (1-2 lines)
- FIRST: Setup guidance (2-3 lines)

**Rules**:
- Status line is the FIRST LINE of your FIRST response. Nothing precedes it.
- Emit it even if loading failed completely — the failure message IS the checkpoint.
- After the status line + briefing, proceed with normal response.
- Subsequent messages in the same conversation do NOT repeat this line.
- If the user's first message is a slash command or skill invocation, the status line still appears first, THEN the command/skill response follows.

### Failure Recovery

If any step fails, continue to the next step. Never stall the conversation.

| Failure | Recovery |
|---|---|
| Manifest unreadable | Fall back to `ls` core directory |
| Core directory empty | Emit ⚠️ in status, continue to Step 2 |
| Git repo not detected | Skip Tier 2 entirely |
| agent-memory SKILL.md missing | Emit ⚠️ in status, operate without memory |
| All steps fail | Emit full failure status line, proceed with response |

The conversation MUST continue regardless of loading failures. Memory enhances responses but its absence never blocks them.
<!-- END: section-0 -->

<!-- BEGIN: context-hierarchy -->
### Context Hierarchy (priority order)

1. **The user's current message + open files explicitly referenced** — primary signal
2. **Files Claude Code has already Read this session** — already in context, treat as authoritative
3. **Agent memory (semantic + episodic)** — loaded automatically via §0
4. **Project-local CLAUDE.md and `project_info/` documentation** — load on demand
5. **Codebase exploration** (Read, Grep, Bash) — when the above is insufficient
6. **Web search / external** (WebFetch, WebSearch, deep-research skill) — last resort, when the question genuinely needs external sources

Guidelines:
- Don't search before checking what's already loaded.
- Document whether responses use loaded context vs. fresh investigation when it's not obvious.
<!-- END: context-hierarchy -->

<!-- BEGIN: section-3 -->
Use Claude Code's built-in **TaskCreate / TaskUpdate / TaskList**. These persist in the harness; no separate `todos.md` file is needed.

- Create tasks during PLAN; refine during REVIEW; mark in_progress / completed during APPLY.
- One concept per task. Brief description, optional details.
- Mark `in_progress` when starting; `completed` as soon as done — never batch completions.
- For cross-session work, link the task to a `type: session` memory (record the task ref in the memory's frontmatter `task_ref`) so resumption context survives.
<!-- END: section-3 -->

<!-- BEGIN: tool-usage -->
- Always Read a file before Editing it.
- Use the right tool: Read for reading, Edit for in-place edits, Write only for new files / complete rewrites, Bash for shell-only operations.
- Provide all required parameters; use exact user-specified values.
- On error, analyze and adjust — don't retry blindly.
<!-- END: tool-usage -->

<!-- BEGIN: subagent-tools -->
Use the **Agent** tool (and specialized subagent types: `Explore`, `general-purpose`, `Plan`, `code-reviewer`, etc.) for parallel or isolated work. Use **Workflow** only when the user has explicitly opted into multi-agent orchestration.

### Prompt Guidelines for Agents

- Brief the agent like a smart colleague who just walked in: what you're trying to accomplish, what you've ruled out, surrounding context for judgment calls.
- Specify deliverable format (markdown report, structured data, code).
- Assume the subagent has no access to the current conversation or open buffers.
- Cap response length when appropriate ("report in under 200 words").

### Result Integration
- Verify subagent outputs align with original task requirements.
- Integrate findings into current workflow stage (PLAN/REVIEW/APPLY).
- Document subagent-generated content sources in final responses.
<!-- END: subagent-tools -->

<!-- BEGIN: section-7 -->
Claude Code surfaces its built-in/plugin skills via `<system-reminder>` (`available-skills` block) at session start. llm-functions skills are NOT auto-listed — see the index in §0 Step 2.

### Tool & Skill Locations on Disk

Skills and tools from the llm-functions project are available for direct Read/execution:

```
~/sources/llm-functions/
├── skills/           # Skill definitions (SKILL.md files)
│   ├── memory/       # agent-memory, johnny-decimal-brain
│   ├── git/          # git-commit-helper
│   ├── organize/     # file-organizer
│   ├── circleci/     # circleci-monitor
│   ├── sourcegraph/  # sourcegraph-search
│   ├── analysis/     # graphify, large-file-introspection
│   ├── draw/         # lucidchart-csv, svg-diagram-generator
│   └── ...           # Many more — ls to discover
└── tools/            # Tool implementations (Python/Bash scripts)
    ├── subagent.py
    ├── ralph_loop.sh
    ├── safe_script_executor.sh
    ├── skills.py
    └── ...           # ls to discover
```

To discover all available llm-functions skills:
```bash
find ~/sources/llm-functions/skills -name "SKILL.md" -exec dirname {} \; | sort
```

### Invocation

- `/<skill-name>` — Claude Code skill (built-in or plugin). Invoke via the **Skill** tool with `skill: "<name>"`.
- `@<skill-name>` — explicit llm-functions skill request (legacy aichat pattern). Read the SKILL.md from the path in the §0 index, then apply.
- Natural-language trigger match — proactively suggest or invoke when a request matches a known trigger. Confirm before invoking only if the action is consequential.

### Detection

When a message starts with `/` or `@` followed by a skill name, treat it as a hard trigger. Parse the name, load the skill, acknowledge invocation, apply guidance.

**Errors**:
- Skill not found: list alternatives (Claude Code: list from `available-skills`; llm-functions: list directory at `/home/pdibiase/sources/llm-functions/skills/`).
- Ambiguous: present matching options.
- Malformed: request correct format.

### Workflow Integration

- Skills augment the current PLAN/REVIEW/APPLY stage; they don't override stage gating.
- Skill context applies to the current task.
- Multiple skills can be combined sequentially — explicitly reference prior loads when combining.
<!-- END: section-7 -->

<!-- BEGIN: section-8 -->
Claude Code provides built-in slash commands (`/help`, `/clear`, `/compact`, `/config`, etc.) and skill-backed commands. The legacy aichat-only commands (`/save`, `/info`, `/summarize`, `/refactor`, `/audit`, `/research`, `/list`) do NOT exist here — their concepts are preserved as workflow practices instead:

| Old aichat command | Replacement in Claude Code |
|---|---|
| `/save` | Memory write triggers (§5). Use `agent-memory` skill to save. |
| `/info` | Read `project_info/*.md` directly when relevant. |
| `/summarize` | Manual consolidation via `agent-memory /consolidate`, or by re-organizing `project_info/`. |
| `/compact` | Native `/compact` (Claude Code) — also triggers an episode write per §5. |
| `/refactor` | Apply normal PLAN→REVIEW→APPLY workflow with refactoring focus. Use `simplify` skill if installed. |
| `/audit` | Use `code-review` or `security-review` skills if installed; otherwise PLAN→REVIEW with explicit findings. |
| `/research` | Use `deep-research` skill (Claude Code) when the question warrants multi-source verification. |
| `/list` | Skills list is in the `<system-reminder>` `available-skills` block. |
| `/init` | Native — initializes `CLAUDE.md` for the current project. |

### Code Location References

When discussing or modifying code, capture explicit locations:
- **Format**: `filepath:line` (single line) or `filepath:start-end` (range).
- **Example**: `src/auth/login.py:45-67` — main login handler.

Capture for: entry points, API endpoints, core business logic, key data structures, configuration, code discussed/modified in conversation, important error handling.

### Shell Execution

Use the **Bash** tool. The `validate-bash.sh` PreToolUse hook validates each command via `safe_script_executor` before execution. Trust its verdict; on `ask`, the user will decide.

For multi-step shell logic where validation is desired, the hook handles it transparently — you don't need to invoke `safe_script_executor` directly.

### Risk Awareness

Carefully consider reversibility and blast radius. Local, reversible actions (file edits, tests, builds) are fine. For destructive or shared-state actions (force-push, dropping branches, sending messages, modifying shared infra), confirm with the user before proceeding — even if a similar action was approved earlier in the session. Authorization stands for the scope specified, not beyond.
<!-- END: section-8 -->
