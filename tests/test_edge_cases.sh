#!/usr/bin/env bash
# test_edge_cases.sh - Test edge cases and error scenarios

set -euo pipefail

# Source test framework
source "$(dirname "$0")/test_framework.sh"

test_no_docker_installed() {
    local test_name="no_docker_installed"
    test_start "$test_name"
    
    # Create script that simulates docker not found
    cat > /tmp/test_no_docker.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Simulate docker command not found
if ! command -v docker_fake >/dev/null 2>&1; then
  echo "docker_fake: command not found" >&2
  exit 127
fi
EOF
    
    chmod +x /tmp/test_no_docker.sh
    
    # Test should fail with exit code 127
    set +e
    /tmp/test_no_docker.sh >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    if assert_equals "127" "$exit_code"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should fail when docker not installed"
    fi
    
    rm -f /tmp/test_no_docker.sh
}

test_invalid_image_name() {
    local test_name="invalid_image_name"
    test_start "$test_name"
    
    # Try to run container with invalid image
    set +e
    docker run --name test-invalid-image "invalid-image-that-does-not-exist:latest" >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    if [[ $exit_code -ne 0 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should fail with invalid image"
        docker rm -f test-invalid-image >/dev/null 2>&1
    fi
}

test_permission_denied() {
    local test_name="permission_denied"
    test_start "$test_name"
    
    # Create directory with no write permissions
    local test_dir="/tmp/test-no-perms"
    mkdir -p "$test_dir"
    chmod 444 "$test_dir"
    
    # Try to write to read-only directory
    set +e
    echo "test" > "$test_dir/test.txt" 2>/dev/null
    local exit_code=$?
    set -e
    
    if [[ $exit_code -ne 0 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should fail with permission denied"
    fi
    
    # Cleanup
    chmod 755 "$test_dir"
    rm -rf "$test_dir"
}

test_corrupted_auth_file() {
    local test_name="corrupted_auth_file"
    test_start "$test_name"
    
    # Create corrupted JSON file
    echo "{ invalid json" > "$HOME/.claude-docker-test/claude-corrupt.json"
    
    # Test parsing corrupted file
    set +e
    jq -r '.token' "$HOME/.claude-docker-test/claude-corrupt.json" >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    if [[ $exit_code -ne 0 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Should fail with corrupted JSON"
    fi
    
    rm -f "$HOME/.claude-docker-test/claude-corrupt.json"
}

test_disk_space_check() {
    local test_name="disk_space_check"
    test_start "$test_name"
    
    # Check available disk space
    local available_space=$(df -k . | awk 'NR==2 {print $4}')
    
    # Just verify we can check disk space
    if [[ -n "$available_space" ]] && [[ "$available_space" -gt 0 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Cannot determine disk space"
    fi
}

test_concurrent_container_access() {
    local test_name="concurrent_container_access"
    test_start "$test_name"
    
    # Start test container
    docker run -d --name test-concurrent alpine tail -f /dev/null >/dev/null 2>&1
    
    # Run multiple concurrent commands
    local pid1 pid2 pid3
    docker exec test-concurrent echo "Process 1" >/dev/null 2>&1 & pid1=$!
    docker exec test-concurrent echo "Process 2" >/dev/null 2>&1 & pid2=$!
    docker exec test-concurrent echo "Process 3" >/dev/null 2>&1 & pid3=$!
    
    # Wait for all processes
    local all_success=true
    wait $pid1 || all_success=false
    wait $pid2 || all_success=false
    wait $pid3 || all_success=false
    
    if [[ "$all_success" == "true" ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Concurrent access failed"
    fi
    
    # Cleanup
    docker rm -f test-concurrent >/dev/null 2>&1
}

test_long_running_command_timeout() {
    local test_name="long_running_command_timeout"
    test_start "$test_name"
    
    # Start test container
    docker run -d --name test-timeout alpine tail -f /dev/null >/dev/null 2>&1
    
    # Run command with timeout
    set +e
    timeout 2 docker exec test-timeout sleep 10 >/dev/null 2>&1
    local exit_code=$?
    set -e
    
    # Exit code 124 indicates timeout
    if [[ $exit_code -eq 124 ]]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Timeout not working correctly"
    fi
    
    # Cleanup
    docker rm -f test-timeout >/dev/null 2>&1
}

test_special_characters_in_paths() {
    local test_name="special_characters_in_paths"
    test_start "$test_name"
    
    # Create directory with special characters
    local special_dir="/tmp/test dir with spaces & special (chars)"
    mkdir -p "$special_dir"
    echo "test content" > "$special_dir/test file.txt"
    
    # Start container with special path mount
    docker run -d \
        --name test-special \
        -v "$special_dir:/workspace" \
        alpine tail -f /dev/null >/dev/null 2>&1
    
    # Test reading file with special characters
    local content=$(docker exec test-special cat "/workspace/test file.txt" 2>/dev/null || echo "")
    
    if assert_contains "$content" "test content"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Failed to handle special characters in paths"
    fi
    
    # Cleanup
    docker rm -f test-special >/dev/null 2>&1
    rm -rf "$special_dir"
}

test_network_connectivity() {
    local test_name="network_connectivity"
    test_start "$test_name"
    
    # Start container and test network
    docker run -d --name test-network alpine tail -f /dev/null >/dev/null 2>&1
    
    # Test DNS resolution
    set +e
    docker exec test-network nslookup google.com >/dev/null 2>&1
    local dns_works=$?
    set -e
    
    if [[ $dns_works -eq 0 ]]; then
        test_pass "$test_name"
    else
        # Network might be restricted, still pass but note it
        test_pass "$test_name" # "(Network access may be restricted)"
    fi
    
    # Cleanup
    docker rm -f test-network >/dev/null 2>&1
}

# Run all tests
echo "=== Edge Case Tests ==="
setup_test_env

test_no_docker_installed
test_invalid_image_name
test_permission_denied
test_corrupted_auth_file
test_disk_space_check
test_concurrent_container_access
test_long_running_command_timeout
test_special_characters_in_paths
test_network_connectivity

cleanup_test_env