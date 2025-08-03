#!/usr/bin/env bash
# test_framework.sh - Test framework for Claude Runner

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result storage
declare -A TEST_RESULTS
declare -A TEST_ERRORS

# Test framework functions
test_start() {
    local test_name="$1"
    echo -e "${YELLOW}Running test: $test_name${NC}"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASSED: $test_name${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TEST_RESULTS["$test_name"]="PASSED"
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    echo -e "${RED}✗ FAILED: $test_name${NC}"
    echo -e "${RED}  Error: $error_msg${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TEST_RESULTS["$test_name"]="FAILED"
    TEST_ERRORS["$test_name"]="$error_msg"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values not equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        echo "Expected: '$expected', Actual: '$actual'"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String not found}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "$message: '$needle' not found in output"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File not found}"
    
    if [[ ! -f "$file" ]]; then
        echo "$message: $file"
        return 1
    fi
    return 0
}

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory not found}"
    
    if [[ ! -d "$dir" ]]; then
        echo "$message: $dir"
        return 1
    fi
    return 0
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command failed}"
    
    if ! eval "$command" >/dev/null 2>&1; then
        echo "$message: $command"
        return 1
    fi
    return 0
}

assert_command_fails() {
    local command="$1"
    local message="${2:-Command should have failed}"
    
    if eval "$command" >/dev/null 2>&1; then
        echo "$message: $command"
        return 1
    fi
    return 0
}

# Cleanup function
cleanup_test_env() {
    # Remove test containers
    docker rm -f test-claude-runner >/dev/null 2>&1 || true
    docker rm -f test-auth-container >/dev/null 2>&1 || true
    
    # Remove test auth directory
    rm -rf "$HOME/.claude-docker-test" 2>/dev/null || true
}

# Setup test environment
setup_test_env() {
    cleanup_test_env
    
    # Create test auth directory
    mkdir -p "$HOME/.claude-docker-test"
    
    # Create mock auth files
    echo '{"token": "test-token"}' > "$HOME/.claude-docker-test/claude.json"
    mkdir -p "$HOME/.claude-docker-test/container-claude-dir"
    echo "test-config" > "$HOME/.claude-docker-test/container-claude-dir/config"
}

# Summary function
print_summary() {
    echo ""
    echo "================================"
    echo "TEST SUMMARY"
    echo "================================"
    echo "Total tests run: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "Failed tests:"
        for test_name in "${!TEST_RESULTS[@]}"; do
            if [[ "${TEST_RESULTS[$test_name]}" == "FAILED" ]]; then
                echo -e "${RED}  - $test_name${NC}"
                if [[ -n "${TEST_ERRORS[$test_name]:-}" ]]; then
                    echo "    Error: ${TEST_ERRORS[$test_name]}"
                fi
            fi
        done
    fi
    
    echo "================================"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Export all functions
export -f test_start test_pass test_fail
export -f assert_equals assert_contains assert_file_exists assert_dir_exists
export -f assert_command_succeeds assert_command_fails
export -f cleanup_test_env setup_test_env print_summary