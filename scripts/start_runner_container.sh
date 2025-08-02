#!/usr/bin/env bash
# start_runner_container.sh
# Launches a persistent Claude runner container with workspace and credentials mounted.
# Usage: ./scripts/start_runner_container.sh

set -euo pipefail

# Name for the container so you can exec into it later
CONTAINER_NAME="claude-runner"

# Start the container in detached mode if not already running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
  docker run -d \
    --name "$CONTAINER_NAME" \
    -e USE_CLAUDE_CREDENTIALS=true \
    -v "$HOME/.claude:/home/node/.claude:ro" \
    -v "$PWD":/workspace \
    -w /workspace \
    claude-runner:latest tail -f /dev/null
  echo "[start_runner_container] Started container $CONTAINER_NAME."
else
  echo "[start_runner_container] Container $CONTAINER_NAME is already running."
fi

# Print instruction to exec into the container
echo "To enter the container shell, run:"
echo "  docker exec -it $CONTAINER_NAME bash"
