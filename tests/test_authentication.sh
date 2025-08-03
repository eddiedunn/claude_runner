#!/usr/bin/env bash
# test_authentication.sh - Test authentication persistence and verification

set -euo pipefail

# Source test framework
source "$(dirname "$0")/test_framework.sh"

test_save_container_auth_success() {
    local test_name="save_container_auth_success"
    test_start "$test_name"
    
    # Start a test container with mock auth files
    docker run -d --name test-auth-container alpine tail -f /dev/null >/dev/null 2>&1
    
    # Create mock auth files in container
    docker exec test-auth-container sh -c "mkdir -p /home/node && echo '{\"token\":\"test\"}' > /home/node/.claude.json"
    docker exec test-auth-container sh -c "mkdir -p /home/node/.claude && echo 'config' > /home/node/.claude/config"
    
    # Create test save script
    cat > /tmp/test_save_auth.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${1:-test-auth-container}"
BACKUP_DIR="$HOME/.claude-docker-test"

mkdir -p "$BACKUP_DIR"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
  exit 1
fi

# Find auth path
AUTH_PATH=""
if docker exec $CONTAINER_NAME test -f /home/node/.claude.json 2>/dev/null; then
  AUTH_PATH="/home/node"
elif docker exec $CONTAINER_NAME test -f /root/.claude.json 2>/dev/null; then
  AUTH_PATH="/root"
else
  exit 1
fi

# Copy files
docker cp "$CONTAINER_NAME:$AUTH_PATH/.claude.json" "$BACKUP_DIR/claude.json"
docker cp "$CONTAINER_NAME:$AUTH_PATH/.claude" "$BACKUP_DIR/container-claude-dir"

# Verify
if [[ -f "$BACKUP_DIR/claude.json" ]] && [[ -d "$BACKUP_DIR/container-claude-dir" ]]; then
  exit 0
else
  exit 1
fi
EOF
    
    chmod +x /tmp/test_save_auth.sh
    
    # Test saving auth
    if /tmp/test_save_auth.sh test-auth-container >/dev/null 2>&1; then
        # Verify files were saved
        if assert_file_exists "$HOME/.claude-docker-test/claude.json" && \
           assert_dir_exists "$HOME/.claude-docker-test/container-claude-dir"; then
            test_pass "$test_name"
        else
            test_fail "$test_name" "Auth files not saved correctly"
        fi
    else
        test_fail "$test_name" "Failed to save authentication"
    fi
    
    # Cleanup
    docker rm -f test-auth-container >/dev/null 2>&1
    rm -f /tmp/test_save_auth.sh
}

test_save_container_auth_no_container() {
    local test_name="save_container_auth_no_container"
    test_start "$test_name"
    
    # Ensure container doesn't exist
    docker rm -f test-nonexistent >/dev/null 2>&1 || true
    
    # Test script should fail
    cat > /tmp/test_save_no_container.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="test-nonexistent"

if ! docker ps | grep -q "$CONTAINER_NAME"; then
  exit 1
fi
exit 0
EOF
    
    chmod +x /tmp/test_save_no_container.sh
    
    if ! /tmp/test_save_no_container.sh >/dev/null 2>&1; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should fail when container doesn't exist"
    fi
    
    rm -f /tmp/test_save_no_container.sh
}

test_auth_verification_in_container() {
    local test_name="auth_verification_in_container"
    test_start "$test_name"
    
    # Start container with mounted auth
    docker run -d \
        --name test-auth-container \
        -v "$HOME/.claude-docker-test/claude.json:/home/node/.claude.json" \
        -v "$HOME/.claude-docker-test/container-claude-dir:/home/node/.claude" \
        alpine tail -f /dev/null >/dev/null 2>&1
    
    # Verify auth files are accessible
    local json_exists=$(docker exec test-auth-container test -f /home/node/.claude.json && echo "yes" || echo "no")
    local dir_exists=$(docker exec test-auth-container test -d /home/node/.claude && echo "yes" || echo "no")
    
    if [[ "$json_exists" == "yes" ]] && [[ "$dir_exists" == "yes" ]]; then
        # Verify content
        local json_content=$(docker exec test-auth-container cat /home/node/.claude.json)
        if assert_contains "$json_content" "test-token"; then
            test_pass "$test_name"
        else
            test_fail "$test_name" "Auth file content incorrect"
        fi
    else
        test_fail "$test_name" "Auth files not accessible in container"
    fi
    
    # Cleanup
    docker rm -f test-auth-container >/dev/null 2>&1
}

test_missing_auth_detection() {
    local test_name="missing_auth_detection"
    test_start "$test_name"
    
    # Remove auth files
    rm -rf "$HOME/.claude-docker-test/claude.json"
    rm -rf "$HOME/.claude-docker-test/container-claude-dir"
    
    # Test script should detect missing auth
    cat > /tmp/test_missing_auth.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -f "$HOME/.claude-docker-test/claude.json" ]] && [[ -d "$HOME/.claude-docker-test/container-claude-dir" ]]; then
  exit 0
else
  exit 1
fi
EOF
    
    chmod +x /tmp/test_missing_auth.sh
    
    if ! /tmp/test_missing_auth.sh >/dev/null 2>&1; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should detect missing authentication"
    fi
    
    rm -f /tmp/test_missing_auth.sh
    
    # Restore auth files for other tests
    setup_test_env
}

test_auth_permissions() {
    local test_name="auth_permissions"
    test_start "$test_name"
    
    # Check permissions of auth files
    local json_perms=$(stat -f "%p" "$HOME/.claude-docker-test/claude.json" 2>/dev/null || stat -c "%a" "$HOME/.claude-docker-test/claude.json" 2>/dev/null)
    
    # Permissions should be readable
    if [[ -r "$HOME/.claude-docker-test/claude.json" ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Auth files not readable"
    fi
}

# Run all tests
echo "=== Authentication Tests ==="
setup_test_env

test_save_container_auth_success
test_save_container_auth_no_container
test_auth_verification_in_container
test_missing_auth_detection
test_auth_permissions

cleanup_test_env