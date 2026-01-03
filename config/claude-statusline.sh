#!/bin/bash
# Claude Code status line - shows model, context, tasks (no cost)
# Install: Add to ~/.claude/settings.json:
# {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 0}}

# Parse JSON input from Claude Code
INPUT=$(cat)

# Extract values using jq
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"' 2>/dev/null)
CONTEXT_USED=$(echo "$INPUT" | jq -r '.usage.context_tokens // 0' 2>/dev/null)
CONTEXT_MAX=$(echo "$INPUT" | jq -r '.usage.context_limit // 200000' 2>/dev/null)

# Calculate context percentage
if [[ "$CONTEXT_MAX" -gt 0 ]] && [[ "$CONTEXT_USED" =~ ^[0-9]+$ ]]; then
    CONTEXT_PCT=$(echo "scale=0; $CONTEXT_USED * 100 / $CONTEXT_MAX" | bc 2>/dev/null || echo "?")
else
    CONTEXT_PCT="?"
fi

# Current directory (abbreviated)
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // "~"' 2>/dev/null | sed "s|$HOME|~|")
DIR_SHORT=$(echo "$DIR" | rev | cut -d'/' -f1-2 | rev)

# Git branch (if in a git repo)
GIT_BRANCH=""
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
fi

# Task count from Claude's todo system
TASK_INFO=""
TODOS_DIR="$HOME/.claude/todos"
if [[ -d "$TODOS_DIR" ]]; then
    # Find most recent todo file
    TODOS_FILE=$(ls -t "$TODOS_DIR"/*.json 2>/dev/null | head -1)
    if [[ -f "$TODOS_FILE" ]]; then
        TOTAL_TASKS=$(jq '.todos | length' "$TODOS_FILE" 2>/dev/null || echo 0)
        DONE_TASKS=$(jq '[.todos[] | select(.status=="completed")] | length' "$TODOS_FILE" 2>/dev/null || echo 0)
        IN_PROGRESS=$(jq '[.todos[] | select(.status=="in_progress")] | length' "$TODOS_FILE" 2>/dev/null || echo 0)
        if [[ "$TOTAL_TASKS" -gt 0 ]]; then
            TASK_INFO="[$DONE_TASKS/$TOTAL_TASKS"
            [[ "$IN_PROGRESS" -gt 0 ]] && TASK_INFO="${TASK_INFO}+${IN_PROGRESS}"
            TASK_INFO="${TASK_INFO}]"
        fi
    fi
fi

# Build status line
OUTPUT="$MODEL"
OUTPUT="$OUTPUT | $DIR_SHORT"
[[ -n "$GIT_BRANCH" ]] && OUTPUT="$OUTPUT ($GIT_BRANCH)"
OUTPUT="$OUTPUT | ctx:${CONTEXT_PCT}%"
[[ -n "$TASK_INFO" ]] && OUTPUT="$OUTPUT $TASK_INFO"

echo -n "$OUTPUT"
