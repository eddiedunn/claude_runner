#!/usr/bin/env bash
# test_hook_functionality.sh - Test PreToolUse hook script functionality

set -euo pipefail

# Source test framework
source "$(dirname "$0")/test_framework.sh"

test_hook_payload_parsing() {
    local test_name="hook_payload_parsing"
    test_start "$test_name"
    
    # Create test hook script
    cat > /tmp/test_hook_parse.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Read payload from stdin
read -r payload

# Extract session ID
SESSION_ID=$(echo "$payload" | jq -r '.session_id')

if [[ -z "$SESSION_ID" || "$SESSION_ID" == "null" ]]; then
  exit 1
fi

echo "SESSION_ID: $SESSION_ID"
exit 0
EOF
    
    chmod +x /tmp/test_hook_parse.sh
    
    # Test with valid payload
    local result=$(echo '{"session_id": "test-session-123"}' | /tmp/test_hook_parse.sh 2>&1)
    
    if assert_contains "$result" "SESSION_ID: test-session-123"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Failed to parse session ID from payload"
    fi
    
    rm -f /tmp/test_hook_parse.sh
}

test_hook_container_check() {
    local test_name="hook_container_check"
    test_start "$test_name"
    
    # Create test script that checks container status
    cat > /tmp/test_hook_container.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-claude-runner"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container not running" >&2
  exit 1
fi

echo "Container is running"
exit 0
EOF
    
    chmod +x /tmp/test_hook_container.sh
    
    # Test without container
    if ! /tmp/test_hook_container.sh >/dev/null 2>&1; then
        # Now start container and test again
        docker run -d --name test-claude-runner alpine tail -f /dev/null >/dev/null 2>&1
        
        if /tmp/test_hook_container.sh >/dev/null 2>&1; then
            test_pass "$test_name"
        else
            test_fail "$test_name" "Container detection not working"
        fi
        
        docker rm -f test-claude-runner >/dev/null 2>&1
    else
        test_fail "$test_name" "Should fail when container not running"
    fi
    
    rm -f /tmp/test_hook_container.sh
}

test_hook_auto_start_container() {
    local test_name="hook_auto_start_container"
    test_start "$test_name"
    
    # Create mock start script
    cat > /tmp/mock_start_runner.sh << 'EOF'
#!/usr/bin/env bash
docker run -d --name test-claude-runner alpine tail -f /dev/null
EOF
    chmod +x /tmp/mock_start_runner.sh
    
    # Create hook script that auto-starts container
    cat > /tmp/test_hook_autostart.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-claude-runner"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Starting container..." >&2
  /tmp/mock_start_runner.sh >&2
  sleep 1
  
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    exit 1
  fi
fi

echo "Container ready"
exit 0
EOF
    
    chmod +x /tmp/test_hook_autostart.sh
    
    # Ensure container is not running
    docker rm -f test-claude-runner >/dev/null 2>&1 || true
    
    # Test auto-start
    if /tmp/test_hook_autostart.sh >/dev/null 2>&1; then
        # Verify container was started
        if docker ps --format '{{.Names}}' | grep -q "test-claude-runner"; then
            test_pass "$test_name"
        else
            test_fail "$test_name" "Container not started"
        fi
    else
        test_fail "$test_name" "Auto-start failed"
    fi
    
    # Cleanup
    docker rm -f test-claude-runner >/dev/null 2>&1
    rm -f /tmp/test_hook_autostart.sh /tmp/mock_start_runner.sh
}

test_hook_auth_check() {
    local test_name="hook_auth_check"
    test_start "$test_name"
    
    # Start container with auth
    docker run -d \
        --name test-claude-runner \
        -v "$HOME/.claude-docker-test/claude.json:/home/node/.claude.json" \
        -v "$HOME/.claude-docker-test/container-claude-dir:/home/node/.claude" \
        alpine tail -f /dev/null >/dev/null 2>&1
    
    # Create hook script that checks auth
    cat > /tmp/test_hook_auth.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-claude-runner"

# Check credentials in container
if ! docker exec "$CONTAINER_NAME" test -f /home/node/.claude.json && \
   ! docker exec "$CONTAINER_NAME" test -d /home/node/.claude; then
  echo "No credentials found" >&2
  exit 1
fi

echo "Credentials verified"
exit 0
EOF
    
    chmod +x /tmp/test_hook_auth.sh
    
    # Test auth check
    if /tmp/test_hook_auth.sh >/dev/null 2>&1; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Auth verification failed"
    fi
    
    # Cleanup
    docker rm -f test-claude-runner >/dev/null 2>&1
    rm -f /tmp/test_hook_auth.sh
}

test_hook_exit_code() {
    local test_name="hook_exit_code"
    test_start "$test_name"
    
    # Create hook that exits with code 2 (blocks local execution)
    cat > /tmp/test_hook_exit.sh << 'EOF'
#!/usr/bin/env bash
echo "Blocking local execution" >&2
exit 2
EOF
    
    chmod +x /tmp/test_hook_exit.sh
    
    # Test exit code
    set +e
    /tmp/test_hook_exit.sh >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    if assert_equals "2" "$exit_code" "Exit code should be 2"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Wrong exit code: $exit_code"
    fi
    
    rm -f /tmp/test_hook_exit.sh
}

test_hook_workspace_mount() {
    local test_name="hook_workspace_mount"
    test_start "$test_name"
    
    # Create test workspace
    local test_workspace="/tmp/test-workspace"
    mkdir -p "$test_workspace"
    echo "test file" > "$test_workspace/test.txt"
    
    # Start container with workspace mount
    docker run -d \
        --name test-claude-runner \
        -v "$test_workspace:/workspace" \
        alpine tail -f /dev/null >/dev/null 2>&1
    
    # Verify workspace is accessible
    local file_content=$(docker exec test-claude-runner cat /workspace/test.txt 2>/dev/null || echo "")
    
    if assert_contains "$file_content" "test file"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Workspace not properly mounted"
    fi
    
    # Cleanup
    docker rm -f test-claude-runner >/dev/null 2>&1
    rm -rf "$test_workspace"
}

# Run all tests
echo "=== Hook Functionality Tests ==="
setup_test_env

test_hook_payload_parsing
test_hook_container_check
test_hook_auto_start_container
test_hook_auth_check
test_hook_exit_code
test_hook_workspace_mount

cleanup_test_env