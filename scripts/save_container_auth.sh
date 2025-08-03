#!/usr/bin/env bash
# save_container_auth.sh
# Saves authentication files from a running container

set -euo pipefail

CONTAINER_NAME="${1:-claude-runner}"
BACKUP_DIR="$HOME/.claude-docker"

echo "[save_container_auth] Saving authentication from container: $CONTAINER_NAME"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
  echo "[save_container_auth] ERROR: Container $CONTAINER_NAME is not running"
  exit 1
fi

# Try both root and node user locations
AUTH_PATH=""
if docker exec $CONTAINER_NAME test -f /home/node/.claude.json 2>/dev/null; then
  AUTH_PATH="/home/node"
elif docker exec $CONTAINER_NAME test -f /root/.claude.json 2>/dev/null; then
  AUTH_PATH="/root"
else
  echo "[save_container_auth] ERROR: No authentication found in container"
  echo "Please run 'claude' and '/login' in the container first"
  exit 1
fi

echo "[save_container_auth] Found auth files at: $AUTH_PATH"

# Copy authentication files
echo "[save_container_auth] Copying authentication files..."
docker cp "$CONTAINER_NAME:$AUTH_PATH/.claude.json" "$BACKUP_DIR/claude.json"
docker cp "$CONTAINER_NAME:$AUTH_PATH/.claude" "$BACKUP_DIR/container-claude-dir"

# Verify files were copied
if [[ -f "$BACKUP_DIR/claude.json" ]] && [[ -d "$BACKUP_DIR/container-claude-dir" ]]; then
  echo "[save_container_auth] ✅ Authentication saved successfully!"
  echo ""
  echo "Files saved to:"
  echo "  - $BACKUP_DIR/claude.json"
  echo "  - $BACKUP_DIR/container-claude-dir/"
  echo ""
  echo "You can now use ./scripts/start_persistent_runner.sh"
  echo "to start a new container with this authentication."
else
  echo "[save_container_auth] ❌ Failed to save authentication files"
  exit 1
fi