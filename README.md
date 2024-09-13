Certainly! Here's the updated `README.md` reflecting the latest changes to the script:

---

# Safe Command Executor

A shell script that evaluates and safely executes commands, providing safety checks, command classification, and options to run commands inside a Docker container or Kubernetes environment.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
  - [Options](#options)
  - [Examples](#examples)
- [Command Classification](#command-classification)
- [Unsafe Patterns](#unsafe-patterns)
- [Notes and Considerations](#notes-and-considerations)
- [Customization](#customization)
- [License](#license)

## Features

- **Safety Checks**: Prevents execution of potentially dangerous commands unless explicitly forced.
- **Root User Warning**: Warns and exits if the script is run as the root user unless `--force` is used.
- **Command Classification**: Identifies and displays the type of command being executed.
- **Docker Integration**: Option to run commands inside a Docker container for isolation.
- **Kubernetes Integration**: Option to generate a Kubernetes manifest from the supplied command and optionally apply it.
- **Help Prompt**: Provides usage instructions when no options are passed or when `--help` is used.
- **Docker and Kubernetes Checks**: Verifies if Docker or `kubectl` are installed and running when their respective options are used.

## Prerequisites

- **Bash**: The script is written in Bash and requires a Unix-like environment.
- **Docker**: Required only if you plan to use the `--docker` option.
  - Docker must be installed and the Docker daemon must be running.
  - [Install Docker](https://docs.docker.com/get-docker/)
- **kubectl**: Required only if you plan to use the `--kubernetes` option with `--apply`.
  - `kubectl` must be installed and configured to connect to your Kubernetes cluster.
  - [Install kubectl](https://kubernetes.io/docs/tasks/tools/)

## Installation

1. **Download the Script**

   Save the script to a file, for example, `safe_run.sh`.

2. **Make the Script Executable**

   ```bash
   chmod +x safe_run.sh
   ```

3. **Move to a Directory in Your PATH** (Optional)

   To run the script from anywhere, move it to a directory that's in your `PATH`, such as `/usr/local/bin`.

   ```bash
   sudo mv safe_run.sh /usr/local/bin/safe_run
   ```

## Usage

```bash
./safe_run.sh [OPTIONS] COMMAND
```

### Options

- `--force`  
  Force execution of unsafe commands and override root user check.

- `--docker [IMAGE_NAME]`  
  Run the command inside a Docker container.  
  If `IMAGE_NAME` is not specified, defaults to `ubuntu:latest`.

- `--kubernetes [IMAGE_NAME]`  
  Generate a Kubernetes manifest from the supplied command.  
  If `IMAGE_NAME` is not specified, defaults to `ubuntu:latest`.

- `--apply`  
  When used with `--kubernetes`, applies the generated manifest using `kubectl`.

- `--help`  
  Display the help message.

### Examples

#### Running a Safe Command

```bash
./safe_run.sh ls -la
```

**Output:**

```
Command Type: Filesystem Commands
Running command: ls -la
[Command output]
```

#### Attempting to Run an Unsafe Command Without `--force`

```bash
./safe_run.sh rm -rf /important/data
```

**Output:**

```
Unsafe command detected: rm -rf
Command Type: Filesystem Commands
Command is not safe to run.
Evaluated command: rm -rf /important/data
Use --force to run the command anyway.
```

#### Forcing Execution of an Unsafe Command

```bash
./safe_run.sh --force rm -rf /important/data
```

**Output:**

```
Unsafe command detected: rm -rf
Command Type: Filesystem Commands
Command is not safe to run.
Evaluated command: rm -rf /important/data
Force execution enabled. Running command.
[Command executes]
```

#### Running a Command Inside Docker

```bash
./safe_run.sh --docker ubuntu:20.04 ls -la
```

**Output:**

```
Command Type: Filesystem Commands
Running command inside Docker container: ubuntu:20.04
[Command output from inside Docker container]
```

#### Forcing Execution of an Unsafe Command Inside Docker

```bash
./safe_run.sh --docker --force rm -rf /
```

**Output:**

```
Unsafe command detected: rm -rf
Command Type: Filesystem Commands
Command is not safe to run.
Evaluated command: rm -rf /
Force execution enabled. Running command inside Docker container: ubuntu:latest
[Command executes inside Docker container]
```

#### Generating a Kubernetes Manifest

```bash
./safe_run.sh --kubernetes alpine ls -la
```

**Output:**

```
Command Type: Kubernetes Command
Generating Kubernetes manifest to run the command
Generated Kubernetes manifest:
apiVersion: v1
kind: Pod
metadata:
  name: command-test
spec:
  restartPolicy: Never
  containers:
  - name: command-container
    image: alpine
    command: [ "bash", "-c", "ls -la" ]
You can apply the manifest using:
kubectl apply -f command-pod.yaml
```

#### Generating and Applying a Kubernetes Manifest

```bash
./safe_run.sh --kubernetes ubuntu:20.04 --apply ls -la
```

**Output:**

```
Command Type: Kubernetes Command
Generating Kubernetes manifest to run the command
Generated Kubernetes manifest:
apiVersion: v1
kind: Pod
metadata:
  name: command-test
spec:
  restartPolicy: Never
  containers:
  - name: command-container
    image: ubuntu:20.04
    command: [ "bash", "-c", "ls -la" ]
Applying Kubernetes manifest
[Output from kubectl apply]
```

#### Forcing Execution of an Unsafe Command in Kubernetes

```bash
./safe_run.sh --force --kubernetes alpine rm -rf /
```

**Output:**

```
Unsafe command detected: rm -rf
Command Type: Kubernetes Command
Force execution enabled. Generating Kubernetes manifest to run the command
Generated Kubernetes manifest:
apiVersion: v1
kind: Pod
metadata:
  name: command-test
spec:
  restartPolicy: Never
  containers:
  - name: command-container
    image: alpine
    command: [ "bash", "-c", "rm -rf /" ]
You can apply the manifest using:
kubectl apply -f command-pod.yaml
```

#### Displaying Help

```bash
./safe_run.sh --help
```

**Output:**

```
Usage: ./safe_run.sh [OPTIONS] COMMAND

Options:
  --force                  Force execution of unsafe commands and override root user check.
  --docker [IMAGE_NAME]    Run the command inside a Docker container.
                           If IMAGE_NAME is not specified, defaults to ubuntu:latest.
  --kubernetes [IMAGE_NAME] Create and optionally apply a Kubernetes manifest to run the command.
                           If IMAGE_NAME is not specified, defaults to ubuntu:latest.
  --apply                  When used with --kubernetes, applies the manifest using kubectl.
  --help                   Display this help message.

Examples:
  ./safe_run.sh ls -la
  ./safe_run.sh --docker ubuntu:20.04 ls -la
  ./safe_run.sh --force rm -rf /important/data
  ./safe_run.sh --docker --force rm -rf /
  ./safe_run.sh --kubernetes alpine ls -la
  ./safe_run.sh --kubernetes ubuntu:20.04 --apply ls -la
```

## Command Classification

The script classifies commands into the following categories:

- **Filesystem Commands**
- **Network Commands**
- **System Commands**
- **Process Commands**
- **Disk Commands**
- **Package Management**
- **User Management**
- **Compression Commands**
- **Text Processing**
- **Kubernetes Commands**

This classification helps in understanding the potential impact of the command being executed.

## Unsafe Patterns

The script checks for unsafe patterns to prevent accidental execution of dangerous commands. Some of the patterns include:

- `rm -rf`
- `mkfs.*` (any `mkfs` command)
- `dd if=`
- `shutdown`
- `reboot`
- `sudo`
- `su`
- Fork bombs (e.g., `:(){ :|:& };:`)
- `wget http://` and `curl http://` (for untrusted downloads)
- ZFS destructive commands (`zfs destroy`, `zpool destroy`, etc.)

**Note:** You can customize the list of unsafe patterns in the script as per your requirements.

## Notes and Considerations

### Safety Precautions

- **Review Commands**: Always review the commands before execution, especially when using `--force`.
- **Force Option**: Use the `--force` option cautiously. It overrides safety checks and root user warnings, and can lead to unintended consequences.
- **Root User Warning**: The script warns and exits if run as root unless `--force` is used.
- **Docker and Kubernetes Execution**: Running commands inside Docker or Kubernetes can provide isolation, but be cautious when mounting volumes or interacting with the host system.

### Docker Considerations

- **Docker Installation**: Ensure Docker is installed and the daemon is running when using the `--docker` option.
- **Permissions**: You may need appropriate permissions to run Docker commands without `sudo`.
- **Docker Images**: The environment inside the Docker container may differ from your host system. Ensure the necessary tools are available in the Docker image.
- **Custom Images**: For complex commands, consider using a custom Docker image with all required dependencies installed.

### Kubernetes Considerations

- **kubectl Installation**: Ensure `kubectl` is installed and configured to connect to your Kubernetes cluster when using the `--kubernetes` option with `--apply`.
- **Manifest File**: The generated Kubernetes manifest is saved as `command-pod.yaml` in the current directory.
- **Cluster Permissions**: Ensure you have the necessary permissions to create resources in your Kubernetes cluster.
- **Customizing the Manifest**: You can modify the generated manifest to suit your needs before applying it.

### Command Environment

- **Environment Differences**: The environment inside Docker or Kubernetes may differ from your host system. Ensure the necessary tools and dependencies are available.
- **Testing Commands**: Running commands in isolated environments can help test their behavior without affecting your host system.

## Customization

### Modifying Unsafe Patterns

Edit the `UNSAFE_PATTERNS` array in the script to add or remove commands you consider unsafe.

```bash
UNSAFE_PATTERNS=(
    "rm -rf"
    "mkfs.*"
    # Add your custom patterns here
)
```

### Adding Command Categories

Edit the `COMMAND_CATEGORIES` associative array to include new command types or commands.

```bash
declare -A COMMAND_CATEGORIES
COMMAND_CATEGORIES=(
    ["Filesystem Commands"]="rm|mkdir|touch|cp|mv|ln|ls|chmod|chown|df|du|mkfs.*|mount|umount|fsck|zfs|zpool"
    # Add your custom categories here
)
```

### Customizing the Kubernetes Manifest

Modify the `generate_kubernetes_manifest` function in the script to customize the Kubernetes manifest as needed.

```bash
generate_kubernetes_manifest() {
    # Customization here
}
```

## License

This script is released under the [MIT License](https://opensource.org/licenses/MIT). You are free to use, modify, and distribute it as per the license terms.

---

**Disclaimer:** Use this script at your own risk. The author is not responsible for any damage caused by the use of this script.

---

This updated `README.md` reflects the latest features of the script, including:

- **Root User Warning**: The script warns if run as root and requires `--force` to proceed.
- **Kubernetes Integration**: Added `--kubernetes` and `--apply` options to generate and optionally apply Kubernetes manifests.
- **Updated Usage Examples**: Demonstrates how to use the new options.
- **Additional Notes**: Includes considerations for using Kubernetes and the implications of running commands in different environments.

Feel free to let me know if you need any more information or further adjustments!