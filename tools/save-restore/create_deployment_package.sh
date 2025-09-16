#!/bin/bash

# SPDX-FileCopyrightText: (C) 2025 Intel Corporation  
# SPDX-License-Identifier: Apache-2.0

# Script to create a deployment package for SceneScape Docker Compose
# This package will contain everything needed to run docker compose up on another machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NAME="${PACKAGE_NAME:-scenescape-deployment-$(date +%Y%m%d_%H%M%S)}"
PACKAGE_DIR="${SCRIPT_DIR}/${PACKAGE_NAME}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

# Find and navigate to workspace root (where docker-compose.yml should be)
WORKSPACE_ROOT=""
if [ -f "${COMPOSE_FILE}" ]; then
    # docker-compose.yml is in current directory - this is the workspace root
    WORKSPACE_ROOT="$(pwd)"
elif [ -f "../../${COMPOSE_FILE}" ]; then
    # We're in tools/save-restore, navigate to workspace root
    WORKSPACE_ROOT="$(cd ../.. && pwd)"
    cd "${WORKSPACE_ROOT}"
else
    # Try to find workspace root by looking for docker-compose.yml
    current_dir="$(pwd)"
    while [ "${current_dir}" != "/" ]; do
        if [ -f "${current_dir}/${COMPOSE_FILE}" ]; then
            WORKSPACE_ROOT="${current_dir}"
            cd "${WORKSPACE_ROOT}"
            break
        fi
        current_dir="$(dirname "${current_dir}")"
    done
fi

if [ -z "${WORKSPACE_ROOT}" ] || [ ! -f "${COMPOSE_FILE}" ]; then
    echo_error "Could not find workspace root or Docker Compose file '${COMPOSE_FILE}'"
    echo_error "Please run from the workspace root or ensure docker-compose.yml exists"
    exit 1
fi

# Parse arguments (support --dry-run or -n)
DRY_RUN=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run|-n]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if docker-compose.yml exists
if [ ! -f "${COMPOSE_FILE}" ]; then
    echo_error "Docker Compose file '${COMPOSE_FILE}' not found!"
    echo_error "Please run 'make docker-compose.yml' first or specify COMPOSE_FILE environment variable"
    exit 1
fi

echo_info "Creating deployment package: ${PACKAGE_NAME}"

if [ "$DRY_RUN" -eq 0 ]; then
    # Create package directory structure
    mkdir -p "${PACKAGE_DIR}"
    mkdir -p "${PACKAGE_DIR}/configs"
    mkdir -p "${PACKAGE_DIR}/manager/secrets"
    mkdir -p "${PACKAGE_DIR}/scripts"
else
    echo_info "DRY RUN: will not create package directories or write files"
fi

# Copy Docker Compose filels
echo_info "Copying Docker Compose configuration..."
if [ "$DRY_RUN" -eq 0 ]; then
    cp "${COMPOSE_FILE}" "${PACKAGE_DIR}/"
else
    echo "DRY RUN: would copy ${COMPOSE_FILE} to ${PACKAGE_DIR}/"
fi

# Copy configuration files referenced in docker-compose.yml
echo_info "Copying configuration files..."
if [ -d "dlstreamer-pipeline-server" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        cp -r dlstreamer-pipeline-server "${PACKAGE_DIR}/"
        mkdir -p "${PACKAGE_DIR}/controller"
        cp -r controller/config "${PACKAGE_DIR}/controller/"
    else
        echo "DRY RUN: would copy dlstreamer-pipeline-server to ${PACKAGE_DIR}/"
    fi
fi

if [ -d "controller/config" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        cp -r controller/config "${PACKAGE_DIR}/configs/controller"
    else
        echo "DRY RUN: would copy controller/config to ${PACKAGE_DIR}/configs/controller"
    fi
fi

# Copy save_restore.sh script if it exists (for volume restoration)
if [ -f "tools/save-restore/save_restore.sh" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        cp tools/save-restore/save_restore.sh "${PACKAGE_DIR}/"
        chmod +x "${PACKAGE_DIR}/save_restore.sh"
    else
        echo "DRY RUN: would copy tools/save-restore/save_restore.sh to ${PACKAGE_DIR}/"
    fi
fi

# Copy generate_secrets.sh script if it exists (as fallback for missing secrets)
if [ -f "tools/save-restore/generate_secrets.sh" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        cp tools/save-restore/generate_secrets.sh "${PACKAGE_DIR}/scripts/"
        chmod +x "${PACKAGE_DIR}/scripts/generate_secrets.sh"
    else
        echo "DRY RUN: would copy tools/save-restore/generate_secrets.sh to ${PACKAGE_DIR}/scripts/"
    fi
fi

# Copy existing secrets directory if it exists
if [ -d "manager/secrets" ]; then
    echo_info "Copying existing secrets directory..."
    if [ "$DRY_RUN" -eq 0 ]; then
        cp -r manager/secrets "${PACKAGE_DIR}/manager/"
    else
        echo "DRY RUN: would copy manager/secrets directory to ${PACKAGE_DIR}/manager/"
    fi
fi

# NOTE: Instead of relying on the workspace `sample_data` directory to
# populate Docker volumes on the target machine, we archive and save the
# named Docker volumes (as defined in `docker-compose.yml`) so they can be
# restored verbatim on the target machine. This preserves permissions and
# contents exactly as they exist locally.
echo_info "(If needed) Docker volumes will be saved when you choose to save images."

# Create secrets directory structure (empty, to be populated by user) - only if not copying existing secrets
if [ ! -d "manager/secrets" ]; then
    echo_info "Creating empty secrets directory structure..."
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "${PACKAGE_DIR}/manager/secrets/certs"
        cat > "${PACKAGE_DIR}/manager/secrets/README.md" << 'EOF'
# Secrets Directory

This directory should contain the following files before running docker compose up:

## Certificates
- `certs/scenescape-ca.pem` - Root certificate
- `certs/scenescape-web.crt` - Web server certificate  
- `certs/scenescape-web.key` - Web server private key
- `certs/scenescape-vdms-c.crt` - VDMS client certificate
- `certs/scenescape-vdms-c.key` - VDMS client private key
- `certs/scenescape-vdms-s.crt` - VDMS server certificate
- `certs/scenescape-vdms-s.key` - VDMS server private key

## Authentication Files
- `django` - Django secret key
- `browser.auth` - Browser authentication credentials
- `calibration.auth` - Calibration service authentication
- `controller.auth` - Controller authentication credentials

## Environment Variables
Set the following environment variables before running:
- `SECRETSDIR=/path/to/secrets` (usually the full path to this secrets directory)
- `VERSION=latest` (or specific version tag)
- `UID=$(id -u)` (current user ID)
- `GID=$(id -g)` (current group ID)
- `SUPASS=<superuser_password>` (database superuser password)
- `DBROOT=<database_root_password>` (database root password)

You can generate these secrets using the generate_secrets.sh script provided in the scripts directory.
EOF
    else
        echo "DRY RUN: would create secrets directory structure and README.md"
    fi
else
    echo_info "Using existing secrets directory (skipping empty structure creation)"
fi

# Create environment template file
echo_info "Creating environment template..."
if [ "$DRY_RUN" -eq 0 ]; then
    # Try to get passwords from existing secrets if available
    DBROOT_VALUE=""
    CONTROLLER_AUTH_VALUE=""
    
    # Detect the VERSION that will be used for images
    TEMPLATE_VERSION="latest"
    if [ -f ".env" ]; then
        DETECTED_VERSION=$(grep "^VERSION=" .env | cut -d'=' -f2)
        if [ -n "$DETECTED_VERSION" ]; then
            TEMPLATE_VERSION="$DETECTED_VERSION"
        fi
    fi
    
    if [ -d "manager/secrets" ]; then
        # Try to read DATABASE_PASSWORD from django secrets
        if [ -f "manager/secrets/django/secrets.py" ]; then
            DBROOT_VALUE=$(grep "^DATABASE_PASSWORD=" "manager/secrets/django/secrets.py" | cut -d"'" -f2 2>/dev/null || echo "")
            # If not found with single quotes, try double quotes
            if [ -z "$DBROOT_VALUE" ]; then
                DBROOT_VALUE=$(grep "^DATABASE_PASSWORD=" "manager/secrets/django/secrets.py" | cut -d'"' -f2 2>/dev/null || echo "")
            fi
        fi
        # Generate DBROOT if not found (it's typically generated fresh)
        if [ -z "$DBROOT_VALUE" ]; then
            DBROOT_VALUE=$(openssl rand -base64 32 2>/dev/null || echo "")
        fi
        
        # Try to read CONTROLLER_AUTH from controller.auth file
        if [ -f "manager/secrets/controller.auth" ]; then
            CONTROLLER_AUTH_VALUE=$(cat "manager/secrets/controller.auth" 2>/dev/null || echo "")
        fi
    fi

    cat > "${PACKAGE_DIR}/.env.template" << EOF
# SceneScape Environment Configuration
# Copy this file to .env and fill in the appropriate values

# Version of SceneScape images to use
VERSION=${TEMPLATE_VERSION}

# User and Group IDs (usually your current user)
UID=1000
GID=1000

# Path to secrets directory (absolute path)
SECRETSDIR=./manager/secrets

# Database passwords (generated from existing secrets or set manually)
SUPASS=
DBROOT=${DBROOT_VALUE}

# Controller authentication (required by docker-compose.yml)
CONTROLLER_AUTH=${CONTROLLER_AUTH_VALUE}

# Docker Compose project name (optional)
COMPOSE_PROJECT_NAME=scenescape
EOF
else
    echo "DRY RUN: would create .env.template with auto-populated values from existing secrets"
fi

# Create scripts for secret generation and deployment
echo_info "Creating deployment scripts..."

# Secret generation script (copied from source directory above)
# Note: The generate_secrets.sh file is copied during the config files section

# Deployment script
if [ "$DRY_RUN" -eq 0 ]; then
    cat > "${PACKAGE_DIR}/scripts/deploy.sh" << 'EOF'
#!/bin/bash

# SceneScape Deployment Script
# This script sets up and starts the SceneScape Docker Compose environment

set -e

DEPLOYMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${DEPLOYMENT_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo_error ".env file not found!"
    echo_info "Please copy .env.template to .env and configure it with your settings"
    exit 1
fi

# Load environment variables (handle readonly variables like UID gracefully)
set -o allexport
# Source .env but ignore errors from readonly variables
source .env 2>/dev/null || {
    # If sourcing fails due to readonly variables, load manually
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        # Try to export, ignore errors for readonly variables
        export "$key=$value" 2>/dev/null || true
    done < .env
}
set +o allexport

# Validate required environment variables
REQUIRED_VARS=("VERSION" "UID" "GID" "SECRETSDIR" "SUPASS" "DBROOT" "CONTROLLER_AUTH")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo_error "Required environment variable $var is not set in .env file"
        exit 1
    fi
done

# Check if secrets exist
echo_info "Checking secrets..."
if [ ! -d "${SECRETSDIR}" ]; then
    echo_error "Secrets directory not found: ${SECRETSDIR}"
    echo_info "Please run: ./scripts/generate_secrets.sh"
    exit 1
fi

REQUIRED_SECRETS=(
    "certs/scenescape-ca.pem"
    "certs/scenescape-web.crt"
    "certs/scenescape-web.key"
    "django"
    "browser.auth"
    "calibration.auth"
    "controller.auth"
)

for secret in "${REQUIRED_SECRETS[@]}"; do
    if [ ! -f "${SECRETSDIR}/${secret}" ]; then
        echo_error "Required secret file not found: ${SECRETSDIR}/${secret}"
        echo_info "Please run: ./scripts/generate_secrets.sh"
        exit 1
    fi
done

# Check Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo_error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo_error "Docker Compose plugin is not installed"
    exit 1
fi

# Check for required ports
REQUIRED_PORTS=(443 1883 8080 8081)
for port in "${REQUIRED_PORTS[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
        echo_warn "Port ${port} appears to be in use. This may cause conflicts."
    fi
done

echo_info "Pre-flight checks passed!"

# Pull images if requested
if [ "${PULL_IMAGES:-yes}" = "yes" ]; then
    echo_info "Pulling Docker images..."
    docker compose pull
fi

# Start services
echo_info "Starting SceneScape services..."
docker compose up -d

# Wait for services to be ready
echo_info "Waiting for services to start..."
sleep 30

# Check service health
echo_info "Checking service health..."
if docker compose ps | grep -q "unhealthy\|exited"; then
    echo_warn "Some services may not be healthy. Check with: docker compose ps"
    echo_warn "Check logs with: docker compose logs [service_name]"
else
    echo_info "All services appear to be running!"
fi

echo ""
echo "====================================================================="
echo_info "SceneScape deployment complete!"
echo_info "Web interface: https://localhost:443"
echo_info "DL Streamer (retail): http://localhost:8080"
echo_info "DL Streamer (queuing): http://localhost:8081"
echo ""
echo_info "Superuser password: ${SUPASS}"
echo ""
echo_info "To stop services: docker compose down"
echo_info "To view logs: docker compose logs [service_name]"
echo_info "To check status: docker compose ps"
echo "====================================================================="
EOF

    chmod +x "${PACKAGE_DIR}/scripts/deploy.sh"
else
    echo "DRY RUN: would create scripts/deploy.sh"
fi

# Create README for the package
if [ "$DRY_RUN" -eq 0 ]; then
    cat > "${PACKAGE_DIR}/README.md" << 'EOF'
# SceneScape Deployment Package

This package contains everything needed to deploy SceneScape using Docker Compose on a new machine.

## Prerequisites

- Docker Engine 20.10.23 or higher
- Docker Compose plugin 2.24.2 or higher
- Linux system (tested on Ubuntu/Debian and RHEL/Fedora)
- At least 8GB RAM
- 20GB free disk space

## Quick Start

1. **Extract and navigate to the deployment directory**
   ```bash
   cd scenescape-deployment-[timestamp]
   ```

2. **Load Docker images (if included in the package)**
   
   If the package includes an `images/` directory with Docker images for offline deployment:
   ```bash
   ./scripts/load_images.sh
   ```
   
   This step loads all required Docker images and restores any saved volumes. Skip this step if you plan to pull images from a registry instead.

3. **Set up secrets and certificates**
   
   If the `manager/secrets/` directory is already populated, you can skip this step.
   
   Otherwise, generate new secrets:
   ```bash
   ./scripts/generate_secrets.sh
   ```

4. **Configure environment variables**
   ```bash
   cp .env.template .env
   # Edit .env file with your settings
   ```

5. **Deploy SceneScape**
   
   Option A - Using the deployment script (recommended for beginners):
   ```bash
   ./scripts/deploy.sh
   ```
   
   Option B - Direct deployment (for experienced users):
   ```bash
   docker compose up -d
   ```
   
   The `deploy.sh` script performs validation checks and provides helpful output, but you can deploy directly with Docker Compose if you prefer.

6. **Access the web interface**
   - Open https://localhost:443 in your browser
   - Use the superuser password displayed during deployment

## Minimal Deployment (Experienced Users)

For experienced users who want the quickest deployment:

```bash
cd scenescape-deployment-[timestamp]
./scripts/load_images.sh  # Only if images/ directory exists
cp .env.template .env     # Edit with your values
docker compose up -d
```

Note: This skips validation checks. Ensure your `.env` file is properly configured and all required secrets are in place.

## Manual Setup

If you prefer to set up manually:

### 1. Load Docker Images (Optional)

If the package includes Docker images for offline deployment:
```bash
./scripts/load_images.sh
```

### 2. Configure Environment Variables

Copy `.env.template` to `.env` and configure:

```bash
VERSION=latest
UID=$(id -u)
GID=$(id -g)
SECRETSDIR=./manager/secrets
SUPASS=your_superuser_password
DBROOT=your_database_root_password

### 3. Set up Secrets

If secrets are not already included in the package, either run `./scripts/generate_secrets.sh` or manually create the required files in the `manager/secrets/` directory. See `manager/secrets/README.md` for details.

### 4. Start Services

Option A - Using the deployment script (performs validation):
```bash
./scripts/deploy.sh
```

Option B - Direct Docker Compose (requires manual validation):
```bash
export $(cat .env | xargs)
docker compose up -d
```

The `deploy.sh` script is optional but recommended as it validates your environment setup and provides helpful status information.

## Directory Structure

```
scenescape-deployment-[timestamp]/
├── docker-compose.yml          # Main Docker Compose configuration
├── .env.template              # Environment variables template
├── dlstreamer-pipeline-server/ # DL Streamer configuration files
├── configs/                   # Service configuration files
├── manager/secrets/          # Security credentials (populate before use)
├── images/                   # Docker images (optional, for offline deployment)
├── volumes/                  # Saved Docker volumes (optional, for offline deployment)
├── scripts/                  # Deployment and utility scripts
│   ├── generate_secrets.sh   # Generate certificates and auth tokens
│   ├── load_images.sh        # Load Docker images and restore volumes (if included)
│   └── deploy.sh             # Automated deployment script
└── README.md                 # This file
```

## Services

The deployment includes the following services:
- Web interface (port 443)
- MQTT broker 
- PostgreSQL database
- Scene controller
- Media server (RTSP)
- DL Streamer pipelines (ports 8080, 8081)
- Camera calibration service
- NTP server

## Offline Deployment

If the package includes Docker images (in the `images/` directory), this enables offline deployment without internet access:

1. The `load_images.sh` script will load all required Docker images from the saved tar files
2. Any saved Docker volumes will be restored automatically
3. No internet connection is required for the deployment process
4. All necessary components are included in the package

If the package does not include images, Docker will pull them from the registry during deployment (internet connection required).

## Troubleshooting

### Check service status
```bash
docker compose ps
```

### View logs
```bash
docker compose logs [service_name]
```

### Stop all services
```bash
docker compose down
```

### Remove all data (careful!)
```bash
docker compose down -v
```

## Security Notes

- The generated certificates are self-signed for development use
- Change default passwords before production deployment
- Ensure proper firewall configuration for production use
- Consider using a reverse proxy for SSL termination in production

## Support

For issues and questions, refer to the main SceneScape documentation.
EOF
else
    echo "DRY RUN: would create README.md"
fi

# Save Docker images (optional, for air-gapped deployments)
read -p "Do you want to save Docker images for offline deployment? This will significantly increase package size. (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Extracting image names from docker-compose.yml..."
    if [ "$DRY_RUN" -eq 0 ]; then
        mkdir -p "${PACKAGE_DIR}/images"
    fi

    # Extract image names from docker-compose.yml
    IMAGES=$(grep -E "^\s*image:" "${COMPOSE_FILE}" | awk '{print $2}' | sort -u)
    
    # Add alpine image for offline volume restoration (used by load_images.sh)
    IMAGES="$IMAGES alpine:latest"
    
    # Process images and replace ${VERSION:-latest} with actual version
    PROCESSED_IMAGES=""
    for image in $IMAGES; do
        if [[ "$image" == *'${VERSION:-latest}'* ]]; then
            # Get VERSION from .env file if it exists
            if [ -f ".env" ]; then
                VERSION=$(grep "^VERSION=" .env | cut -d'=' -f2)
            fi
            # Use latest if VERSION is empty or not found
            VERSION=${VERSION:-latest}
            # Replace the variable with actual version
            processed_image=$(echo "$image" | sed "s/\${VERSION:-latest}/$VERSION/g")
            PROCESSED_IMAGES="$PROCESSED_IMAGES $processed_image"
        else
            PROCESSED_IMAGES="$PROCESSED_IMAGES $image"
        fi
    done
    IMAGES="$PROCESSED_IMAGES"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo_info "DRY RUN: images that would be saved:"
        for image in $IMAGES; do
            echo " - $image"
        done
    else
        echo_info "Saving Docker images..."
        for image in $IMAGES; do
            # Replace special characters in filename
            safe_name=$(echo "$image" | tr '/' '_' | tr ':' '_')
            echo_info "Saving $image as ${safe_name}.tar..."
            docker save "$image" > "${PACKAGE_DIR}/images/${safe_name}.tar"
        done

        # Create image loading script (also restores saved volumes if present)
        cat > "${PACKAGE_DIR}/scripts/load_images.sh" << 'EOF'
#!/bin/bash
# Script to load Docker images from saved tar files and restore saved Docker volumes

set -e

IMAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/images"
VOLUMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/volumes"
SAVE_RESTORE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/save_restore.sh"

if [ ! -d "$IMAGES_DIR" ]; then
    echo "Images directory not found: $IMAGES_DIR"
else
    echo "Loading Docker images..."
    for tar_file in "$IMAGES_DIR"/*.tar; do
        if [ -f "$tar_file" ]; then
            echo "Loading $(basename "$tar_file")..."
            docker load < "$tar_file"
        fi
    done
    echo "All images loaded successfully!"
fi

# Restore saved volumes if any
if [ -d "$VOLUMES_DIR" ] && [ -n "$(ls -A "$VOLUMES_DIR" 2>/dev/null)" ]; then
    echo "Restoring Docker volumes from: $VOLUMES_DIR"
    
    # Check if save_restore.sh exists in the package
    if [ -f "$SAVE_RESTORE_SCRIPT" ] && [ -x "$SAVE_RESTORE_SCRIPT" ]; then
        echo "Using save_restore.sh to restore volumes..."
        if "$SAVE_RESTORE_SCRIPT" restore --dir "$VOLUMES_DIR"; then
            echo "Volumes restored successfully using save_restore.sh"
        else
            echo "Warning: save_restore.sh failed to restore volumes, falling back to manual restore"
            # Fallback to manual restore
            manual_restore=true
        fi
    else
        echo "save_restore.sh not found, using manual volume restore..."
        manual_restore=true
    fi
    
    # Manual restore fallback (original logic)
    if [ "${manual_restore:-false}" = "true" ]; then
        for vol_archive in "$VOLUMES_DIR"/*.tar.gz; do
            if [ -f "$vol_archive" ]; then
                base=$(basename "$vol_archive")
                vol_name="${base%.tar.gz}"
                echo "Restoring volume: $vol_name from $base"
                # Create the volume if it doesn't exist
                if ! docker volume inspect "$vol_name" >/dev/null 2>&1; then
                    echo "Creating Docker volume: $vol_name"
                    docker volume create "$vol_name"
                fi
                # Extract archive into the volume using a temporary container
                docker run --rm -v "${vol_name}:/volume" -v "$VOLUMES_DIR:/backup" alpine sh -c \
                    "cd /volume && tar -xzf /backup/$base || true"
            fi
        done
        echo "Manual volume restore complete."
    fi
else
    echo "No volumes directory found or directory is empty, skipping volume restore"
fi
EOF
        chmod +x "${PACKAGE_DIR}/scripts/load_images.sh"
    fi

    # Save Docker volumes using save_restore.sh
    echo_info "Saving Docker volumes using save_restore.sh..."
    
    if [ "$DRY_RUN" -eq 1 ]; then
        # For dry-run, we'll simulate what save_restore.sh would do
        if [ -f "tools/save-restore/save_restore.sh" ]; then
            echo_info "DRY RUN: would use save_restore.sh to save volumes from ${COMPOSE_FILE}"
            # Try to show what volumes would be saved
            if command -v yq >/dev/null 2>&1; then
                VOLUME_NAMES=$(yq e '.volumes // {} | keys | .[]' "${COMPOSE_FILE}" 2>/dev/null | tr '\n' ' ')
            elif command -v docker >/dev/null 2>&1 && docker compose -f "${COMPOSE_FILE}" config --format json >/dev/null 2>&1; then
                if command -v jq >/dev/null 2>&1; then
                    VOLUME_NAMES=$(docker compose -f "${COMPOSE_FILE}" config --format json | jq -r '.volumes // {} | keys[]' 2>/dev/null | tr '\n' ' ')
                fi
            fi
            if [ -n "$VOLUME_NAMES" ]; then
                echo_info "DRY RUN: would save volumes: $VOLUME_NAMES"
            else
                echo_info "DRY RUN: would attempt to detect volumes from compose file"
            fi
        else
            echo_warn "DRY RUN: save_restore.sh not found, would skip volume saving"
        fi
    else
        mkdir -p "${PACKAGE_DIR}/volumes"
        if [ -f "tools/save-restore/save_restore.sh" ] && [ -x "tools/save-restore/save_restore.sh" ]; then
            # Use save_restore.sh to save volumes
            echo_info "Using save_restore.sh to save volumes..."
            if tools/save-restore/save_restore.sh save --dir "${PACKAGE_DIR}/volumes" --compose-file "${COMPOSE_FILE}"; then
                echo_info "Volumes saved successfully using save_restore.sh"
            else
                echo_warn "save_restore.sh failed to save volumes"
            fi
        else
            echo_warn "save_restore.sh not found or not executable, skipping volume save"
        fi
    fi

    if [ "$DRY_RUN" -eq 0 ]; then
        echo_info "Docker images and volumes saved. Use ./scripts/load_images.sh on target machine to load them."
    else
        echo_info "DRY RUN: would have saved images and volumes as listed above."
    fi
fi

# Create the final package
echo_info "Creating package archive..."
if [ "$DRY_RUN" -eq 0 ]; then
    cd "$(dirname "${PACKAGE_DIR}")"
    tar -czf "${PACKAGE_NAME}.tar.gz" "$(basename "${PACKAGE_DIR}")"

    echo_info "Cleaning up temporary directory..."
    rm -rf "${PACKAGE_DIR}"
else
    echo "DRY RUN: would create ${PACKAGE_NAME}.tar.gz and clean up temporary directory"
fi

echo ""
echo "====================================================================="
echo_info "Deployment package created successfully!"
echo_info "Package location: ${SCRIPT_DIR}/${PACKAGE_NAME}.tar.gz"
echo ""
echo_info "To deploy on target machine:"
echo_info "1. Copy ${PACKAGE_NAME}.tar.gz to target machine"
echo_info "2. tar -xzf ${PACKAGE_NAME}.tar.gz"
echo_info "3. cd ${PACKAGE_NAME}"
echo_info "4. Follow instructions in README.md"
echo "====================================================================="
