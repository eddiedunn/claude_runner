#!/usr/bin/env bash
# test_container_lifecycle.sh - Test container lifecycle management

set -euo pipefail

# Source test framework
source "$(dirname "$0")/test_framework.sh"

# Test container lifecycle
test_container_start_stop() {
    local test_name="container_start_stop"
    test_start "$test_name"
    
    # Create a modified version of start_persistent_runner for testing
    cat > /tmp/test_start_runner.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-claude-runner"
IMAGE_NAME="claude-runner-official:latest"
CLAUDE_DATA_DIR="$HOME/.claude-docker-test/container-claude-dir"

# Check if image exists, if not use a simple alpine image for testing
if ! docker images | grep -q "claude-runner-official"; then
  docker pull alpine:latest >/dev/null 2>&1
  docker tag alpine:latest "$IMAGE_NAME"
fi

# Check authentication
if [[ -f "$HOME/.claude-docker-test/claude.json" ]] && [[ -d "$CLAUDE_DATA_DIR" ]]; then
  echo "[test] Found saved authentication files!"
else
  echo "[test] No saved authentication found."
  exit 1
fi

# Stop and remove existing container
if docker ps -a | grep -q "$CONTAINER_NAME"; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Start container
docker run -d \
  --name "$CONTAINER_NAME" \
  -v "$PWD:/workspace" \
  -v "$HOME/.claude-docker-test/claude.json:/home/node/.claude.json" \
  -v "$CLAUDE_DATA_DIR:/home/node/.claude" \
  -w /workspace \
  "$IMAGE_NAME" \
  tail -f /dev/null
EOF
    
    chmod +x /tmp/test_start_runner.sh
    
    # Test starting container
    if /tmp/test_start_runner.sh >/dev/null 2>&1; then
        # Verify container is running
        if docker ps --format '{{.Names}}' | grep -q "test-claude-runner"; then
            test_pass "$test_name"
            
            # Cleanup
            docker rm -f test-claude-runner >/dev/null 2>&1
        else
            test_fail "$test_name" "Container not running after start"
        fi
    else
        test_fail "$test_name" "Failed to start container"
    fi
    
    rm -f /tmp/test_start_runner.sh
}

test_container_already_exists() {
    local test_name="container_already_exists"
    test_start "$test_name"
    
    # Start a test container
    docker run -d --name test-claude-runner alpine tail -f /dev/null >/dev/null 2>&1
    
    # Create test script that handles existing container
    cat > /tmp/test_existing_container.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-claude-runner"

# Check if container exists
if docker ps -a | grep -q "$CONTAINER_NAME"; then
  echo "Removing existing container..."
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Start new container
docker run -d --name "$CONTAINER_NAME" alpine tail -f /dev/null
EOF
    
    chmod +x /tmp/test_existing_container.sh
    
    # Test handling existing container
    if /tmp/test_existing_container.sh >/dev/null 2>&1; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Failed to handle existing container"
    fi
    
    # Cleanup
    docker rm -f test-claude-runner >/dev/null 2>&1
    rm -f /tmp/test_existing_container.sh
}

test_container_not_running() {
    local test_name="container_not_running_detection"
    test_start "$test_name"
    
    # Ensure no test container is running
    docker rm -f test-claude-runner >/dev/null 2>&1 || true
    
    # Check if detection works
    if docker ps --format '{{.Names}}' | grep -q "^test-claude-runner$"; then
        test_fail "$test_name" "Container should not be running"
    else
        test_pass "$test_name"
    fi
}

test_container_volume_mounts() {
    local test_name="container_volume_mounts"
    test_start "$test_name"
    
    # Start container with volume mounts
    docker run -d \
        --name test-claude-runner \
        -v "$PWD:/workspace" \
        -v "$HOME/.claude-docker-test/claude.json:/home/node/.claude.json" \
        -v "$HOME/.claude-docker-test/container-claude-dir:/home/node/.claude" \
        alpine tail -f /dev/null >/dev/null 2>&1
    
    # Test workspace mount
    local workspace_mounted=$(docker exec test-claude-runner test -d /workspace && echo "yes" || echo "no")
    
    # Test auth file mount
    local auth_mounted=$(docker exec test-claude-runner test -f /home/node/.claude.json && echo "yes" || echo "no")
    
    # Test auth dir mount
    local auth_dir_mounted=$(docker exec test-claude-runner test -d /home/node/.claude && echo "yes" || echo "no")
    
    if [[ "$workspace_mounted" == "yes" ]] && \
       [[ "$auth_mounted" == "yes" ]] && \
       [[ "$auth_dir_mounted" == "yes" ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Volume mounts not working correctly"
    fi
    
    # Cleanup
    docker rm -f test-claude-runner >/dev/null 2>&1
}

# Run all tests
echo "=== Container Lifecycle Tests ==="
setup_test_env

test_container_start_stop
test_container_already_exists
test_container_not_running
test_container_volume_mounts

cleanup_test_env