#!/usr/bin/env bash
# build_claude_cli_from_source.sh
# Clone the Claude Code CLI repo, build it from source, and install it globally.
# This lets us test bleeding-edge commits before they are published to npm.
#
# Usage:
#   ./scripts/build_claude_cli_from_source.sh [git_ref]
#
# If no git_ref is supplied the script builds the current default branch (main).
# The repo is cloned/updated under .cache/claude-code to avoid polluting $PWD.

set -euo pipefail

REPO_URL="https://github.com/anthropics/claude-code.git"
CACHE_DIR="$(pwd)/.cache/claude-code"
GIT_REF="${1:-main}"

mkdir -p "$(pwd)/.cache"

if [[ -d "$CACHE_DIR/.git" ]]; then
  echo "[build] Updating existing clone at $CACHE_DIR …" >&2
  git -C "$CACHE_DIR" fetch --quiet
else
  echo "[build] Cloning Claude Code CLI repo …" >&2
  git clone --depth 1 "$REPO_URL" "$CACHE_DIR"
fi

echo "[build] Checking out $GIT_REF …" >&2
git -C "$CACHE_DIR" checkout --quiet "$GIT_REF"

echo "[build] Installing dependencies …" >&2
# The project uses npm; switch to pnpm/yarn if upstream changes.
cd "$CACHE_DIR"
npm install --silent

echo "[build] Building CLI …" >&2
npm run build --silent

# The CLI's package.json outputs compiled files to dist/ and supports npm link
echo "[build] Linking built CLI globally …" >&2
npm link

echo "[build] Done. Current version:"
claude --version
