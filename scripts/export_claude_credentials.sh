#!/usr/bin/env bash
# export_claude_credentials.sh
# Exports Claude credentials from macOS Keychain and rewrites them for use by the CLI in Docker.
# Usage: ./scripts/export_claude_credentials.sh

set -euo pipefail

CRED_FILE="$HOME/.claude/.credentials.json"

# Try new and legacy service labels
RAW_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
if [[ -z "$RAW_JSON" ]]; then
  RAW_JSON=$(security find-generic-password -s "Claude Code" -w 2>/dev/null || true)
fi

if [[ -z "$RAW_JSON" ]]; then
  echo "[export_claude_credentials] ERROR: No Claude credentials found in Keychain." >&2
  exit 1
fi

# Extract inner object if wrapped in {"claudeAiOauth": ...}
if echo "$RAW_JSON" | grep -q '"claudeAiOauth"'; then
  # Use jq to extract the inner object
  jq '.claudeAiOauth' <<< "$RAW_JSON" > "$CRED_FILE"
else
  # Already in expected format
  echo "$RAW_JSON" > "$CRED_FILE"
fi

chmod 600 "$CRED_FILE"
echo "[export_claude_credentials] Exported and formatted credentials to $CRED_FILE"
