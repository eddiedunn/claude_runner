#!/usr/bin/env bash
# update_claude_cli.sh – install or upgrade Claude Code CLI.
# Usage:  ./scripts/update_claude_cli.sh            # installs latest
#         ./scripts/update_claude_cli.sh 1.1.0      # installs specific

set -euo pipefail

# Accept optional version argument
REQUESTED_VERSION="${1:-}"

if [[ "$REQUESTED_VERSION" == "--help" || "$REQUESTED_VERSION" == "-h" ]]; then
  echo "Usage: $0 [version]" >&2
  exit 0
fi

# If no version supplied, query npm for latest
if [[ -z "$REQUESTED_VERSION" ]]; then
  echo "[update] Fetching latest version from npm…" >&2
  REQUESTED_VERSION="$(npm view @anthropic-ai/claude-code version || true)"
  if [[ -z "$REQUESTED_VERSION" ]]; then
    echo "[update] Could not determine latest version from npm." >&2
    exit 1
  fi
fi

echo "[update] Installing Claude Code CLI v$REQUESTED_VERSION…" >&2
npm install -g "@anthropic-ai/claude-code@$REQUESTED_VERSION"

echo "[update] Installation complete. Current version:" >&2
claude --version
# update_claude_cli.sh
# Fetch and install the newest published version of the Claude Code CLI.
# Usage: ./scripts/update_claude_cli.sh [version]
# If no version is supplied the script installs the latest version available on npm.

set -euo pipefail

if [[ ${1-} == "--help" ]]; then
  echo "Usage: $0 [version]" >&2
  echo "Install a specific version (e.g. 1.1.0) or omit to install the latest." >&2
  exit 0
fi

REQUESTED_VERSION="${1-}"
# strip any Windows carriage returns that may break variable usage
REQUESTED_VERSION=${REQUESTED_VERSION//$'\r'/}

if [[ -z "$REQUESTED_VERSION" ]]; then
  echo "[update] Discovering latest version on npm…" >&2
  REQUESTED_VERSION=$(npm view @anthropic-ai/claude-code version)
fi

echo "[update] Installing Claude Code CLI v$REQUESTED_VERSION…" >&2
npm install -g "@anthropic-ai/claude-code@$REQUESTED_VERSION"

echo "[update] Installation complete. Current version:" >&2
claude --version
