#!/bin/bash
# build-roles.sh — Assemble system prompts from role-core.md + adapters
#
# Usage: ./build-roles.sh [--verify] [--dry-run]
# Outputs:
#   ./default-vim-role.md          (aichat)
#   ~/.claude/CLAUDE.md            (Claude Code, copied)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/role-core.md"
AICHAT_ADAPTER="$SCRIPT_DIR/adapters/aichat.md"
CLAUDE_ADAPTER="$SCRIPT_DIR/adapters/claude.md"
AICHAT_OUT="$SCRIPT_DIR/default-vim-role.md"
CLAUDE_OUT="$SCRIPT_DIR/.generated-claude.md"
CLAUDE_DEST="$HOME/.claude/CLAUDE.md"

DRY_RUN=false
VERIFY=false

for arg in "$@"; do
    case "$arg" in
        --verify) VERIFY=true ;;
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

assemble() {
    local adapter="$1"
    local output="$2"
    local label="$3"

    python3 - "$CORE" "$adapter" "$output" << 'PYTHON'
import sys
import re

core_path, adapter_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

def parse_adapter_blocks(content):
    """Parse adapter file into named blocks delimited by BEGIN/END markers."""
    blocks = {}
    current_name = None
    current_lines = []

    for line in content.split('\n'):
        begin_match = re.match(r'^<!--\s*BEGIN:\s*(\S+)\s*-->', line)
        end_match = re.match(r'^<!--\s*END:\s*(\S+)\s*-->', line)

        if begin_match:
            current_name = begin_match.group(1)
            current_lines = []
        elif end_match:
            if current_name:
                blocks[current_name] = '\n'.join(current_lines).strip()
            current_name = None
            current_lines = []
        elif current_name is not None:
            current_lines.append(line)

    return blocks

def assemble_output(core_content, blocks):
    """Replace <!-- INJECT: name --> markers in core with adapter blocks."""
    lines = core_content.split('\n')
    output_lines = []

    for line in lines:
        inject_match = re.match(r'^<!--\s*INJECT:\s*(\S+)\s*-->', line.strip())
        if inject_match:
            block_name = inject_match.group(1)
            if block_name in blocks:
                output_lines.append(blocks[block_name])
            else:
                # Leave a comment noting the missing block
                output_lines.append(f'<!-- WARNING: No adapter block found for "{block_name}" -->')
        else:
            output_lines.append(line)

    return '\n'.join(output_lines)

# Read files
with open(core_path) as f:
    core_content = f.read()
with open(adapter_path) as f:
    adapter_content = f.read()

# Parse adapter blocks
blocks = parse_adapter_blocks(adapter_content)

# Handle preamble: insert before the core content
preamble = blocks.pop('preamble', '')
assembled = assemble_output(core_content, blocks)

# Prepend preamble if it exists
if preamble:
    assembled = preamble + '\n' + assembled

with open(output_path, 'w') as f:
    f.write(assembled + '\n')

print(f"  Generated: {output_path} ({len(assembled.split(chr(10)))} lines)")
PYTHON

    echo "  Built: $label"
}

echo "Building system prompts..."
echo ""

assemble "$AICHAT_ADAPTER" "$AICHAT_OUT" "aichat (default-vim-role.md)"
assemble "$CLAUDE_ADAPTER" "$CLAUDE_OUT" "claude (.generated-claude.md)"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== DRY RUN — not copying to $CLAUDE_DEST ==="
    echo "Would copy: $CLAUDE_OUT → $CLAUDE_DEST"
else
    cp "$CLAUDE_OUT" "$CLAUDE_DEST"
    echo ""
    echo "  Copied to: $CLAUDE_DEST"
fi

if [ "$VERIFY" = true ]; then
    echo ""
    echo "=== Verification ==="
    echo "aichat output: $(wc -l < "$AICHAT_OUT") lines, $(wc -c < "$AICHAT_OUT") bytes"
    echo "claude output: $(wc -l < "$CLAUDE_OUT") lines, $(wc -c < "$CLAUDE_OUT") bytes"
    echo ""
    echo "Section coverage:"
    for f in "$AICHAT_OUT" "$CLAUDE_OUT"; do
        sections=$(grep -c '^## ' "$f" || true)
        echo "  $(basename $f): $sections top-level sections"
    done
    echo ""
    echo "Injection markers remaining (should be 0):"
    for f in "$AICHAT_OUT" "$CLAUDE_OUT"; do
        remaining=$(grep -c 'INJECT:' "$f" || true)
        echo "  $(basename $f): $remaining"
    done
    echo ""
    echo "Missing block warnings:"
    for f in "$AICHAT_OUT" "$CLAUDE_OUT"; do
        warnings=$(grep -c 'WARNING: No adapter block' "$f" || true)
        echo "  $(basename $f): $warnings"
    done
fi
