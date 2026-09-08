#!/bin/bash
# DockEasy Install / Update / Uninstall Script
# Usage:
#   curl -sSL https://sirajli.dev/dockeasy/install.sh | bash
#   DOCKEASY_VERSION=v0.1.2 bash install.sh
#   bash install.sh --version v0.1.2
#   bash install.sh update [--version v0.1.2]
#   bash install.sh uninstall
#   bash install.sh restore --restore-file=/root/dockeasy-db.dump [--yes]

set -e

# ─── Constants ───────────────────────────────────────────────────────────────
BASE_URL="https://sirajli.dev/dockeasy"
GHCR_OWNER="elvin0802"
DOCKEASY_DIR="/etc/dockeasy"
COMPOSE_FILE="$DOCKEASY_DIR/docker-compose.prod.yml"
ENV_FILE="$DOCKEASY_DIR/.env"
TRAEFIK_DYNAMIC_DIR="$DOCKEASY_DIR/traefik/dynamic"
# Docker-out-of-Docker working dirs — host bind mounts at identical container paths.
# The API container writes cloned code / generated compose files here and asks the host
# daemon to build/compose against them, so host and container paths must match.
APPLICATIONS_DIR="/dockeasy/applications"
BACKUPS_DIR="/dockeasy/backups"
SYSTEM_BACKUPS_DIR="/dockeasy/backups/system"
DEPLOY_LOGS_DIR="/dockeasy/deploy-logs"
VOLUME_EXPLORER_HELPER_IMAGE="busybox:1.36"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { printf "${BLUE}[DockEasy]${NC} %s\n" "$*" >&2; }
success() { printf "${GREEN}[DockEasy]${NC} %s\n" "$*" >&2; }
warn()    { printf "${YELLOW}[DockEasy]${NC} %s\n" "$*" >&2; }
error()   { printf "${RED}[DockEasy] ERROR:${NC} %s\n" "$*" >&2; exit 1; }

# ─── Version Detection ───────────────────────────────────────────────────────
detect_version() {
    local ver="${DOCKEASY_VERSION:-}"

    # Check --version flag
    while [ $# -gt 0 ]; do
        if [ "$1" = "--version" ] && [ -n "$2" ]; then
            ver="$2"
            break
        fi
        shift
    done

    if [ -z "$ver" ]; then
        info "Detecting latest stable version..."
        ver=$(curl -fsSL "$BASE_URL/version.json" 2>/dev/null | \
            sed -n 's/.*"platform"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        if [ -z "$ver" ]; then
            warn "Could not detect latest version, using 'latest' tag."
            ver="latest"
        else
            info "Latest version: $ver"
        fi
    fi

    echo "$ver"
}

# ─── Common Checks ───────────────────────────────────────────────────────────
check_root() {
    [ "$(id -u)" = "0" ] || error "This script must be run as root."
}

check_linux() {
    [ "$(uname -s)" = "Linux" ] || error "DockEasy only supports Linux."
    if [ -f "/.dockerenv" ]; then
        error "Cannot install inside a Docker container."
    fi
}

install_docker_if_missing() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker is already installed: $(docker --version)"
        return
    fi
    info "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    success "Docker installed."
}

check_docker_compose() {
    docker compose version >/dev/null 2>&1 || \
        error "Docker Compose plugin not found. Please update Docker to a version that includes 'docker compose'."
}

ensure_volume_explorer_helper_image() {
    if docker image inspect "$VOLUME_EXPLORER_HELPER_IMAGE" >/dev/null 2>&1; then
        info "Volume Explorer helper image is already available: $VOLUME_EXPLORER_HELPER_IMAGE"
        return
    fi

    info "Pulling Volume Explorer helper image: $VOLUME_EXPLORER_HELPER_IMAGE"
    docker pull "$VOLUME_EXPLORER_HELPER_IMAGE" || \
        error "Failed to pull Volume Explorer helper image ($VOLUME_EXPLORER_HELPER_IMAGE). Run: docker pull $VOLUME_EXPLORER_HELPER_IMAGE"
}

check_ports() {
    for port in 80 443; do
        if ss -tulnp 2>/dev/null | grep -q ":${port} "; then
            error "Port $port is already in use. Please free it before installing DockEasy."
        fi
    done
}

get_public_ip() {
    local ip=""
    ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null) ||
    ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null) ||
    ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)

    if [ -z "$ip" ]; then
        ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null) ||
        ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
    fi

    if [ -z "$ip" ]; then
        warn "Could not detect public IP. Using 'localhost' as fallback."
        ip="localhost"
    fi
    echo "$ip"
}

generate_secret() {
    openssl rand -hex "$1" 2>/dev/null || \
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c $(($1 * 2)) || \
    error "Failed to generate a random secret. Install openssl and retry."
}

# ─── Download Helpers ─────────────────────────────────────────────────────────
download_compose_file() {
    local url="$BASE_URL/docker-compose.prod.yml"
    info "Downloading docker-compose.prod.yml..."
    curl -fsSL "$url" -o "$COMPOSE_FILE" || \
        error "Failed to download docker-compose.prod.yml from $url"
}

# ─── Traefik Initial Config ───────────────────────────────────────────────────
write_traefik_dynamic_config() {
    cat > "$TRAEFIK_DYNAMIC_DIR/system.yml" <<'EOF'
# DockEasy system routing — managed by DockEasy, do not edit manually.
# This file is updated automatically when you configure a domain in the dashboard.
http:
  routers:
    dockeasy-api:
      rule: "PathPrefix(`/api`) || PathPrefix(`/hubs`) || PathPrefix(`/swagger`)"
      service: dockeasy-api-svc
      entryPoints: [web]
      priority: 20
    dockeasy-web:
      rule: "PathPrefix(`/`)"
      service: dockeasy-web-svc
      entryPoints: [web]
      priority: 1
  services:
    dockeasy-api-svc:
      loadBalancer:
        servers:
          - url: "http://dockeasy-api:8080"
    dockeasy-web-svc:
      loadBalancer:
        servers:
          - url: "http://dockeasy-web:3000"
EOF
    info "Traefik dynamic config written."
}

# ─── Install ──────────────────────────────────────────────────────────────────
install_dockeasy() {
    local version="$1"
    shift || true

    info "Installing DockEasy $version..."

    check_root
    check_linux
    check_ports
    install_docker_if_missing
    check_docker_compose
    ensure_volume_explorer_helper_image

    local server_ip
    server_ip=$(get_public_ip)
    info "Server IP detected: $server_ip"

    local pg_password jwt_secret auth_secret
    pg_password=$(generate_secret 32)
    jwt_secret=$(generate_secret 64)
    auth_secret=$(generate_secret 32)

    # Create directories
    mkdir -p "$DOCKEASY_DIR" "$TRAEFIK_DYNAMIC_DIR" "$DOCKEASY_DIR/traefik/acme"
    chmod 700 "$DOCKEASY_DIR"

    # Docker-out-of-Docker working dirs (host bind mounts; see docker-compose.prod.yml).
    # Docker would auto-create these on first `up`, but explicit creation keeps
    # ownership/permissions predictable and documented.
    mkdir -p "$APPLICATIONS_DIR" "$BACKUPS_DIR" "$SYSTEM_BACKUPS_DIR" "$DEPLOY_LOGS_DIR"

    # Write .env
    cat > "$ENV_FILE" <<EOF
# DockEasy configuration — generated by install.sh
# Do not edit manually unless you know what you are doing.

DOCKEASY_VERSION=$version
SERVER_IP=$server_ip

# Database
POSTGRES_DB=dockeasy
POSTGRES_USER=dockeasy
POSTGRES_PASSWORD=$pg_password

# API secrets
JWT_SECRET=$jwt_secret
AUTH_SECRET=$auth_secret
JWT_ISSUER=DockEasy
JWT_AUDIENCE=DockEasy

# Internal URLs (used by web for SSR)
API_INTERNAL_URL=http://dockeasy-api:8080

# Let's Encrypt email — set via DockEasy dashboard when configuring HTTPS domain.
# Leave empty to issue certs without expiry notification emails.
ACME_EMAIL=

# Image tags (overridden by version selection)
DOCKEASY_API_IMAGE=ghcr.io/$GHCR_OWNER/dockeasy-api:$version
DOCKEASY_WEB_IMAGE=ghcr.io/$GHCR_OWNER/dockeasy-web:$version
EOF
    chmod 600 "$ENV_FILE"
    info "Environment file written to $ENV_FILE"

    write_traefik_dynamic_config
    download_compose_file "$version"

    info "Pulling Docker images..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

    info "Starting DockEasy..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

    echo ""
    success "DockEasy $version is installed!"
    printf "${YELLOW}Access your dashboard at: http://${server_ip}${NC}\n"
    printf "${BLUE}First-time setup: go to http://${server_ip}/auth/setup to create your admin account.${NC}\n\n"
    printf "To configure a custom domain, use the dashboard after initial setup.\n"
    printf "To update: curl -sSL $BASE_URL/install.sh | sh -s update\n"
    printf "To uninstall: curl -sSL $BASE_URL/install.sh | sh -s uninstall\n\n"
}

# ─── Update ───────────────────────────────────────────────────────────────────
update_dockeasy() {
    local version="$1"

    check_root
    [ -f "$COMPOSE_FILE" ] || error "DockEasy is not installed. Run install first."
    [ -f "$ENV_FILE" ]     || error "Environment file not found at $ENV_FILE"

    info "Updating DockEasy to $version..."

    # Update image tags in .env
    sed -i "s|^DOCKEASY_API_IMAGE=.*|DOCKEASY_API_IMAGE=ghcr.io/$GHCR_OWNER/dockeasy-api:$version|" "$ENV_FILE"
    sed -i "s|^DOCKEASY_WEB_IMAGE=.*|DOCKEASY_WEB_IMAGE=ghcr.io/$GHCR_OWNER/dockeasy-web:$version|" "$ENV_FILE"
    sed -i "s|^DOCKEASY_VERSION=.*|DOCKEASY_VERSION=$version|" "$ENV_FILE"

    download_compose_file "$version"

    # Ensure persistent host bind mount directories exist before applying refreshed compose.
    mkdir -p "$BACKUPS_DIR" "$SYSTEM_BACKUPS_DIR" "$DEPLOY_LOGS_DIR"
    ensure_volume_explorer_helper_image

    info "Pulling new images..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

    info "Restarting containers..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans

    success "DockEasy updated to $version!"
}

# ─── Uninstall ────────────────────────────────────────────────────────────────
uninstall_dockeasy() {
    check_root

    if [ ! -f "$COMPOSE_FILE" ]; then
        warn "DockEasy does not appear to be installed (compose file not found)."
        exit 0
    fi

    warn "This will stop and remove all DockEasy containers."
    printf "Remove database volumes and deployed app data too? This will DELETE all data\n"
    printf "(database, cloned repos in %s, backups in %s, deploy logs in %s). [y/N]: " "$APPLICATIONS_DIR" "$BACKUPS_DIR" "$DEPLOY_LOGS_DIR"
    read -r remove_volumes

    info "Stopping DockEasy containers..."
    if [ "$remove_volumes" = "y" ] || [ "$remove_volumes" = "Y" ]; then
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down -v 2>/dev/null || true
        # These are now host bind mounts (not named volumes), so `down -v` does not touch them.
        rm -rf "$APPLICATIONS_DIR" "$BACKUPS_DIR" "$DEPLOY_LOGS_DIR"
        warn "Database volumes and deployed app data removed."
    else
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down 2>/dev/null || true
        info "Database volumes and deployed app data kept ($APPLICATIONS_DIR, $BACKUPS_DIR, $DEPLOY_LOGS_DIR)."
    fi

    rm -rf "$DOCKEASY_DIR"
    success "DockEasy uninstalled."
}

# ─── Restore ─────────────────────────────────────────────────────────────────
restore_dockeasy() {
    check_root
    [ -f "$COMPOSE_FILE" ] || error "DockEasy is not installed. Run install first."
    [ -f "$ENV_FILE" ]     || error "Environment file not found at $ENV_FILE"

    local restore_file=""
    local assume_yes="false"

    while [ $# -gt 0 ]; do
        case "$1" in
            --restore-file=*)
                restore_file="${1#*=}"
                ;;
            --restore-file)
                [ $# -ge 2 ] || error "Missing value for --restore-file."
                shift
                restore_file="${1:-}"
                ;;
            --yes|-y)
                assume_yes="true"
                ;;
            *)
                error "Unknown restore option: $1. Use: restore --restore-file=<absolute path> [--yes]"
                ;;
        esac
        shift || true
    done

    [ -n "$restore_file" ] || error "Missing --restore-file=<path>."
    [ -f "$restore_file" ] || error "Restore file not found: $restore_file"

    # shellcheck disable=SC1090
    . "$ENV_FILE"
    POSTGRES_DB="${POSTGRES_DB:-dockeasy}"
    POSTGRES_USER="${POSTGRES_USER:-dockeasy}"

    mkdir -p "$SYSTEM_BACKUPS_DIR"

    warn "This will overwrite the current DockEasy database."
    warn "The target /etc/dockeasy/.env must contain the same JWT_SECRET used when this backup was created."
    warn "If JWT_SECRET does not match, encrypted env variables and tokens cannot be recovered."

    if [ "$assume_yes" != "true" ]; then
        printf "Continue restoring %s into %s? [y/N]: " "$restore_file" "$POSTGRES_DB"
        read -r confirm_restore
        if [ "$confirm_restore" != "y" ] && [ "$confirm_restore" != "Y" ]; then
            error "Restore cancelled."
        fi
    fi

    local timestamp safety_dump
    timestamp=$(date -u +"%Y-%m-%dT%H-%M-%S")
    safety_dump="$SYSTEM_BACKUPS_DIR/pre-restore-$timestamp.dump"

    info "Creating safety backup of the current database..."
    if docker exec dockeasy-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$safety_dump"; then
        success "Safety backup written to $safety_dump"
    else
        warn "Could not create safety backup. Continuing because restore was explicitly requested."
        rm -f "$safety_dump"
    fi

    info "Stopping DockEasy API and Web containers..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" stop dockeasy-api dockeasy-web

    info "Restoring database from $restore_file..."
    if ! docker exec -i dockeasy-db pg_restore --clean --if-exists -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$restore_file"; then
        warn "Restore failed. Starting DockEasy containers again before exiting."
        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d || true
        error "Database restore failed."
    fi

    info "Starting DockEasy containers..."
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

    success "DockEasy database restored."
    warn "Existing browser/mobile sessions may be invalid. Sign in again."
}

# ─── Entry Point ──────────────────────────────────────────────────────────────
COMMAND="${1:-install}"
[ "$COMMAND" = "install" ] || [ "$COMMAND" = "update" ] || [ "$COMMAND" = "uninstall" ] || [ "$COMMAND" = "restore" ] || \
    error "Unknown command: $COMMAND. Use: install | update | uninstall | restore"

shift || true
VERSION=""
if [ "$COMMAND" = "install" ] || [ "$COMMAND" = "update" ]; then
    VERSION=$(detect_version "$@")
fi

case "$COMMAND" in
    install)   install_dockeasy   "$VERSION" "$@" ;;
    update)    update_dockeasy    "$VERSION" ;;
    uninstall) uninstall_dockeasy ;;
    restore)   restore_dockeasy   "$@" ;;
esac
