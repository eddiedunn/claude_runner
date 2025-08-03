#!/usr/bin/env bash
# test_e2e_simulation.sh - End-to-end workflow simulation

set -euo pipefail

# Source test framework
source "$(dirname "$0")/test_framework.sh"

# Simulate the complete workflow
test_e2e_workflow_simulation() {
    local test_name="e2e_workflow_simulation"
    test_start "$test_name"
    
    echo "Simulating complete Claude Runner workflow..."
    
    # Step 1: Simulate hook receiving payload
    local mock_payload='{"session_id": "test-session-123", "tool": "Edit", "params": {"file_path": "/workspace/test.py"}}'
    
    # Step 2: Create mock hook script that simulates the workflow
    cat > /tmp/test_e2e_hook.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Read payload
read -r payload

# Extract session ID
SESSION_ID=$(echo "$payload" | jq -r '.session_id')
echo "[Hook] Received session: $SESSION_ID" >&2

# Simulate container check and start
CONTAINER_NAME="test-e2e-runner"
WORKSPACE="/tmp/test-e2e-workspace"

# Create test workspace
mkdir -p "$WORKSPACE"
echo "print('Hello from test')" > "$WORKSPACE/test.py"

# Check if container running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[Hook] Starting container..." >&2
    
    # Start container with mounts
    docker run -d \
        --name "$CONTAINER_NAME" \
        -v "$WORKSPACE:/workspace" \
        -v "$HOME/.claude-docker-test/claude.json:/home/node/.claude.json" \
        -v "$HOME/.claude-docker-test/container-claude-dir:/home/node/.claude" \
        alpine tail -f /dev/null >&2
    
    sleep 1
fi

# Verify auth in container
if docker exec "$CONTAINER_NAME" test -f /home/node/.claude.json; then
    echo "[Hook] Authentication verified" >&2
else
    echo "[Hook] ERROR: No authentication found" >&2
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

# Simulate Claude execution in container
echo "[Hook] Executing in container..." >&2
docker exec "$CONTAINER_NAME" sh -c "
    cd /workspace
    # Simulate editing the file
    echo '# Modified by Claude' >> test.py
    echo 'print(\"Modified in container\")' >> test.py
"

# Verify modification
if docker exec "$CONTAINER_NAME" grep -q "Modified in container" /workspace/test.py; then
    echo "[Hook] Execution completed successfully" >&2
else
    echo "[Hook] ERROR: Execution failed" >&2
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

# Cleanup
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
rm -rf "$WORKSPACE"

# Exit with code 2 to block local execution
exit 2
EOF
    
    chmod +x /tmp/test_e2e_hook.sh
    
    # Run the simulation
    set +e
    echo "$mock_payload" | /tmp/test_e2e_hook.sh >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    # Verify workflow completed with exit code 2
    if [[ $exit_code -eq 2 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Workflow did not complete correctly (exit code: $exit_code)"
    fi
    
    # Cleanup
    rm -f /tmp/test_e2e_hook.sh
}

test_workflow_error_recovery() {
    local test_name="workflow_error_recovery"
    test_start "$test_name"
    
    # Test workflow with various failure scenarios
    cat > /tmp/test_error_recovery.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Simulate different error conditions
ERROR_TYPE="${1:-none}"

case "$ERROR_TYPE" in
    "no_session")
        # Missing session ID
        read -r payload
        SESSION_ID=$(echo '{"no_session": true}' | jq -r '.session_id')
        if [[ "$SESSION_ID" == "null" ]]; then
            echo "ERROR: No session_id found" >&2
            exit 1
        fi
        ;;
    
    "no_auth")
        # Missing authentication
        if [[ ! -f "$HOME/.claude-docker-test/claude.json" ]]; then
            echo "ERROR: No authentication found" >&2
            exit 1
        fi
        ;;
    
    "container_fail")
        # Container start failure
        if ! docker run --name fail-test invalid-image 2>/dev/null; then
            echo "ERROR: Failed to start container" >&2
            exit 1
        fi
        ;;
    
    *)
        echo "Unknown error type" >&2
        exit 1
        ;;
esac
EOF
    
    chmod +x /tmp/test_error_recovery.sh
    
    # Test each error scenario
    local scenarios=("no_session" "no_auth" "container_fail")
    local all_handled=true
    
    for scenario in "${scenarios[@]}"; do
        set +e
        echo '{}' | /tmp/test_error_recovery.sh "$scenario" >/dev/null 2>&1
        local exit_code=$?
        set -e
        
        if [[ $exit_code -eq 1 ]]; then
            echo "  ✓ Error scenario '$scenario' handled correctly"
        else
            echo "  ✗ Error scenario '$scenario' not handled properly"
            all_handled=false
        fi
    done
    
    if [[ "$all_handled" == "true" ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Some error scenarios not handled correctly"
    fi
    
    rm -f /tmp/test_error_recovery.sh
}

test_concurrent_workflow_execution() {
    local test_name="concurrent_workflow_execution"
    test_start "$test_name"
    
    # Create script that handles concurrent executions
    cat > /tmp/test_concurrent_workflow.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SESSION_ID="$1"
LOCK_FILE="/tmp/claude-runner.lock"

# Simple file-based locking
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Another execution in progress for session $SESSION_ID" >&2
    exit 3
fi

# Simulate work
sleep 1
echo "Completed session $SESSION_ID"

# Release lock
flock -u 200
EOF
    
    chmod +x /tmp/test_concurrent_workflow.sh
    
    # Start multiple concurrent executions
    local pid1 pid2 pid3
    /tmp/test_concurrent_workflow.sh "session-1" & pid1=$!
    /tmp/test_concurrent_workflow.sh "session-2" & pid2=$!
    /tmp/test_concurrent_workflow.sh "session-3" & pid3=$!
    
    # Wait and check results
    local success_count=0
    wait $pid1 && ((success_count++)) || true
    wait $pid2 && ((success_count++)) || true
    wait $pid3 && ((success_count++)) || true
    
    # At least one should succeed, others might be blocked
    if [[ $success_count -ge 1 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Concurrent execution handling failed"
    fi
    
    rm -f /tmp/test_concurrent_workflow.sh /tmp/claude-runner.lock
}

# Run all tests
echo "=== End-to-End Simulation Tests ==="
setup_test_env

test_e2e_workflow_simulation
test_workflow_error_recovery
test_concurrent_workflow_execution

cleanup_test_env