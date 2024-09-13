#!/bin/bash

# Default behavior
FORCE_EXECUTION=false
DOCKER_EXECUTION=false
DOCKER_IMAGE="ubuntu:latest"
KUBERNETES_EXECUTION=false
KUBERNETES_IMAGE="ubuntu:latest"

# Function to display usage help
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Options:"
    echo "  --force                  Force execution of unsafe commands and override root user check."
    echo "  --docker [IMAGE_NAME]    Run the command inside a Docker container."
    echo "                           If IMAGE_NAME is not specified, defaults to ubuntu:latest."
    echo "  --kubernetes [IMAGE_NAME] Create and optionally apply a Kubernetes manifest to run the command."
    echo "                           If IMAGE_NAME is not specified, defaults to ubuntu:latest."
    echo "  --apply                  When used with --kubernetes, applies the manifest using kubectl."
    echo "  --help                   Display this help message."
    echo ""
    echo "Examples:"
    echo "  $0 ls -la"
    echo "  $0 --docker ubuntu:20.04 ls -la"
    echo "  $0 --force rm -rf /important/data"
    echo "  $0 --docker --force rm -rf /"
    echo "  $0 --kubernetes alpine ls -la"
    echo "  $0 --kubernetes ubuntu:20.04 --apply ls -la"
    exit 1
}

# Function to check if Docker is running
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not found in PATH."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running."
        exit 1
    fi
}

# Function to check if kubectl is installed and configured
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not found in PATH."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo "Error: kubectl is not configured or cannot connect to the cluster."
        exit 1
    fi
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -eq 0 ] && [ "$FORCE_EXECUTION" = false ]; then
        echo "Warning: Running this script as root is not recommended."
        echo "Use --force to override this check and proceed as root."
        exit 1
    fi
}

# Check if no arguments are provided or if --help is used
if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
    usage
fi

# Parse options
APPLY_MANIFEST=false
while [[ "$1" == --* ]]; do
    case "$1" in
        --force)
            FORCE_EXECUTION=true
            shift
            ;;
        --docker)
            DOCKER_EXECUTION=true
            shift
            if [[ "$1" != --* ]] && [[ -n "$1" ]]; then
                DOCKER_IMAGE="$1"
                shift
            fi
            ;;
        --kubernetes)
            KUBERNETES_EXECUTION=true
            shift
            if [[ "$1" != --* ]] && [[ -n "$1" ]]; then
                KUBERNETES_IMAGE="$1"
                shift
            fi
            ;;
        --apply)
            APPLY_MANIFEST=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if command is provided
if [ -z "$1" ]; then
    echo "Error: No command provided."
    usage
fi

# Get the command to evaluate
COMMAND="$@"

# Define a list of unsafe patterns
UNSAFE_PATTERNS=(
    "rm -rf"
    "mkfs.*"
    "dd if="
    "shutdown"
    "reboot"
    "sudo"
    "su"
    ":(){ :|:& };:"        # Fork bomb
    "wget http://"
    "curl http://"
    "zfs destroy"
    "zfs snapshot"
    "zfs clone"
    "zfs promote"
    "zfs rollback"
    "zfs rename"
    "zfs send"
    "zfs receive"
    "zpool destroy"
    "zpool labelclear"
    "zpool replace"
    "zpool offline"
    "zpool online"
    "zpool clear"
    "zpool import"
    "zpool export"
)

# Define command categories
declare -A COMMAND_CATEGORIES
COMMAND_CATEGORIES=(
    ["Filesystem Commands"]="rm|mkdir|touch|cp|mv|ln|ls|chmod|chown|df|du|mkfs.*|mount|umount|fsck|zfs|zpool"
    ["Network Commands"]="ping|curl|wget|netstat|ifconfig|ip|traceroute|ssh|telnet|ftp|scp"
    ["System Commands"]="shutdown|reboot|systemctl|service|ps|top|kill|killall|sudo|su"
    ["Process Commands"]="ps|top|htop|kill|killall|nice|renice|pgrep|pkill"
    ["Disk Commands"]="fdisk|dd|parted|mkfs.*|df|du|mount|umount|fsck"
    ["Package Management"]="apt|yum|dnf|pacman|brew|pip|gem|npm"
    ["User Management"]="useradd|userdel|usermod|passwd|groupadd|groupdel|groupmod|chown|chmod"
    ["Compression Commands"]="tar|gzip|gunzip|zip|unzip|bzip2|bunzip2"
    ["Text Processing"]="cat|more|less|head|tail|grep|awk|sed|sort|uniq|wc|cut|paste"
)

# Function to classify the command
classify_command() {
    if [ "$KUBERNETES_EXECUTION" = true ]; then
        echo "Kubernetes Command"
        return
    fi

    local cmd=$(echo "$COMMAND" | awk '{print $1}')
    for category in "${!COMMAND_CATEGORIES[@]}"; do
        if [[ "$cmd" =~ ^(${COMMAND_CATEGORIES[$category]})$ ]]; then
            echo "$category"
            return
        fi
    done
    echo "Unknown Command Type"
}

# Function to check if the command is safe
is_safe() {
    for pattern in "${UNSAFE_PATTERNS[@]}"; do
        if [[ "$COMMAND" =~ $pattern ]]; then
            echo "Unsafe command detected: $pattern"
            return 1
        fi
    done
    return 0
}

# Check if running as root
check_root

# Classify the command
COMMAND_TYPE=$(classify_command)

# Check if Docker is needed and running
if [ "$DOCKER_EXECUTION" = true ]; then
    check_docker
fi

# Check if Kubernetes is needed and configured
if [ "$KUBERNETES_EXECUTION" = true ] && [ "$APPLY_MANIFEST" = true ]; then
    check_kubectl
fi

# Check if the command is safe
if is_safe; then
    echo "Command Type: $COMMAND_TYPE"
    if [ "$DOCKER_EXECUTION" = true ]; then
        echo "Running command inside Docker container: $DOCKER_IMAGE"
        docker run --rm -it "$DOCKER_IMAGE" bash -c "$COMMAND"
    elif [ "$KUBERNETES_EXECUTION" = true ]; then
        echo "Generating Kubernetes manifest to run the command"
        generate_kubernetes_manifest
    else
        echo "Running command: $COMMAND"
        eval "$COMMAND"
    fi
else
    echo "Command Type: $COMMAND_TYPE"
    echo "Command is not safe to run."
    echo "Evaluated command: $COMMAND"
    if [ "$FORCE_EXECUTION" = true ]; then
        if [ "$DOCKER_EXECUTION" = true ]; then
            echo "Force execution enabled. Running command inside Docker container: $DOCKER_IMAGE"
            docker run --rm -it "$DOCKER_IMAGE" bash -c "$COMMAND"
        elif [ "$KUBERNETES_EXECUTION" = true ]; then
            echo "Force execution enabled. Generating Kubernetes manifest to run the command"
            generate_kubernetes_manifest
        else
            echo "Force execution enabled. Running command."
            eval "$COMMAND"
        fi
    else
        echo "Use --force to run the command anyway."
        exit 1
    fi
fi

# Function to generate Kubernetes manifest
generate_kubernetes_manifest() {
    MANIFEST_FILE="command-pod.yaml"
    cat <<EOF > $MANIFEST_FILE
apiVersion: v1
kind: Pod
metadata:
  name: command-test
spec:
  restartPolicy: Never
  containers:
  - name: command-container
    image: $KUBERNETES_IMAGE
    command: [ "bash", "-c", "$COMMAND" ]
EOF

    echo "Generated Kubernetes manifest:"
    cat $MANIFEST_FILE

    if [ "$APPLY_MANIFEST" = true ]; then
        check_kubectl
        echo "Applying Kubernetes manifest"
        kubectl apply -f $MANIFEST_FILE
    else
        echo "You can apply the manifest using:"
        echo "kubectl apply -f $MANIFEST_FILE"
    fi
}
