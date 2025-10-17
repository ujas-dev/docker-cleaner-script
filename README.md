# Docker and Kubernetes Cleaner

A robust, feature-rich shell script to clean up Docker containers, images, volumes, build caches, and local Kubernetes clusters (minikube, kind) in WSL and Docker Desktop environments. Designed for developers and system administrators, this script provides granular control over cleanup with options for dry-run, verbose logging, age-based filtering, selective resource targeting, and more. Use with caution, as it can delete critical Docker and Kubernetes resources.

## Features

- **Comprehensive Cleanup**: Removes Docker containers, images, volumes, build caches, builders, and local Kubernetes clusters (minikube, kind).
- **WSL and Docker Desktop Support**: Handles WSL-specific paths and Docker Desktop build history cleanup.
- **Dry-Run Mode**: Simulates cleanup without deleting anything (`--dry-run`).
- **Verbose Logging**: Detailed output for each action (`--verbose`).
- **Age-Based Filtering**: Removes resources older than a specified number of days (`--older-than DAYS`).
- **Selective Cleanup**: Target specific resource types (e.g., `--only-containers`, `--only-images`).
- **Dangling Resource Cleanup**: Removes unused images, exited containers, dangling volumes, networks, and build caches (`--only-dangling`).
- **Interactive Confirmation**: Prompts before major actions (`--confirm`).
- **Container Log Cleaning**: Truncates Docker container logs to free space (`--clean-logs`).
- **Cron-Friendly**: Quiet mode for automated runs (`--quiet`).
- **Exclusion Options**: Protect specific containers, images, volumes, builders, or clusters (e.g., `--exclude-containers "c1 c2"`).
- **Protect Current Directory**: Automatically excludes resources tied to the current directory's Docker Compose project (`--protect-current-dir`).
- **Docker Desktop Reset**: Optional reset of all Docker Desktop data (`--reset-docker-desktop`, destructive).
- **Summary Table**: Outputs a detailed table of removed and excluded resources.

## Installation

1. **Download the Script**:
   ```bash
   wget https://raw.githubusercontent.com/yourusername/docker-k8s-cleaner/main/clean_docker.sh
   ```

2. **Make Executable**:
   ```bash
   chmod +x clean_docker.sh
   ```

3. **Ensure Dependencies**:
   - Docker CLI (compatible with Docker Desktop on Windows or native Linux).
   - Optional: `minikube` and `kind` for Kubernetes cleanup.
   - WSL2 (for Windows users running Docker Desktop).
   - Basic Unix tools (`awk`, `grep`, `date`, `wc`).

4. **Verify Docker Setup**:
   - Run `docker --version` to ensure Docker is installed.
   - For WSL, ensure Docker Desktop is configured with WSL2 integration (Settings > Resources > WSL Integration).

## Usage

Run the script from your WSL or Linux terminal. Use options to customize the cleanup process.

### Basic Usage
```bash
./clean_docker.sh
```
Cleans all Docker and Kubernetes resources (except excluded ones).

### Options
```bash
./clean_docker.sh [options]
Options:
  --exclude-containers "c1 c2"   Space-separated container IDs or names to exclude
  --exclude-images "i1 i2"       Space-separated image IDs or repo:tags to exclude
  --exclude-volumes "v1 v2"      Space-separated volume names to exclude
  --exclude-builders "b1 b2"     Space-separated builder names to exclude
  --exclude-minikube "p1 p2"     Space-separated minikube profiles to exclude
  --exclude-kind "c1 c2"         Space-separated kind clusters to exclude
  --protect-current-dir          Protect resources associated with the current directory (docker-compose projects)
  --reset-docker-desktop         Reset Docker Desktop data (WARNING: removes all Docker data)
  --dry-run                      Simulate cleanup without deleting
  --verbose                      Log detailed actions
  --older-than DAYS              Only remove resources older than DAYS days
  --only-containers              Only clean containers
  --only-images                  Only clean images
  --only-volumes                 Only clean volumes
  --only-builders                Only clean builders and build history
  --only-minikube                Only clean minikube profiles
  --only-kind                    Only clean kind clusters
  --only-dangling                Only clean dangling/unused resources
  --only-logs                    Only clean container logs
  --confirm                      Prompt for confirmation before major actions
  --clean-logs                   Clean (truncate) Docker container logs
  --quiet                        Suppress output (for cron jobs)
```

### Examples
- **Dry-run with verbose output**:
  ```bash
  ./clean_docker.sh --dry-run --verbose
  ```
  Simulates cleanup and logs every action.

- **Clean containers older than 30 days**:
  ```bash
  ./clean_docker.sh --only-containers --older-than 30
  ```

- **Clean dangling resources and logs quietly (for cron)**:
  ```bash
  ./clean_docker.sh --quiet --only-dangling --clean-logs
  ```

- **Protect current directory and exclude a builder**:
  ```bash
  ./clean_docker.sh --protect-current-dir --exclude-builders "my-builder"
  ```

- **Reset Docker Desktop (destructive)**:
  ```bash
  ./clean_docker.sh --reset-docker-desktop --confirm
  ```

### Cron Setup
To automate cleanup (e.g., nightly at 2 AM), edit your crontab:
```bash
crontab -e
```
Add:
```bash
0 2 * * * /path/to/clean_docker.sh --quiet --older-than 30 --only-dangling --clean-logs
```

## Output
The script outputs a summary table of removed and excluded resources:
```
Cleanup Summary:
Resource Type             | Removed  | Excluded
------------------------- | -------- | --------
Containers                | 5        | 2
Images                    | 10       | 1
Volumes                   | 3        | 0
Builders (Processed)      | 2        | 1
Builders (Removed)        | 1        | N/A
Minikube Profiles         | 0        | 0
Kind Clusters             | 1        | 0
Dangling Images           | 4        | N/A
Dangling Containers       | 2        | N/A
Dangling Volumes          | 1        | N/A
Dangling Networks         | 1        | N/A
Dangling Build Cache      | 1        | N/A
Cleaned Logs              | 5        | N/A
```

## Troubleshooting

- **Error: `unknown flag: --format`**:
  - The script avoids `--format` for compatibility with older Docker versions (<19.03). If you encounter issues, update Docker Desktop or verify your Docker CLI version (`docker --version`).
- **Error: `printf: 0 0: not completely converted`**:
  - Fixed in the latest version by sanitizing counter variables. If it persists, run with `--verbose --dry-run` and share the output.
- **Build History Persists in Docker Desktop**:
  - Restart Docker Desktop.
  - Manually delete `$HOME/.docker/buildx` (WSL) and `%USERPROFILE%\.docker\buildx` (Windows).
  - Use `--reset-docker-desktop` (back up critical data first).
- **Permission Issues**:
  - Run with `sudo` in WSL: `sudo ./clean_docker.sh`.
  - Ensure Docker Desktop WSL2 integration is enabled.
- **Slow Performance**:
  - Increase WSL2 memory in `%USERPROFILE%\.wslconfig`:
    ```ini
    [wsl2]
    memory=8GB
    ```
- **Debugging**:
  - Run with verbose mode: `./clean_docker.sh --verbose --dry-run`.
  - Check Docker version: `docker --version` and `docker buildx version`.
  - Share output with the maintainer for further assistance.

## System Requirements
- **OS**: WSL2 (Windows 11) or Linux.
- **Hardware**: 16 GB RAM recommended (script is optimized for your 12th Gen Intel i7-1255U, 16 GB RAM setup).
- **Software**: Docker CLI, Docker Desktop (for Windows), optional minikube/kind.
- **Docker Version**: Compatible with older versions (pre-19.03), but 19.03+ recommended for optimal performance.

## Contributing
Contributions are welcome! Fork the repository, make changes, and submit a pull request. Please test changes in a WSL or Linux environment and ensure compatibility with Docker Desktop.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments
- Built for developers and DevOps engineers managing Docker and Kubernetes in WSL and Docker Desktop environments.
- Inspired by community tools like `docker-clean` and Stack Overflow solutions for Docker resource management.
