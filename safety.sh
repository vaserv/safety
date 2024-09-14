#!/bin/bash

set -oeu pipefail
# set -x 
# Default behavior
export FORCE_EXECUTION=false
export DOCKER_EXECUTION=false
export DOCKER_IMAGE="ubuntu:latest"
export KUBERNETES_EXECUTION=false
export KUBERNETES_IMAGE="ubuntu:latest"
export APPLY_MANIFEST=false
export RUN_COMMAND=false
export CHATGPT_EVALUATION=false

# Function to display usage help
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Options:"
    echo "  --run                    Execute the command after safety checks."
    echo "  --force                  Force execution of unsafe commands and override root user check."
    echo "  --docker [IMAGE_NAME]    Run the command inside a Docker container."
    echo "                           If IMAGE_NAME is not specified, defaults to ubuntu:latest."
    echo "  --kubernetes [IMAGE_NAME] Create and optionally apply a Kubernetes manifest to run the command."
    echo "                           If IMAGE_NAME is not specified, defaults to ubuntu:latest."
    echo "  --apply                  When used with --kubernetes, applies the manifest using kubectl."
    echo "  --gpt                    Use ChatGPT to evaluate the command for safety."
    echo "  --help                   Display this help message."
    echo ""
    echo "Examples:"
    echo "  $0 --run ls -la"
    echo "  $0 --docker ubuntu:20.04 --run ls -la"
    echo "  $0 --force --run rm -rf /important/data"
    echo "  $0 --docker --force --run rm -rf /"
    echo "  $0 --kubernetes alpine ls -la"
    echo "  $0 --kubernetes ubuntu:20.04 --apply --run ls -la"
    echo "  $0 --gpt ls -la"
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

# Function to check if kubectl is installed and configured
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed or not found in PATH."
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

# Function to evaluate the command using ChatGPT
chatgpt_evaluate_command() {
    local command="$1"

    # Check if OPENAI_API_KEY is set
    if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Error: OPENAI_API_KEY is not set."
        echo "Please export your OpenAI API key as an environment variable."
        exit 1
    fi

    # Prepare the JSON payload
    local payload=$(jq -n --arg cmd "$command" \
        '{
            "model": "gpt-3.5-turbo",
            "messages": [
                {"role": "system", "content": "You are an AI language assistant that helps to evaluate shell commands for safety and correctness."},
                {"role": "user", "content": "Please evaluate the following shell command for safety and provide any potential risks:\n\n\"\($cmd)\""}
            ]
        }')

    # Send the request to the OpenAI API
    local response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$payload")

    # Check for errors in the response
    if echo "$response" | grep -q '"error"'; then
        local error_message=$(echo "$response" | jq -r '.error.message')
        echo "Error from OpenAI API: $error_message"
        exit 1
    fi

    # Extract the assistant's reply
    local reply=$(echo "$response" | jq -r '.choices[0].message.content')

    # Output the assistant's reply
    echo -e "ChatGPT Evaluation:\n$reply"
}

# Check if no arguments are provided or if --help is used
if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
    usage
fi

# Parse options
while [[ "$1" == --* ]]; do
    case "$1" in
        --run)
            RUN_COMMAND=true
            shift
            ;;
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
        --gpt)
            CHATGPT_EVALUATION=true
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

# Check for jq
if [ "$CHATGPT_EVALUATION" = true ]; then
    check_jq
fi

# Check if the command is safe
SAFE=1  # Assume unsafe
if is_safe; then
    SAFE=0
fi

# Evaluate with ChatGPT if requested
if [ "$CHATGPT_EVALUATION" = true ]; then
    chatgpt_evaluate_command "$COMMAND"
    # Prompt user for decision
    echo "Do you want to proceed with executing this command? (yes/no)"
    read -r USER_DECISION
    if [ "$USER_DECISION" != "yes" ]; then
        echo "Command execution aborted by user."
        exit 0
    fi
    # User wants to proceed, set SAFE=0
    SAFE=0
fi

# Proceed based on safety and user options
if [ $SAFE -eq 0 ]; then
    echo "Command Type: $COMMAND_TYPE"
    echo "Evaluated Command: $COMMAND"
    if [ "$RUN_COMMAND" = true ]; then
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
        echo "Command evaluation complete. Use --run to execute the command."
    fi
else
    echo "Command Type: $COMMAND_TYPE"
    echo "Unsafe command detected. Evaluated Command: $COMMAND"
    if [ "$FORCE_EXECUTION" = true ] && [ "$RUN_COMMAND" = true ]; then
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
        echo "Command is not safe to run."
        echo "Use --force and --run to execute the command anyway."
        exit 1
    fi
fi

