#!/usr/bin/env bash
# start_persistent_runner.sh
# Starts a Claude runner container with persistent authentication

set -euo pipefail

CONTAINER_NAME="claude-runner"
IMAGE_NAME="claude-runner-official:latest"
CLAUDE_DATA_DIR="$HOME/.claude-docker/container-claude-dir"

# Check if image exists
if ! docker images | grep -q "claude-runner-official"; then
  echo "[start_persistent_runner] Building official image..."
  docker build -f Dockerfile.official -t "$IMAGE_NAME" .
fi

# Check if we have saved authentication
if [[ -f "$HOME/.claude-docker/claude.json" ]] && [[ -d "$CLAUDE_DATA_DIR" ]]; then
  echo "[start_persistent_runner] Found saved authentication files!"
else
  echo "[start_persistent_runner] No saved authentication found."
  echo ""
  echo "To set up authentication:"
  echo "1. Start a container: docker run -it --name temp-auth $IMAGE_NAME bash"
  echo "2. Run: claude"
  echo "3. Complete: /login"
  echo "4. Save auth: ./scripts/save_container_auth.sh temp-auth"
  echo ""
  exit 1
fi

# Stop and remove existing container if it exists
if docker ps -a | grep -q "$CONTAINER_NAME"; then
  echo "[start_persistent_runner] Removing existing container..."
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Start new container with mounted authentication
echo "[start_persistent_runner] Starting container with persistent auth..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -v "$PWD:/workspace" \
  -v "$HOME/.claude-docker/claude.json:/home/node/.claude.json" \
  -v "$CLAUDE_DATA_DIR:/home/node/.claude" \
  -w /workspace \
  "$IMAGE_NAME" \
  tail -f /dev/null

echo ""
echo "[start_persistent_runner] Container started!"
echo ""
echo "To enter the container:"
echo "  docker exec -it $CONTAINER_NAME bash"
echo ""

# Fix permissions on mounted volumes
echo "Fixing permissions..."
docker exec $CONTAINER_NAME bash -c '
  chown -R node:node /home/node/.claude* 2>/dev/null || true
  chmod -R u+rw /home/node/.claude* 2>/dev/null || true
' >/dev/null 2>&1

# Test if authentication works
echo "Testing authentication..."
if docker exec -u node $CONTAINER_NAME bash -c "echo '' | claude 2>&1 | grep -q 'Invalid API key'"; then
  echo "❌ Authentication not working. You'll need to run /login"
else
  echo "✅ Authentication is working! Claude should use your Max/Pro subscription"
fi