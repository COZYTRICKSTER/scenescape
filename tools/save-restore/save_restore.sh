#!/bin/bash
# Save and restore Docker volumes with an alternate prefix to avoid name clashes
# Usage:
#  ./save_restore.sh save [--dir DIR] [volume ...]
#  ./save_restore.sh restore [--dir DIR] [--prefix PREFIX] [volume ...]

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./saved_volumes}"
PREFIX=""
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
CMD=""

usage() {
    cat <<EOF
Usage:
  $0 save [--dir DIR] [volume ...]      Save named volumes (or all if none specified) into DIR
  $0 restore [--dir DIR] [--prefix P] [volume ...]  Restore archives from DIR into new volumes prefixed with P

Examples:
  $0 save scenescape_vol-db scenescape_vol-media
  $0 save --dir /tmp/vols
  $0 restore --prefix new_ scenescape_vol-db
  $0 restore
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

CMD="$1"; shift
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir)
            BACKUP_DIR="$2"; shift 2;;
        --prefix)
            PREFIX="$2"; shift 2;;
        --compose-file)
            COMPOSE_FILE="$2"; shift 2;;
        --help|-h)
            usage; exit 0;;
        --*)
            echo "Unknown option: $1"; usage; exit 1;;
        *)
            # remaining args are volumes
            break;;
    esac
done

# Gather volumes list from remaining args
VOLUMES=()
if [ "$#" -gt 0 ]; then
    while [ "$#" -gt 0 ]; do
        VOLUMES+=("$1")
        shift
    done
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found in PATH"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

if [ "$CMD" = "save" ]; then
    if [ ${#VOLUMES[@]} -eq 0 ]; then
        # Try to extract named volumes from compose file using robust tools
        if [ -f "$COMPOSE_FILE" ]; then
            echo "Attempting to extract named volumes from $COMPOSE_FILE"
            # Prefer yq if available
            if command -v yq >/dev/null 2>&1; then
                mapfile -t compose_vols < <(yq e '.volumes // {} | keys | .[]' "$COMPOSE_FILE" 2>/dev/null || true)
            else
                # Try docker compose config -> json + jq
                if command -v docker >/dev/null 2>&1 && docker compose -f "$COMPOSE_FILE" config --format json >/dev/null 2>&1; then
                    if command -v jq >/dev/null 2>&1; then
                        mapfile -t compose_vols < <(docker compose -f "$COMPOSE_FILE" config --format json | jq -r '.volumes // {} | keys[]' 2>/dev/null || true)
                    fi
                fi
            fi
            # If compose_vols populated, use it
            if [ ${#compose_vols[@]} -gt 0 ]; then
                for v in "${compose_vols[@]}"; do
                    VOLUMES+=("$v")
                done
            else
                # fallback: manual parsing (previous approach)
                in_vol_section=0
                while IFS= read -r line; do
                    if [ "$in_vol_section" -eq 0 ]; then
                        if [[ $line =~ ^[[:space:]]*volumes: ]]; then
                            in_vol_section=1
                        fi
                    else
                        if [[ ! $line =~ ^[[:space:]]+ ]]; then
                            break
                        fi
                        if [[ $line =~ ^[[:space:]]+([a-zA-Z0-9_.-]+):[[:space:]]*$ ]]; then
                            VOLUMES+=("${BASH_REMATCH[1]}")
                        fi
                    fi
                done < "$COMPOSE_FILE"
            fi
        fi
        # fallback to listing all docker volumes if none found
        if [ ${#VOLUMES[@]} -eq 0 ]; then
            while IFS= read -r v; do
                VOLUMES+=("$v")
            done < <(docker volume ls --format '{{.Name}}')
        fi
    fi
    echo "Saving ${#VOLUMES[@]} volumes to ${BACKUP_DIR}"
    resolve_volume_name() {
        local key="$1"
        # If exact docker volume exists, return it
        if docker volume inspect "$key" >/dev/null 2>&1; then
            echo "$key"; return 0
        fi
        # Try to find a volume that ends with _key or -key (common compose prefixes)
        cand=$(docker volume ls --format '{{.Name}}' | awk -v k="${key}" 'tolower($0) ~ tolower("_"k"$") || tolower($0) ~ tolower("-"k"$") {print $0; exit}')
        if [ -n "$cand" ]; then
            echo "$cand"; return 0
        fi
        # Last resort: any volume containing the key
        cand=$(docker volume ls --format '{{.Name}}' | grep -i "${key}" | head -n1 || true)
        if [ -n "$cand" ]; then
            echo "$cand"; return 0
        fi
        # Not found
        return 1
    }

    for vol in "${VOLUMES[@]}"; do
        if [ -z "$vol" ]; then
            continue
        fi
        # Resolve to actual docker volume name (may be project-prefixed)
        if resolved=$(resolve_volume_name "$vol"); then
            docker_vol="$resolved"
        else
            echo_warn "Could not find docker volume for '$vol'; attempting to use it directly (may produce empty archive)"
            docker_vol="$vol"
        fi
        safe_file="${docker_vol}.tar.gz"
        echo "Saving volume: $docker_vol -> ${BACKUP_DIR}/${safe_file}"
        
        # Check if volume exists
        if ! docker volume inspect "$docker_vol" >/dev/null 2>&1; then
            echo "Warning: Docker volume '$docker_vol' does not exist, skipping" >&2
            continue
        fi
        
        # Show volume contents for debugging
        echo "Checking volume contents..."
        vol_contents=$(docker run --rm -v "${docker_vol}:/volume" alpine sh -c 'find /volume -type f | wc -l' 2>/dev/null || echo "0")
        vol_size=$(docker run --rm -v "${docker_vol}:/volume" alpine sh -c 'du -sh /volume 2>/dev/null | cut -f1' || echo "unknown")
        echo "Volume $docker_vol contains $vol_contents files, size: $vol_size"
        
        if [ "$vol_contents" = "0" ]; then
            echo "Warning: Volume $docker_vol appears to be empty" >&2
        fi
        
        # Create archive with verbose output
        echo "Creating archive..."
        if docker run --rm -v "${docker_vol}:/volume" -v "$(realpath "$BACKUP_DIR"):/backup" alpine sh -c "cd /volume && tar -czf /backup/\"${safe_file}\" . && echo 'Archive created successfully'"; then
            # Verify archive was created and has content
            if [ -f "${BACKUP_DIR}/${safe_file}" ]; then
                archive_size=$(ls -lh "${BACKUP_DIR}/${safe_file}" | awk '{print $5}')
                echo "Archive ${safe_file} created successfully, size: $archive_size"
            else
                echo "Error: Archive file was not created" >&2
            fi
        else
            echo "Error: Failed to create archive for volume: ${docker_vol}" >&2
        fi
    done
    echo "Save complete"
    exit 0
elif [ "$CMD" = "restore" ]; then
    # If volumes were passed, restore those archives; otherwise restore all archives in DIR
    ARCHIVES=()
    if [ ${#VOLUMES[@]} -gt 0 ]; then
        for vol in "${VOLUMES[@]}"; do
            ARCHIVES+=("${vol}.tar.gz")
        done
    else
        while IFS= read -r f; do
            ARCHIVES+=("$(basename "$f")")
        done < <(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true)
    fi
    if [ ${#ARCHIVES[@]} -eq 0 ]; then
        echo "No archives found in ${BACKUP_DIR} to restore"
        exit 1
    fi
    echo "Restoring ${#ARCHIVES[@]} archives from ${BACKUP_DIR} with prefix '${PREFIX}'"
    for a in "${ARCHIVES[@]}"; do
        base="${a%.tar.gz}"
        newvol="${PREFIX}${base}"
        echo "Restoring ${a} -> volume ${newvol}"
        if ! docker volume inspect "$newvol" >/dev/null 2>&1; then
            docker volume create "$newvol"
        fi
        if ! docker run --rm -v "${newvol}:/volume" -v "$(realpath "$BACKUP_DIR"):/backup" alpine sh -c "cd /volume && tar -xzf /backup/\"${a}\" || true"; then
            echo "Warning: failed to restore archive: $a" >&2
        fi
    done
    echo "Restore complete"
    exit 0
else
    echo "Unknown command: $CMD"; usage; exit 1
fi
