#!/bin/bash

# Test script for safe_run.sh

# Path to the safe_run.sh script
SAFE_RUN_SCRIPT="./safety.sh"

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo "[PASS] $2"
    else
        echo "[FAIL] $2"
        exit 1
    fi
}

# Function to simulate running as root (requires sudo)
run_as_root() {
    sudo bash -c "$1"
}

# Test 1: Evaluate a safe command without execution
test_safe_command_evaluation() {
    OUTPUT=$($SAFE_RUN_SCRIPT ls -la)
    echo "$OUTPUT" | grep -q "Command evaluation complete. Use --run to execute the command."
    print_result $? "Test 1: Safe command evaluation without execution"
}

# Test 2: Execute a safe command with --run
test_safe_command_execution() {
    OUTPUT=$($SAFE_RUN_SCRIPT --run echo "Test safe command execution")
    echo "$OUTPUT" | grep -q "Test safe command execution"
    print_result $? "Test 2: Safe command execution with --run"
}

# Test 3: Evaluate an unsafe command without execution
test_unsafe_command_evaluation() {
    OUTPUT=$($SAFE_RUN_SCRIPT rm -rf / 2>&1)
    echo "$OUTPUT" | grep -q "Unsafe command detected"
    print_result $? "Test 3: Unsafe command evaluation without execution"
}

# Test 4: Attempt to execute an unsafe command without --force
test_unsafe_command_execution_without_force() {
    OUTPUT=$($SAFE_RUN_SCRIPT --run rm -rf / 2>&1)
    echo "$OUTPUT" | grep -q "Use --force and --run to execute the command anyway."
    print_result $? "Test 4: Unsafe command execution attempt without --force"
}

# Test 5: Execute an unsafe command with --force and --run
test_unsafe_command_execution_with_force() {
    OUTPUT=$($SAFE_RUN_SCRIPT --force --run echo "Unsafe command test")
    echo "$OUTPUT" | grep -q "Unsafe command test"
    print_result $? "Test 5: Unsafe command execution with --force and --run"
}

# Test 6: Running a command inside Docker without execution
test_docker_command_evaluation() {
    OUTPUT=$($SAFE_RUN_SCRIPT --docker ubuntu:20.04 ls -la)
    echo "$OUTPUT" | grep -q "Command evaluation complete. Use --run to execute the command."
    print_result $? "Test 6: Docker command evaluation without execution"
}

# Test 7: Running a command inside Docker with --run
test_docker_command_execution() {
    OUTPUT=$($SAFE_RUN_SCRIPT --docker ubuntu:20.04 --run echo "Hello from Docker")
    echo "$OUTPUT" | grep -q "Hello from Docker"
    print_result $? "Test 7: Docker command execution with --run"
}

# Test 8: Generating a Kubernetes manifest without execution
test_kubernetes_manifest_generation() {
    OUTPUT=$($SAFE_RUN_SCRIPT --kubernetes alpine echo "Hello from Kubernetes")
    echo "$OUTPUT" | grep -q "Command evaluation complete. Use --run to execute the command."
    print_result $? "Test 8: Kubernetes manifest generation without execution"
}

# Test 9: Generating and applying a Kubernetes manifest with --run and --apply
test_kubernetes_manifest_application() {
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo "[SKIP] Test 9: kubectl not installed. Skipping Kubernetes manifest application test."
        return
    fi
    # Check if Kubernetes cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        echo "[SKIP] Test 9: Kubernetes cluster not accessible. Skipping Kubernetes manifest application test."
        return
    fi
    OUTPUT=$($SAFE_RUN_SCRIPT --kubernetes ubuntu:20.04 --apply --run echo "Hello from Kubernetes" 2>&1)
    echo "$OUTPUT" | grep -q "Applying Kubernetes manifest"
    print_result $? "Test 9: Kubernetes manifest application with --run and --apply"
    # Clean up the pod
    kubectl delete pod command-test --ignore-not-found
}

# Test 10: Displaying help message
test_help_option() {
    OUTPUT=$($SAFE_RUN_SCRIPT --help)
    echo "$OUTPUT" | grep -q "Usage: $SAFE_RUN_SCRIPT \[OPTIONS\] COMMAND"
    print_result $? "Test 10: Displaying help message"
}

# Test 11: Root user warning without --force
test_root_user_warning() {
    OUTPUT=$(sudo $SAFE_RUN_SCRIPT ls -la 2>&1)
    echo "$OUTPUT" | grep -q "Warning: Running this script as root is not recommended."
    print_result $? "Test 11: Root user warning without --force"
}

# Test 12: Root user execution with --force
test_root_user_execution_with_force() {
    OUTPUT=$(sudo $SAFE_RUN_SCRIPT --force --run echo "Running as root" 2>&1)
    echo "$OUTPUT" | grep -q "Running as root"
    print_result $? "Test 12: Root user execution with --force"
}

# Run all tests
test_safe_command_evaluation
test_safe_command_execution
test_unsafe_command_evaluation
test_unsafe_command_execution_without_force
test_unsafe_command_execution_with_force
test_docker_command_evaluation
test_docker_command_execution
test_kubernetes_manifest_generation
test_kubernetes_manifest_application
test_help_option
test_root_user_warning
test_root_user_execution_with_force

echo "All tests passed successfully!"
