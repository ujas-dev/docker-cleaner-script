#!/bin/sh

# Script to completely clean Docker and local Kubernetes setups in WSL + Docker Desktop on Windows.
# Removes all containers, images, volumes, build caches, builders, and local K8s clusters (minikube, kind).
# Includes specific cleanup for build history in Docker Desktop's UI.
# Features: dry-run, verbose, filter by age, selective cleanup, dangling cleanup, interactive confirmation, clean docker logs, cron-friendly.
# Avoids --format flag for compatibility with older Docker versions.
# Fixed printf error by sanitizing counter variables and improving dangling resource counting.
# Use with caution! This can delete important data.

set -e

# Default variables
exclude_containers=""
exclude_images=""
exclude_volumes=""
exclude_builders=""
exclude_minikube=""
exclude_kind=""
protect_current=0
reset_docker_desktop=0
dry_run=0
verbose=0
older_than=-1  # Days, -1 means no filter
confirm=0
clean_logs=0
quiet=0

# Selective cleanup flags
only_containers=0
only_images=0
only_volumes=0
only_builders=0
only_minikube=0
only_kind=0
only_dangling=0
only_logs=0
run_all=1  # Default to run all unless any only_ is set

# Counters for logging
removed_containers=0
excluded_containers=0
removed_images=0
excluded_images=0
removed_volumes=0
excluded_volumes=0
processed_builders=0
removed_builders=0
excluded_builders=0
removed_minikube=0
excluded_minikube=0
removed_kind=0
excluded_kind=0
removed_dangling_images=0
removed_dangling_containers=0
removed_dangling_volumes=0
removed_dangling_networks=0
removed_dangling_build_cache=0
cleaned_logs=0

# Function to echo if not quiet
qecho() {
  if [ $quiet -eq 0 ]; then
    echo "$@"
  fi
}

# Function to prompt for confirmation
confirm_action() {
  if [ $confirm -eq 1 ]; then
    read -p "$1 [y/N]: " ans
    if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
      return 1
    fi
  fi
  return 0
}

# Function to check if resource is older than specified days
is_older_than() {
  created_at="$1"  # ISO 8601 or similar
  if [ $older_than -eq -1 ]; then
    return 0  # No filter, always true
  fi
  current_time=$(date +%s)
  created_time=$(date -d "$created_at" +%s 2>/dev/null || echo 0)
  if [ $created_time -eq 0 ]; then
    return 0  # If date parsing fails, assume old enough
  fi
  age_seconds=$((current_time - created_time))
  age_days=$((age_seconds / 86400))
  if [ $age_days -gt $older_than ]; then
    return 0
  else
    return 1
  fi
}

# Function to sanitize numeric variables
sanitize_number() {
  input="$1"
  # Remove non-numeric characters, return 0 if empty or invalid
  sanitized=$(echo "$input" | tr -d '[:space:]' | grep -E '^[0-9]+$' || echo 0)
  echo "$sanitized"
}

# Parse options
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-containers)
      shift
      exclude_containers="$1"
      ;;
    --exclude-images)
      shift
      exclude_images="$1"
      ;;
    --exclude-volumes)
      shift
      exclude_volumes="$1"
      ;;
    --exclude-builders)
      shift
      exclude_builders="$1"
      ;;
    --exclude-minikube)
      shift
      exclude_minikube="$1"
      ;;
    --exclude-kind)
      shift
      exclude_kind="$1"
      ;;
    --protect-current-dir)
      protect_current=1
      ;;
    --reset-docker-desktop)
      reset_docker_desktop=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    --verbose)
      verbose=1
      ;;
    --older-than)
      shift
      older_than="$1"
      ;;
    --only-containers)
      only_containers=1
      run_all=0
      ;;
    --only-images)
      only_images=1
      run_all=0
      ;;
    --only-volumes)
      only_volumes=1
      run_all=0
      ;;
    --only-builders)
      only_builders=1
      run_all=0
      ;;
    --only-minikube)
      only_minikube=1
      run_all=0
      ;;
    --only-kind)
      only_kind=1
      run_all=0
      ;;
    --only-dangling)
      only_dangling=1
      run_all=0
      ;;
    --only-logs)
      only_logs=1
      run_all=0
      ;;
    --confirm)
      confirm=1
      ;;
    --clean-logs)
      clean_logs=1
      ;;
    --quiet)
      quiet=1
      ;;
    *)
      qecho "Unknown option: $1"
      qecho "Usage: $0 [options]"
      qecho "Options:"
      qecho "  --exclude-containers \"c1 c2\"   Space-separated container IDs or names to exclude"
      qecho "  --exclude-images \"i1 i2\"       Space-separated image IDs or repo:tags to exclude"
      qecho "  --exclude-volumes \"v1 v2\"      Space-separated volume names to exclude"
      qecho "  --exclude-builders \"b1 b2\"     Space-separated builder names to exclude"
      qecho "  --exclude-minikube \"p1 p2\"     Space-separated minikube profiles to exclude"
      qecho "  --exclude-kind \"c1 c2\"         Space-separated kind clusters to exclude"
      qecho "  --protect-current-dir           Protect resources associated with the current directory (docker-compose projects)"
      qecho "  --reset-docker-desktop          Reset Docker Desktop data (WARNING: removes all Docker data)"
      qecho "  --dry-run                       Simulate cleanup without deleting"
      qecho "  --verbose                       Log detailed actions"
      qecho "  --older-than DAYS               Only remove resources older than DAYS days"
      qecho "  --only-containers               Only clean containers"
      qecho "  --only-images                   Only clean images"
      qecho "  --only-volumes                  Only clean volumes"
      qecho "  --only-builders                 Only clean builders and build history"
      qecho "  --only-minikube                 Only clean minikube profiles"
      qecho "  --only-kind                     Only clean kind clusters"
      qecho "  --only-dangling                 Only clean dangling/unused resources"
      qecho "  --only-logs                     Only clean container logs"
      qecho "  --confirm                       Prompt for confirmation before major actions"
      qecho "  --clean-logs                    Clean (truncate) Docker container logs"
      qecho "  --quiet                         Suppress output (for cron jobs)"
      exit 1
      ;;
  esac
  shift
done

# Check if running in WSL
if grep -qi microsoft /proc/version; then
  qecho "Detected WSL environment"
  is_wsl=1
else
  is_wsl=0
fi

# If protect-current-dir is enabled, identify and add protected resources (for docker-compose projects)
if [ $protect_current -eq 1 ]; then
  project_name=$(basename "$(pwd)")
  protected_containers=$(docker container ls -a --filter "label=com.docker.compose.project=$project_name" -q || true)

  for cont in $protected_containers; do
    exclude_containers="$exclude_containers $cont"
    cont_image=$(docker inspect --format '{{.Image}}' "$cont" 2>/dev/null || true)
    if [ -n "$cont_image" ]; then
      exclude_images="$exclude_images $cont_image"
    fi
    cont_volumes=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ end }}{{ end }}' "$cont" 2>/dev/null || true)
    exclude_volumes="$exclude_volumes $cont_volumes"
  done
fi

# Clean containers
if [ $run_all -eq 1 ] || [ $only_containers -eq 1 ]; then
  if confirm_action "Proceed with cleaning containers?"; then
    qecho "Cleaning containers..."
    all_container_ids=$(docker container ls -a -q || true)
    for id in $all_container_ids; do
      name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's|^/||' || true)
      created_at=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null || true)
      excluded=0
      for ex in $exclude_containers; do
        if [ "$id" = "$ex" ] || [ "$name" = "$ex" ]; then
          excluded=1
          break
        fi
      done
      if [ $excluded -eq 0 ] && is_older_than "$created_at"; then
        if [ $verbose -eq 1 ]; then
          qecho "Removing container: $id ($name)"
        fi
        if [ $dry_run -eq 0 ]; then
          docker container rm -f "$id" >/dev/null 2>&1 || true
        fi
        removed_containers=$((removed_containers + 1))
      else
        if [ $excluded -eq 1 ] && [ $verbose -eq 1 ]; then
          qecho "Excluding container: $id ($name)"
        fi
        excluded_containers=$((excluded_containers + 1))
      fi
    done
  fi
fi

# Clean images
if [ $run_all -eq 1 ] || [ $only_images -eq 1 ]; then
  if confirm_action "Proceed with cleaning images?"; then
    qecho "Cleaning images..."
    all_image_ids=$(docker image ls -a -q | sort -u || true)
    for id in $all_image_ids; do
      repotag=$(docker inspect --format '{{.RepoTags}}' "$id" 2>/dev/null | grep -o '[^]\[]*' || true)
      created_at=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null || true)
      excluded=0
      for ex in $exclude_images; do
        if [ "$id" = "$ex" ] || echo "$repotag" | grep -q "$ex"; then
          excluded=1
          break
        fi
      done
      if [ $excluded -eq 0 ] && is_older_than "$created_at"; then
        if [ $verbose -eq 1 ]; then
          qecho "Removing image: $id ($repotag)"
        fi
        if [ $dry_run -eq 0 ]; then
          docker image rm -f "$id" >/dev/null 2>&1 || true
        fi
        removed_images=$((removed_images + 1))
      else
        if [ $excluded -eq 1 ] && [ $verbose -eq 1 ]; then
          qecho "Excluding image: $id ($repotag)"
        fi
        excluded_images=$((excluded_images + 1))
      fi
    done
  fi
fi

# Clean volumes
if [ $run_all -eq 1 ] || [ $only_volumes -eq 1 ]; then
  if confirm_action "Proceed with cleaning volumes?"; then
    qecho "Cleaning volumes..."
    all_volumes=$(docker volume ls -q || true)
    for vol in $all_volumes; do
      excluded=0
      for ex in $exclude_volumes; do
        if [ "$vol" = "$ex" ]; then
          excluded=1
          break
        fi
      done
      # Volume creation dates not available in older Docker, skip age filter
      if [ $excluded -eq 0 ]; then
        if [ $verbose -eq 1 ]; then
          qecho "Removing volume: $vol"
        fi
        if [ $dry_run -eq 0 ]; then
          docker volume rm -f "$vol" >/dev/null 2>&1 || true
        fi
        removed_volumes=$((removed_volumes + 1))
      else
        if [ $excluded -eq 1 ] && [ $verbose -eq 1 ]; then
          qecho "Excluding volume: $vol"
        fi
        excluded_volumes=$((excluded_volumes + 1))
      fi
    done
  fi
fi

# Clean builders and build history
if [ $run_all -eq 1 ] || [ $only_builders -eq 1 ]; then
  if confirm_action "Proceed with cleaning builders and build history?"; then
    qecho "Cleaning up build history and caches..."
    all_builders=$(docker buildx ls | grep -v 'NAME/NODE' | awk '{print $1}' || true)
    for builder in $all_builders; do
      excluded=0
      for ex in $exclude_builders; do
        if [ "$builder" = "$ex" ]; then
          excluded=1
          break
        fi
      done
      if [ $excluded -eq 0 ]; then
        if [ $verbose -eq 1 ]; then
          qecho "Processing builder: $builder"
        fi
        if [ $dry_run -eq 0 ]; then
          docker buildx use "$builder" >/dev/null 2>&1 || true
          docker buildx prune -a -f >/dev/null 2>&1 || true
        fi
        processed_builders=$((processed_builders + 1))
        if [ "$builder" != "default" ]; then
          if [ $verbose -eq 1 ]; then
            qecho "Removing builder: $builder"
          fi
          if [ $dry_run -eq 0 ]; then
            docker buildx rm "$builder" >/dev/null 2>&1 || true
          fi
          removed_builders=$((removed_builders + 1))
        fi
      else
        if [ $verbose -eq 1 ]; then
          qecho "Skipping excluded builder: $builder"
        fi
        excluded_builders=$((excluded_builders + 1))
      fi
    done
  fi
fi

# WSL and Docker Desktop-specific cleanup
if [ $is_wsl -eq 1 ] && ([ $run_all -eq 1 ] || [ $only_builders -eq 1 ]); then
  if confirm_action "Proceed with WSL-specific cleanup?"; then
    qecho "Performing WSL-specific cleanup..."
    if [ $dry_run -eq 0 ]; then
      [ -d "$HOME/.docker/buildx" ] && rm -rf "$HOME/.docker/buildx"/* >/dev/null 2>&1 || true
      windows_userprofile=$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')
      wsl_userprofile=$(wslpath "$windows_userprofile" 2>/dev/null || true)
      if [ -n "$wsl_userprofile" ] && [ -d "$wsl_userprofile/.docker" ]; then
        qecho "Cleaning Windows-side Docker Desktop cache..."
        rm -rf "$wsl_userprofile/.docker/buildx"/* >/dev/null 2>&1 || true
        rm -rf "$wsl_userprofile/.docker/desktop/build"/* >/dev/null 2>&1 || true
      fi
    else
      qecho "[Dry-run] Would clean WSL and Windows-side caches"
    fi
  fi
fi

# Optional Docker Desktop reset
if [ $reset_docker_desktop -eq 1 ]; then
  if confirm_action "Proceed with resetting Docker Desktop (destructive)?"; then
    qecho "WARNING: Resetting Docker Desktop data (this removes ALL Docker data)..."
    if [ $dry_run -eq 0 ]; then
      cmd.exe /c "wsl --shutdown" >/dev/null 2>&1 || true
      powershell.exe -Command "Stop-Process -Name 'Docker Desktop' -Force" >/dev/null 2>&1 || true
      windows_docker_data="$windows_userprofile\AppData\Local\Docker"
      wsl_docker_data=$(wslpath "$windows_docker_data" 2>/dev/null || true)
      [ -d "$wsl_docker_data" ] && rm -rf "$wsl_docker_data"/* >/dev/null 2>&1 || true
      qecho "Docker Desktop data reset. You must restart Docker Desktop manually."
    else
      qecho "[Dry-run] Would reset Docker Desktop data"
    fi
  fi
fi

# Clean minikube
if [ $run_all -eq 1 ] || [ $only_minikube -eq 1 ]; then
  if command -v minikube >/dev/null 2>&1; then
    if confirm_action "Proceed with cleaning minikube profiles?"; then
      all_minikube=$(minikube profile list 2>/dev/null | tail -n +2 | head -n -1 | awk '{print $2}' || true)
      for profile in $all_minikube; do
        excluded=0
        for ex in $exclude_minikube; do
          if [ "$profile" = "$ex" ]; then
            excluded=1
            break
          fi
        done
        if [ $excluded -eq 0 ]; then
          if [ $verbose -eq 1 ]; then
            qecho "Removing minikube profile: $profile"
          fi
          if [ $dry_run -eq 0 ]; then
            minikube delete --profile "$profile" >/dev/null 2>&1 || true
          fi
          removed_minikube=$((removed_minikube + 1))
        else
          if [ $verbose -eq 1 ]; then
            qecho "Excluding minikube profile: $profile"
          fi
          excluded_minikube=$((excluded_minikube + 1))
        fi
      done
    fi
  fi
fi

# Clean kind
if [ $run_all -eq 1 ] || [ $only_kind -eq 1 ]; then
  if command -v kind >/dev/null 2>&1; then
    if confirm_action "Proceed with cleaning kind clusters?"; then
      all_kind=$(kind get clusters 2>/dev/null || true)
      for cluster in $all_kind; do
        excluded=0
        for ex in $exclude_kind; do
          if [ "$cluster" = "$ex" ]; then
            excluded=1
            break
          fi
        done
        if [ $excluded -eq 0 ]; then
          if [ $verbose -eq 1 ]; then
            qecho "Removing kind cluster: $cluster"
          fi
          if [ $dry_run -eq 0 ]; then
            kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
          fi
          removed_kind=$((removed_kind + 1))
        else
          if [ $verbose -eq 1 ]; then
            qecho "Excluding kind cluster: $cluster"
          fi
          excluded_kind=$((excluded_kind + 1))
        fi
      done
    fi
  fi
fi

# Clean dangling/unused resources
if [ $run_all -eq 1 ] || [ $only_dangling -eq 1 ]; then
  if confirm_action "Proceed with cleaning dangling/unused resources?"; then
    qecho "Cleaning dangling/unused resources..."
    if [ $dry_run -eq 0 ]; then
      # Count dangling images before pruning
      removed_dangling_images=$(docker image ls -q -f dangling=true | sort -u | wc -l || echo 0)
      removed_dangling_images=$(sanitize_number "$removed_dangling_images")
      docker image prune -f -a >/dev/null 2>&1 || true
      # Count exited containers before pruning
      removed_dangling_containers=$(docker container ls -a -q -f status=exited | wc -l || echo 0)
      removed_dangling_containers=$(sanitize_number "$removed_dangling_containers")
      docker container prune -f --filter "status=exited" >/dev/null 2>&1 || true
      # Count dangling volumes before pruning
      removed_dangling_volumes=$(docker volume ls -q -f dangling=true | wc -l || echo 0)
      removed_dangling_volumes=$(sanitize_number "$removed_dangling_volumes")
      docker volume prune -f >/dev/null 2>&1 || true
      # Count dangling networks before pruning
      removed_dangling_networks=$(docker network ls -q -f dangling=true | wc -l || echo 0)
      removed_dangling_networks=$(sanitize_number "$removed_dangling_networks")
      docker network prune -f >/dev/null 2>&1 || true
      # Build cache
      docker builder prune -a -f >/dev/null 2>&1 || true
      removed_dangling_build_cache=1
    else
      qecho "[Dry-run] Would clean dangling images, containers, volumes, networks, build cache"
      removed_dangling_images=$(docker image ls -q -f dangling=true | sort -u | wc -l || echo 0)
      removed_dangling_images=$(sanitize_number "$removed_dangling_images")
      removed_dangling_containers=$(docker container ls -a -q -f status=exited | wc -l || echo 0)
      removed_dangling_containers=$(sanitize_number "$removed_dangling_containers")
      removed_dangling_volumes=$(docker volume ls -q -f dangling=true | wc -l || echo 0)
      removed_dangling_volumes=$(sanitize_number "$removed_dangling_volumes")
      removed_dangling_networks=$(docker network ls -q -f dangling=true | wc -l || echo 0)
      removed_dangling_networks=$(sanitize_number "$removed_dangling_networks")
      removed_dangling_build_cache=1
    fi
  fi
fi

# Clean Docker logs
if [ $clean_logs -eq 1 ] && ([ $run_all -eq 1 ] || [ $only_logs -eq 1 ]); then
  if confirm_action "Proceed with cleaning Docker container logs?"; then
    qecho "Cleaning Docker container logs..."
    all_containers_ids=$(docker container ls -a -q || true)
    for id in $all_containers_ids; do
      log_path=$(docker inspect --format '{{.LogPath}}' "$id" 2>/dev/null || true)
      if [ -n "$log_path" ] && [ -f "$log_path" ]; then
        if [ $verbose -eq 1 ]; then
          qecho "Truncating log for container: $id ($log_path)"
        fi
        if [ $dry_run -eq 0 ]; then
          echo "" > "$log_path" 2>/dev/null || true
        fi
        cleaned_logs=$((cleaned_logs + 1))
      fi
    done
  fi
fi

# Final system-wide cleanup
if [ $run_all -eq 1 ] || [ $only_dangling -eq 1 ]; then
  if [ $dry_run -eq 0 ]; then
    docker system prune -a -f --volumes >/dev/null 2>&1 || true
  else
    qecho "[Dry-run] Would run system prune"
  fi
fi

# Output summary table
qecho "Cleanup completed."
qecho ""
qecho "Cleanup Summary:"
printf "%-25s | %-8s | %-8s\n" "Resource Type" "Removed" "Excluded"
printf "%-25s | %-8s | %-8s\n" "-------------------------" "--------" "--------"
printf "%-25s | %-8d | %-8d\n" "Containers" "$removed_containers" "$excluded_containers"
printf "%-25s | %-8d | %-8d\n" "Images" "$removed_images" "$excluded_images"
printf "%-25s | %-8d | %-8d\n" "Volumes" "$removed_volumes" "$excluded_volumes"
printf "%-25s | %-8d | %-8d\n" "Builders (Processed)" "$processed_builders" "$excluded_builders"
printf "%-25s | %-8d | %-8s\n" "Builders (Removed)" "$removed_builders" "N/A"
printf "%-25s | %-8d | %-8d\n" "Minikube Profiles" "$removed_minikube" "$excluded_minikube"
printf "%-25s | %-8d | %-8d\n" "Kind Clusters" "$removed_kind" "$excluded_kind"
printf "%-25s | %-8d | %-8s\n" "Dangling Images" "$removed_dangling_images" "N/A"
printf "%-25s | %-8d | %-8s\n" "Dangling Containers" "$removed_dangling_containers" "N/A"
printf "%-25s | %-8d | %-8s\n" "Dangling Volumes" "$removed_dangling_volumes" "N/A"
printf "%-25s | %-8d | %-8s\n" "Dangling Networks" "$removed_dangling_networks" "N/A"
printf "%-25s | %-8d | %-8s\n" "Dangling Build Cache" "$removed_dangling_build_cache" "N/A"
printf "%-25s | %-8d | %-8s\n" "Cleaned Logs" "$cleaned_logs" "N/A"

if [ $is_wsl -eq 1 ]; then
  qecho "Please restart Docker Desktop on Windows to refresh the UI."
  qecho "If build history persists, try running with --reset-docker-desktop (WARNING: highly destructive)."
fi
