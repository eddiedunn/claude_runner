#!/usr/bin/env bash
# offload_to_docker.sh
# Triggered by Claude Code PreToolUse hook to offload the plan execution
# to an isolated Docker container that re-uses the host's Claude Max credentials.
#
# The script reads the session_id from the hook payload (stdin), starts a
# claude-runner:latest container with the workspace & credentials mounted, then
# resumes the same session inside the container. Finally it creates a marker
# file so subsequent invocations can detect completion, and exits with status 2
# to block local tool execution.

set -euo pipefail

# Read entire JSON payload from stdin
payload="$(cat)"

# Extract session ID (requires jq inside host; documented in TASK_LIST.md)
SESSION_ID=$(jq -r '.session_id' <<<"$payload")
if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  echo "[offload_to_docker] ERROR: Could not read session_id from hook payload" >&2
  exit 1
fi

echo "[offload_to_docker] Offloading session $SESSION_ID to Docker…"

# Location of the workspace on the host (provided by Claude CLI env var)
WORKSPACE="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Ensure the offload marker is cleared so we dont short-circuit prematurely
offload_done_file="$WORKSPACE/.claude/offload_done"
rm -f "$offload_done_file"

# Run the claude-runner container
# - USE_CLAUDE_CREDENTIALS=true tells the CLI to look for ~/.claude/.credentials.json
# - We mount the host credential dir read-only; refresh tokens will not update
#   when mounted ro, but suffices for one-shot runs.
docker run --rm \
  --user 1000:1000 \
  -e USE_CLAUDE_CREDENTIALS=true \
  -v "$HOME/.claude:/home/node/.claude:ro" \
  -v "$WORKSPACE":/workspace \
  claude-runner:latest bash -lc "\
    cd /workspace && \
    claude -p --resume \"$SESSION_ID\" \
      --dangerously-skip-permissions \
      --allowedTools \"Read,Write,Edit,Bash,Git\" \
      --disallowedTools \"Bash(git push:*)\" \
      --max-turns 50 \"Proceed with the approved plan, create a **local** branch called feature/auto, commit all changes, DO NOT push.\""

echo "[offload_to_docker] Plan execution finished inside container."

touch "$offload_done_file"

# Exit code 2 to prevent the local tool call from continuing
exit 2
