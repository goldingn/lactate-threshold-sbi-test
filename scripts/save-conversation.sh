#!/usr/bin/env bash
#
# save-conversation.sh
#
# Save the current Claude Code conversation history into this repository and
# commit it, so each phase-2 (agentic Bayesian SBI) experiment leaves a durable
# record of the conversation that produced it.
#
# Usage:
#   scripts/save-conversation.sh [name] [--dry-run]
#
#   name       Optional label for the saved conversation. Defaults to the
#              current git branch name.
#   --dry-run  Locate the session log and report what would be saved, but do
#              not copy, render, or commit anything.
#
# Where it saves:
#   conversations/phase1/<name>.{jsonl,md}   when on the main/master branch
#   conversations/phase2/<name>.{jsonl,md}   on any other branch
#
# What it saves:
#   <name>.jsonl   the raw Claude Code session log (canonical, complete record)
#   <name>.md      a human-readable transcript (best effort; needs python3)
#
# How the session log is found:
#   Claude Code stores per-project session logs as
#     ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug>/<session-id>.jsonl
#   where <slug> is the repo's absolute path with every non-alphanumeric
#   character replaced by "-". The most-recently-modified .jsonl is taken to be
#   the current session. Run this from within the Claude session you want to
#   save (ideally as the final step of the experiment). To pin an exact session,
#   set CLAUDE_SESSION_ID to its id.
#
set -euo pipefail

# ---- parse args ------------------------------------------------------------
NAME=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
    *)            NAME="$arg" ;;
  esac
done

# ---- repo location & phase -------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
NAME="${NAME:-$BRANCH}"
SAFE_NAME=$(printf '%s' "$NAME" | sed 's#[^A-Za-z0-9._-]#-#g')

case "$BRANCH" in
  main|master) PHASE="phase1" ;;
  *)           PHASE="phase2" ;;
esac
DEST_DIR="conversations/$PHASE"

# ---- locate the Claude Code session log ------------------------------------
PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
SLUG=$(printf '%s' "$REPO_ROOT" | sed 's#[^A-Za-z0-9]#-#g')
SESSION_DIR="$PROJECTS_DIR/$SLUG"

if [ ! -d "$SESSION_DIR" ]; then
  echo "ERROR: no Claude session directory at $SESSION_DIR" >&2
  echo "       Set CLAUDE_CONFIG_DIR if your Claude config lives elsewhere." >&2
  exit 1
fi

if [ -n "${CLAUDE_SESSION_ID:-}" ] && [ -f "$SESSION_DIR/$CLAUDE_SESSION_ID.jsonl" ]; then
  SESSION_FILE="$SESSION_DIR/$CLAUDE_SESSION_ID.jsonl"
else
  SESSION_FILE=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -n1 || true)
fi

if [ -z "${SESSION_FILE:-}" ] || [ ! -f "$SESSION_FILE" ]; then
  echo "ERROR: no .jsonl session log found in $SESSION_DIR" >&2
  exit 1
fi

DEST_JSONL="$DEST_DIR/$SAFE_NAME.jsonl"
DEST_MD="$DEST_DIR/$SAFE_NAME.md"

echo "Branch:      $BRANCH  ($PHASE)"
echo "Session log: $SESSION_FILE"
echo "Destination: $DEST_JSONL"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] nothing written or committed."
  exit 0
fi

# ---- copy + render + commit ------------------------------------------------
mkdir -p "$DEST_DIR"
cp "$SESSION_FILE" "$DEST_JSONL"
echo "Saved session log -> $DEST_JSONL"

FILES=("$DEST_JSONL")
if command -v python3 >/dev/null 2>&1; then
  if python3 "$REPO_ROOT/scripts/jsonl_to_markdown.py" "$DEST_JSONL" "$DEST_MD" "$NAME"; then
    echo "Rendered transcript -> $DEST_MD"
    FILES+=("$DEST_MD")
  else
    echo "(markdown render failed; keeping .jsonl only)"
  fi
else
  echo "(python3 not found; skipping markdown transcript)"
fi

git add "${FILES[@]}"
if git diff --cached --quiet; then
  echo "No changes to commit (conversation already up to date)."
  exit 0
fi
git commit -m "Save $PHASE conversation history: $NAME" >/dev/null
echo "Committed conversation history for '$NAME'. Push with: git push"
