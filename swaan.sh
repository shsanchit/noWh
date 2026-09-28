#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#   SWAAN SOAR Platform — Enterprise 1-Script Lifecycle & Service Orchestrator
#   Supports: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 11 / 12
#
#   Usage:
#     chmod +x swaan.sh
#     ./swaan.sh            (Install & Launch SWAAN SOAR)
#     ./swaan.sh --update   (Update platform to latest build safely)
#     ./swaan.sh --status   (Check container health & API status)
#     ./swaan.sh --restart  (Restart SWAAN containers)
#     ./swaan.sh --stop     (Stop all SWAAN containers)
#     ./swaan.sh --logs     (View live aggregated logs)
#     ./swaan.sh --backup   (Instant PostgreSQL database backup)
#     ./swaan.sh --debug    (Run deep system diagnostics)
#     ./swaan.sh --help     (Display usage documentation)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Color Definitions ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR"

DEFAULT_INSTALL_DIR="/opt/swaan"
REPO_URL="https://github.com/shsanchit/SWAAN-v4.git"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

# ── Configuration & State Detection ──────────────────────────────────────────
SERVICE_FILE="/etc/systemd/system/swaan.service"

# ── Argument Parsing (Unified Enterprise Operations Engine) ──────────────────
ACTION="install"
CUSTOM_COMPOSE_ARG=""
PURGE_ARG=false
FORCE_INSTALL=false

while [ $# -gt 0 ]; do
    case "$1" in
        --update|update|-u)
            ACTION="update"
            ;;
        --status|status|-s)
            ACTION="status"
            ;;
        --restart|restart|-r)
            ACTION="restart"
            ;;
        --stop|stop)
            ACTION="stop"
            ;;
        --logs|logs|-l)
            ACTION="logs"
            if [ $# -gt 1 ] && [[ "$2" != -* ]] && [ ! -f "$2" ]; then
                LOG_TARGET="$2"
                shift
            fi
            ;;
        --backup|backup|-b)
            ACTION="backup"
            ;;
        --debug|debug|--diagnostics|diag|-d)
            ACTION="debug"
            ;;
        --uninstall|uninstall)
            ACTION="uninstall"
            ;;
        --purge)
            PURGE_ARG=true
            ;;
        --install-service)
            ACTION="install_service"
            ;;
        --remove-service)
            ACTION="remove_service"
            ;;
        --service)
            ACTION="service"
            ;;
        --shell)
            ACTION="shell"
            ;;
        --db-shell)
            ACTION="db_shell"
            ;;
        --export-logs)
            ACTION="export_logs"
            ;;
        --prune)
            ACTION="prune"
            ;;
        --reset-admin)
            ACTION="reset_admin"
            ;;
        --force|-f|--force-install|--reinstall)
            FORCE_INSTALL=true
            ACTION="force_install"
            ;;
        --help|help|-h)
            ACTION="help"
            ;;
        --build|build)
            ACTION="build"
            ;;
        *)
            if [ -f "$1" ]; then
                CUSTOM_COMPOSE_ARG="$1"
            fi
            ;;
    esac
    shift
done

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          SWAAN SOAR — Autonomous Security Platform           ║"
    echo "║      1-Command Automated Docker Installer & Manager          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}[→] ${BOLD}$1${NC}"; }

resolve_compose_file() {
    if [ -n "$CUSTOM_COMPOSE_ARG" ] && [ -f "$CUSTOM_COMPOSE_ARG" ]; then
        COMPOSE_FILE="$CUSTOM_COMPOSE_ARG"
        return
    fi
    if [ -f "docker-compose.prod.yml" ]; then
        COMPOSE_FILE="docker-compose.prod.yml"
    elif [ -f "docker-compose.yml" ]; then
        COMPOSE_FILE="docker-compose.yml"
    elif [ -f "$DEFAULT_INSTALL_DIR/docker-compose.prod.yml" ]; then
        cd "$DEFAULT_INSTALL_DIR"
        COMPOSE_FILE="docker-compose.prod.yml"
    elif [ -f "$DEFAULT_INSTALL_DIR/docker-compose.yml" ]; then
        cd "$DEFAULT_INSTALL_DIR"
        COMPOSE_FILE="docker-compose.yml"
    else
        # Auto-detect compose file from running container label
        local DETECTED_FILE
        DETECTED_FILE=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' swaan-backend 2>/dev/null || docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' swaan-postgres 2>/dev/null || true)
        if [ -n "$DETECTED_FILE" ] && [ -f "$DETECTED_FILE" ]; then
            COMPOSE_FILE="$DETECTED_FILE"
            cd "$(dirname "$COMPOSE_FILE")"
        fi
    fi
}

is_swaan_installed() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker ps -a --filter "name=swaan-backend" --format '{{.Names}}' 2>/dev/null | grep -q "swaan-backend"; then
            return 0
        fi
        if docker ps -a --filter "name=swaan-postgres" --format '{{.Names}}' 2>/dev/null | grep -q "swaan-postgres"; then
            return 0
        fi
    fi
    if [ -f "$DEFAULT_INSTALL_DIR/.env" ] && { [ -f "$DEFAULT_INSTALL_DIR/docker-compose.yml" ] || [ -f "$DEFAULT_INSTALL_DIR/docker-compose.prod.yml" ]; }; then
        return 0
    fi
    if [ -f ".env" ] && { [ -f "docker-compose.yml" ] || [ -f "docker-compose.prod.yml" ]; } && [ "$SCRIPT_DIR" != "/" ] && [ "$SCRIPT_DIR" != "/root" ]; then
        return 0
    fi
    return 1
}

# ── Operational Functions ────────────────────────────────────────────────────
execute_update() {
    print_banner
    resolve_compose_file
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Could not find a valid compose file ($COMPOSE_FILE) in $(pwd) or $DEFAULT_INSTALL_DIR."
        log_error "Please run './${SCRIPT_NAME}' first to set up the platform."
        exit 1
    fi

    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     SWAAN Platform Update — Safe Seamless Image Refresh      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Target Compose File : ${BOLD}${COMPOSE_FILE}${NC}"
    log_info "Working Directory   : ${BOLD}$(pwd)${NC}"
    echo ""
    echo -e "${GREEN}Configuration & Persistent Storage Safeguards:${NC}"
    echo -e "  [✓] Database Volumes (pgdata)   : 100% Preserved (PostgreSQL tables & data untouched)"
    echo -e "  [✓] Cache Volumes (redisdata)   : 100% Preserved"
    echo -e "  [✓] Environment File (.env)     : 100% Preserved (passwords & API keys untouched)"
    echo -e "  [✓] Tenant Configurations       : 100% Preserved (stored safely in database)"
    echo -e "  [✓] Updating Only               : swaan-backend & swaan-frontend containers"
    echo ""

    log_step "1/4: Pulling latest application images from Docker Hub..."
    docker compose -f "$COMPOSE_FILE" pull backend frontend 2>/dev/null || docker compose -f "$COMPOSE_FILE" pull

    log_step "2/4: Recreating updated containers (zero database downtime)..."
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

    log_step "3/4: Cleaning up stale/dangling image layers..."
    docker image prune -f >/dev/null 2>&1 || true

    log_step "4/4: Verifying platform health..."
    MAX_WAIT=45
    ELAPSED=0
    HEALTHY=false
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" == "200" ]; then
            HEALTHY=true
            break
        fi
        HTTP_CODE_NGINX=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/health 2>/dev/null || echo "000")
        if [ "$HTTP_CODE_NGINX" == "200" ]; then
            HEALTHY=true
            break
        fi
        printf "  ⏳ Waiting for updated backend to initialize... (%ds/%ds)\r" "$ELAPSED" "$MAX_WAIT"
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    echo ""

    HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    if [ "$HEALTHY" = true ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ SWAAN Updated Successfully to Latest Build!               ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "🌐 Web Console:  ${BOLD}${CYAN}http://${HOST_IP}${NC} (or http://localhost)"
        echo -e "🔑 Status:       Healthy (HTTP 200)"
        echo -e "📦 All configurations, tenant settings, and incident data intact."
    else
        log_warn "Containers refreshed. Finalizing startup. Inspect live logs with:"
        echo -e "    ${BOLD}docker compose -f $COMPOSE_FILE logs -f backend${NC}"
    fi
    exit 0
}

execute_status() {
    resolve_compose_file
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║             SWAAN Platform Container Status                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    if [ -f "$COMPOSE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" ps
        echo ""
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" == "200" ]; then
            echo -e "${GREEN}[✓] Backend Engine: HEALTHY (HTTP 200 on /health)${NC}"
            VERSION_DATA=$(curl -s http://127.0.0.1:8000/api/system/version 2>/dev/null || echo "")
            if [ -n "$VERSION_DATA" ]; then
                echo -e "    Version info: $VERSION_DATA"
            fi
        else
            echo -e "${YELLOW}[!] Backend Engine: Initializing or unreachable (HTTP ${HTTP_CODE})${NC}"
        fi
    else
        docker ps --filter "name=swaan-"
    fi
    exit 0
}

execute_restart() {
    resolve_compose_file
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Compose file ($COMPOSE_FILE) not found."
        exit 1
    fi
    echo -e "${YELLOW}[→] Restarting SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" restart
    echo -e "${GREEN}[✓] Platform containers restarted.${NC}"
    exit 0
}

execute_stop() {
    resolve_compose_file
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Compose file ($COMPOSE_FILE) not found."
        exit 1
    fi
    echo -e "${YELLOW}[→] Stopping SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down
    echo -e "${GREEN}[✓] All SWAAN containers stopped cleanly.${NC}"
    exit 0
}

execute_logs() {
    resolve_compose_file
    local TARGET="${LOG_TARGET:-}"
    if [ ! -f "$COMPOSE_FILE" ]; then
        if [ -n "$TARGET" ]; then
            echo -e "${CYAN}[→] Streaming logs for container: ${BOLD}swaan-${TARGET}${NC} (Ctrl+C to stop)..."
            docker logs -f --tail=100 "swaan-$TARGET" 2>/dev/null || docker logs -f --tail=100 "$TARGET"
        else
            echo -e "${CYAN}[→] Streaming logs for ${BOLD}swaan-backend${NC} (Ctrl+C to stop)..."
            docker logs -f --tail=100 swaan-backend 2>/dev/null || docker ps --filter "name=swaan-"
        fi
        exit 0
    fi

    if [ -n "$TARGET" ]; then
        echo -e "${CYAN}[→] Streaming live logs for service: ${BOLD}${TARGET}${NC} (Ctrl+C to stop)..."
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100 "$TARGET"
    else
        echo -e "${CYAN}[→] Streaming aggregated live logs for all SWAAN services (Ctrl+C to stop)..."
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100
    fi
    exit 0
}

execute_backup() {
    resolve_compose_file
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Compose file ($COMPOSE_FILE) not found. PostgreSQL container must be running."
        exit 1
    fi
    BACKUP_FILE="swaan_backup_$(date +%Y%m%d_%H%M%S).sql"
    echo -e "${CYAN}[→] Creating PostgreSQL database backup to ${BACKUP_FILE}...${NC}"
    if docker compose -f "$COMPOSE_FILE" exec -T db pg_dump -U postgres soar_intelligence > "$BACKUP_FILE"; then
        if [ -s "$BACKUP_FILE" ]; then
            echo -e "${GREEN}[✓] Database backup successfully created: ${BOLD}${BACKUP_FILE}${NC} ($(du -h "$BACKUP_FILE" | cut -f1))"
        else
            echo -e "${RED}[✗] Backup file was empty. Ensure database container is running.${NC}"
            rm -f "$BACKUP_FILE"
            exit 1
        fi
    else
        echo -e "${RED}[✗] Failed to execute database backup.${NC}"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
    exit 0
}

_run_diagnostic_checks() {
    log_step "1. Host & Operating System Environment"
    echo -e "  • Hostname:        $(hostname)"
    echo -e "  • Architecture:    $(uname -m)"
    echo -e "  • Kernel Version:  $(uname -r)"
    echo -e "  • OS Release:      $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || uname -s)"
    echo -e "  • Current User:    $(whoami) (UID: ${EUID:-$(id -u)})"
    echo -e "  • Uptime:          $(uptime -p 2>/dev/null || uptime)"

    log_step "2. Compute & Memory Resources"
    if command -v free >/dev/null 2>&1; then
        echo -e "  • Memory (RAM):"
        free -h | sed 's/^/      /'
    fi
    echo -e "  • Disk Space:"
    df -h . | head -2 | sed 's/^/      /'

    log_step "3. Docker Engine & Virtualization"
    if command -v docker >/dev/null 2>&1; then
        echo -e "  • Docker Binary:   $(which docker)"
        echo -e "  • Docker Version:  $(docker --version)"
        echo -e "  • Compose Version: $(docker compose version 2>/dev/null || echo 'Not installed')"
        if docker info >/dev/null 2>&1; then
            echo -e "  • Daemon Status:   Running (Healthy)"
            echo -e "  • Storage Driver:  $(docker info --format '{{.Driver}}' 2>/dev/null || echo 'N/A')"
        else
            echo -e "  • Daemon Status:   ${RED}STOPPED or Permission Denied${NC}"
        fi
    else
        echo -e "  • Docker Binary:   ${RED}NOT FOUND${NC}"
    fi

    log_step "4. Platform Network Port Availability"
    for port in 80 443 5432 6379 8000 5173; do
        local STATUS="Unknown"
        if command -v ss >/dev/null 2>&1; then
            if ss -tuln 2>/dev/null | grep -q ":$port "; then
                STATUS="${YELLOW}BOUND / IN-USE${NC}"
            else
                STATUS="${GREEN}AVAILABLE${NC}"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                STATUS="${YELLOW}BOUND / IN-USE${NC}"
            else
                STATUS="${GREEN}AVAILABLE${NC}"
            fi
        elif command -v lsof >/dev/null 2>&1; then
            if lsof -i :$port >/dev/null 2>&1; then
                STATUS="${YELLOW}BOUND / IN-USE${NC}"
            else
                STATUS="${GREEN}AVAILABLE${NC}"
            fi
        fi
        echo -e "  • Port $port: $STATUS"
    done

    log_step "5. Container Cluster Inspection"
    if [ -f "$COMPOSE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" ps --all 2>&1 || true
    else
        docker ps --filter "name=swaan-" 2>&1 || true
    fi

    log_step "6. Database & Cache Health Check"
    if docker ps --filter "name=swaan-postgres" --format '{{.Names}}' 2>/dev/null | grep -q "swaan-postgres"; then
        PG_PING=$(docker exec swaan-postgres pg_isready -U postgres 2>&1 || echo "Failed")
        echo -e "  • PostgreSQL:      $PG_PING"
    else
        echo -e "  • PostgreSQL:      ${YELLOW}Container not running${NC}"
    fi

    if docker ps --filter "name=swaan-redis" --format '{{.Names}}' 2>/dev/null | grep -q "swaan-redis"; then
        REDIS_PING=$(docker exec swaan-redis redis-cli ping 2>&1 || echo "Failed")
        echo -e "  • Redis Cache:     $REDIS_PING"
    else
        echo -e "  • Redis Cache:     ${YELLOW}Container not running${NC}"
    fi

    log_step "7. REST API Engine & HTTP Latency Probe"
    local START_MS END_MS LATENCY LATENCY_UNIT
    if command -v python3 >/dev/null 2>&1; then
        START_MS=$(python3 -c "import time; print(int(time.time()*1000))")
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health 2>/dev/null || echo "000")
        END_MS=$(python3 -c "import time; print(int(time.time()*1000))")
        LATENCY=$((END_MS - START_MS))
        LATENCY_UNIT="ms"
    else
        START_MS=$(date +%s)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health 2>/dev/null || echo "000")
        END_MS=$(date +%s)
        LATENCY=$((END_MS - START_MS))
        LATENCY_UNIT="s"
    fi

    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "  • API Endpoint:    ${GREEN}HTTP 200 OK${NC} (${LATENCY}${LATENCY_UNIT})"
        VERSION_DATA=$(curl -s http://127.0.0.1:8000/api/system/version 2>/dev/null || echo "")
        if [ -n "$VERSION_DATA" ]; then
            echo -e "  • Version Info:    $VERSION_DATA"
        fi
    else
        echo -e "  • API Endpoint:    ${RED}HTTP $HTTP_CODE (Offline or Unreachable)${NC}"
    fi

    log_step "8. Recent Engine Warnings & Errors (Last 50 Lines)"
    if docker ps --filter "name=swaan-backend" --format '{{.Names}}' 2>/dev/null | grep -q "swaan-backend"; then
        docker logs --tail=50 swaan-backend 2>&1 | grep -iE "error|exception|traceback|fail" | tail -10 | sed 's/^/      /' || echo "      (No recent errors detected in log tail)"
    else
        echo -e "      (Backend container not running)"
    fi
}

execute_debug() {
    print_banner
    resolve_compose_file
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         SWAAN Deep System & Environment Diagnostics          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local DIAG_LOG="swaan_diag_$(date +%Y%m%d_%H%M%S).log"
    echo "Saving full report to: $DIAG_LOG"

    _run_diagnostic_checks 2>&1 | tee "$DIAG_LOG"

    echo ""
    echo -e "${GREEN}✓ Diagnostic scan completed. Full report saved to: ${BOLD}${DIAG_LOG}${NC}"
    exit 0
}

execute_uninstall() {
    print_banner
    resolve_compose_file
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║            SWAAN Platform Uninstaller                        ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_warn "This will stop and remove all SWAAN containers and network bridges."
    echo ""

    # Offer to create pre-uninstall safety backup
    if [ -f "$COMPOSE_FILE" ] && docker compose -f "$COMPOSE_FILE" ps --services 2>/dev/null | grep -q "db"; then
        BACKUP_UNINSTALL="swaan_pre_uninstall_$(date +%Y%m%d_%H%M%S).sql"
        echo -e "${CYAN}[→] Creating safety database backup to ${BACKUP_UNINSTALL}...${NC}"
        docker compose -f "$COMPOSE_FILE" exec -T db pg_dump -U postgres soar_intelligence > "$BACKUP_UNINSTALL" 2>/dev/null || true
        if [ -s "$BACKUP_UNINSTALL" ]; then
            log_info "Safety database backup created: ${BACKUP_UNINSTALL}"
        else
            rm -f "$BACKUP_UNINSTALL"
        fi
    fi

    # Determine whether to purge data volumes
    PURGE_DATA=false
    if [ "$PURGE_ARG" = true ]; then
        PURGE_DATA=true
    elif [ -t 0 ]; then
        read -rp "Do you also want to permanently DELETE database volumes and configs? (y/N): " PURGE_CONFIRM
        if [[ "$PURGE_CONFIRM" =~ ^[Yy]$ ]]; then
            PURGE_DATA=true
        fi
    fi

    # 1. Stop and remove systemd service if installed
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${CYAN}[→] Removing systemd service (swaan.service)...${NC}"
        if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
            sudo systemctl stop swaan 2>/dev/null || true
            sudo systemctl disable swaan 2>/dev/null || true
            sudo rm -f "$SERVICE_FILE"
            sudo systemctl daemon-reload
        elif [ "$EUID" -eq 0 ]; then
            systemctl stop swaan 2>/dev/null || true
            systemctl disable swaan 2>/dev/null || true
            rm -f "$SERVICE_FILE"
            systemctl daemon-reload
        fi
        log_info "systemd service removed."
    fi

    # 2. Stop and remove docker containers
    if [ -f "$COMPOSE_FILE" ]; then
        if [ "$PURGE_DATA" = true ]; then
            echo -e "${RED}[→] Stopping containers and purging all persistent data volumes...${NC}"
            docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
            log_info "Containers and persistent volumes purged."
        else
            echo -e "${YELLOW}[→] Stopping and removing containers (preserving persistent volumes)...${NC}"
            docker compose -f "$COMPOSE_FILE" down --remove-orphans
            log_info "Containers removed. Persistent volumes (pgdata, redisdata) preserved."
        fi
    fi

    # 3. Clean up directory if purged
    if [ "$PURGE_DATA" = true ]; then
        if [ "$(pwd)" == "$DEFAULT_INSTALL_DIR" ]; then
            cd /
            rm -rf "$DEFAULT_INSTALL_DIR"
            log_info "Removed directory $DEFAULT_INSTALL_DIR"
        fi
        echo -e "${GREEN}[✓] SWAAN has been completely uninstalled from this host.${NC}"
    else
        echo -e "${GREEN}[✓] SWAAN containers stopped and removed.${NC}"
        echo -e "${CYAN}Note: Your database data and .env file are intact. To reinstall, simply run: ./${SCRIPT_NAME}${NC}"
    fi
    exit 0
}

execute_install_service() {
    resolve_compose_file
    SUDO=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else log_error "Root or sudo required."; exit 1; fi
    fi
    WORK_DIR="$(pwd)"
    DOCKER_BIN="$(command -v docker || echo "/usr/bin/docker")"

    echo -e "${CYAN}[→] Creating native systemd service: ${BOLD}swaan.service${NC}..."
    cat << EOF | $SUDO tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=SWAAN SOAR Autonomous Security Platform
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$WORK_DIR
ExecStart=$DOCKER_BIN compose -f $COMPOSE_FILE up -d
ExecStop=$DOCKER_BIN compose -f $COMPOSE_FILE down
ExecReload=$DOCKER_BIN compose -f $COMPOSE_FILE restart
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

    $SUDO systemctl daemon-reload
    $SUDO systemctl enable swaan.service
    log_info "SWAAN systemd service created and enabled at: ${SERVICE_FILE}"
    echo -e "You can now manage SWAAN via systemctl:"
    echo -e "  • ${BOLD}systemctl status swaan${NC}"
    echo -e "  • ${BOLD}systemctl start swaan${NC}"
    echo -e "  • ${BOLD}systemctl stop swaan${NC}"
    echo -e "  • ${BOLD}systemctl restart swaan${NC}"
    exit 0
}

execute_remove_service() {
    SUDO=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else log_error "Root or sudo required."; exit 1; fi
    fi
    echo -e "${YELLOW}[→] Disabling and removing swaan.service...${NC}"
    $SUDO systemctl stop swaan 2>/dev/null || true
    $SUDO systemctl disable swaan 2>/dev/null || true
    $SUDO rm -f "$SERVICE_FILE"
    $SUDO systemctl daemon-reload
    log_info "swaan.service removed successfully."
    exit 0
}

execute_service() {
    if [ -f "$SERVICE_FILE" ]; then
        systemctl status swaan --no-pager
    else
        log_warn "swaan.service is not installed. Install with: ./${SCRIPT_NAME} --install-service"
    fi
    exit 0
}

execute_shell() {
    resolve_compose_file
    echo -e "${CYAN}[→] Launching interactive shell in swaan-backend container...${NC}"
    docker compose -f "$COMPOSE_FILE" exec backend bash 2>/dev/null || docker compose -f "$COMPOSE_FILE" exec backend sh
    exit 0
}

execute_db_shell() {
    resolve_compose_file
    echo -e "${CYAN}[→] Launching PostgreSQL psql shell in swaan-postgres container...${NC}"
    docker compose -f "$COMPOSE_FILE" exec db psql -U postgres -d soar_intelligence
    exit 0
}

execute_export_logs() {
    resolve_compose_file
    LOG_EXPORT="swaan_logs_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${CYAN}[→] Exporting platform container logs to ${LOG_EXPORT}...${NC}"
    docker compose -f "$COMPOSE_FILE" logs --no-color > "$LOG_EXPORT"
    log_info "Logs successfully exported: ${LOG_EXPORT} ($(du -h "$LOG_EXPORT" | cut -f1))"
    exit 0
}

execute_prune() {
    echo -e "${CYAN}[→] Pruning unused Docker images, dangling layers, and build caches...${NC}"
    docker image prune -f
    docker builder prune -f >/dev/null 2>&1 || true
    log_info "Docker environment cleaned successfully."
    exit 0
}

execute_reset_admin() {
    resolve_compose_file
    echo -e "${CYAN}[→] Verifying and restoring default superadmin credentials...${NC}"
    if docker compose -f "$COMPOSE_FILE" exec -T backend python seed.py --no-demo 2>/dev/null; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✓ Default Superadmin Access Restored!                       ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo -e "   • Username: ${YELLOW}admin${NC} or ${YELLOW}superadmin${NC}"
        echo -e "   • Password: ${YELLOW}Password123!${NC}"
    else
        log_error "Could not run reset inside container. Ensure backend container is running."
    fi
    exit 0
}

# ── Subcommand Dispatcher ────────────────────────────────────────────────────
case "$ACTION" in
    help)
        print_banner
        echo -e "Usage: ${BOLD}./${SCRIPT_NAME} [COMMAND / FLAG] [COMPOSE_FILE]${NC}"
        echo ""
        echo -e "Core Lifecycle Operations:"
        echo -e "  ${CYAN}(no flag)${NC}          1-command automated deployment (prevents overwrite if already installed)"
        echo -e "  ${CYAN}--update, -u${NC}       Safely update backend & frontend images (preserves DB, volumes & .env)"
        echo -e "  ${CYAN}--status, -s${NC}       Check container cluster health and REST API status"
        echo -e "  ${CYAN}--restart, -r${NC}      Restart all SWAAN platform containers"
        echo -e "  ${CYAN}--stop${NC}             Stop and halt all platform containers"
        echo -e "  ${CYAN}--uninstall${NC}        Cleanly uninstall SWAAN (with option to preserve or purge data)"
        echo -e "  ${CYAN}--force-install, -f${NC} Force complete re-installation from scratch"
        echo ""
        echo -e "Diagnostics & Administration:"
        echo -e "  ${CYAN}--debug, -d${NC}        Deep diagnostic audit (OS, RAM, ports, Docker, PostgreSQL & API latency)"
        echo -e "  ${CYAN}--logs, -l${NC}         Stream live aggregated container logs (Ctrl+C to stop)"
        echo -e "  ${CYAN}--export-logs${NC}      Export container logs into a timestamped file for troubleshooting"
        echo -e "  ${CYAN}--backup, -b${NC}       Create instant SQL backup of the PostgreSQL database"
        echo -e "  ${CYAN}--reset-admin${NC}      Restore default Super Admin credentials (admin / Password123!)"
        echo -e "  ${CYAN}--shell${NC}            Drop into an interactive shell inside swaan-backend"
        echo -e "  ${CYAN}--db-shell${NC}         Open interactive PostgreSQL psql prompt in swaan-postgres"
        echo -e "  ${CYAN}--prune${NC}            Clean up dangling Docker images and build layer caches"
        echo ""
        echo -e "systemd Service Management (Auto-Start on Boot):"
        echo -e "  ${CYAN}--install-service${NC}  Register swaan.service in systemd for automatic startup on host boot"
        echo -e "  ${CYAN}--service${NC}          Check systemd service status (systemctl status swaan)"
        echo -e "  ${CYAN}--remove-service${NC}   Unregister and delete swaan.service"
        echo ""
        exit 0
        ;;
    update)
        execute_update
        exit 0
        ;;
    status)
        execute_status
        exit 0
        ;;
    restart)
        execute_restart
        exit 0
        ;;
    stop)
        execute_stop
        exit 0
        ;;
    logs)
        execute_logs
        exit 0
        ;;
    backup)
        execute_backup
        exit 0
        ;;
    debug)
        execute_debug
        exit 0
        ;;
    uninstall)
        execute_uninstall
        exit 0
        ;;
    install_service)
        execute_install_service
        exit 0
        ;;
    remove_service)
        execute_remove_service
        exit 0
        ;;
    service)
        execute_service
        exit 0
        ;;
    shell)
        execute_shell
        exit 0
        ;;
    db_shell)
        execute_db_shell
        exit 0
        ;;
    export_logs)
        execute_export_logs
        exit 0
        ;;
    prune)
        execute_prune
        exit 0
        ;;
    reset_admin)
        execute_reset_admin
        exit 0
        ;;
    install)
        # Check if already installed to prevent accidental wipe or re-run
        if is_swaan_installed && [ "$FORCE_INSTALL" != "true" ]; then
            print_banner
            echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║  [!] SWAAN SOAR Platform is Already Installed on This Host   ║${NC}"
            echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            resolve_compose_file
            RUNNING_COUNT=$(docker ps --filter "name=swaan-" --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
            if [ "$RUNNING_COUNT" -gt 0 ]; then
                log_info "Status: ${BOLD}${RUNNING_COUNT} active SWAAN containers running${NC}"
            else
                log_warn "Status: SWAAN containers exist but are currently stopped"
            fi
            echo ""
            echo -e "To prevent accidental overwrite of existing databases and tenant configs,"
            echo -e "please choose an operational action:"
            echo ""
            echo -e "  ${BOLD}1)${NC} ${CYAN}Update Platform${NC}       - Pull latest images, keep DB & .env 100% safe (--update)"
            echo -e "  ${BOLD}2)${NC} ${CYAN}Platform Status${NC}       - Inspect container cluster & API health (--status)"
            echo -e "  ${BOLD}3)${NC} ${CYAN}Restart Platform${NC}      - Restart all containers (--restart)"
            echo -e "  ${BOLD}4)${NC} ${CYAN}Stream Logs${NC}           - Live aggregated container logs (--logs)"
            echo -e "  ${BOLD}5)${NC} ${CYAN}Deep Diagnostics${NC}      - Full OS, ports, Docker, DB & API audit (--debug)"
            echo -e "  ${BOLD}6)${NC} ${CYAN}Backup Database${NC}       - Instant PostgreSQL snapshot (--backup)"
            echo -e "  ${BOLD}7)${NC} ${CYAN}Re-install SWAAN${NC}      - Force reinstall / re-deploy (--force-install)"
            echo -e "  ${BOLD}8)${NC} ${RED}Uninstall SWAAN${NC}       - Clean removal of SWAAN (--uninstall)"
            echo -e "  ${BOLD}9)${NC} ${BOLD}Exit${NC}"
            echo ""

            if [ -t 0 ]; then
                read -rp "Enter choice [1-9]: " MENU_CHOICE
                case "$MENU_CHOICE" in
                    1) execute_update; exit 0 ;;
                    2) execute_status; exit 0 ;;
                    3) execute_restart; exit 0 ;;
                    4) execute_logs; exit 0 ;;
                    5) execute_debug; exit 0 ;;
                    6) execute_backup; exit 0 ;;
                    7) log_info "Proceeding with forced reinstallation..." ;;
                    8) execute_uninstall; exit 0 ;;
                    *) echo -e "${CYAN}Operation cancelled. Exiting.${NC}"; exit 0 ;;
                esac
            else
                echo -e "${YELLOW}Notice: Non-interactive session detected. Preventing overwrite.${NC}"
                echo -e "To update:          ${BOLD}./${SCRIPT_NAME} --update${NC}"
                echo -e "To check status:    ${BOLD}./${SCRIPT_NAME} --status${NC}"
                echo -e "To force reinstall: ${BOLD}./${SCRIPT_NAME} --force-install${NC}"
                echo -e "To uninstall:       ${BOLD}./${SCRIPT_NAME} --uninstall${NC}"
                exit 0
            fi
        fi
        ;;
    force_install|build)
        log_info "Proceeding with platform installation..."
        ;;
esac

# If docker-compose.yml is not in current dir, but already exists in /opt/swaan, switch to it
if [ ! -f "$COMPOSE_FILE" ] && [ -f "$DEFAULT_INSTALL_DIR/$COMPOSE_FILE" ]; then
    cd "$DEFAULT_INSTALL_DIR"
    SCRIPT_DIR="$DEFAULT_INSTALL_DIR"
fi

print_banner

# ── Resolve Workspace Directory & Compose File ──────────────────────────────
if [ ! -f "$COMPOSE_FILE" ]; then
    # If in root or system directory, default to /opt/swaan
    if [ "$SCRIPT_DIR" == "/" ] || [ "$SCRIPT_DIR" == "/root" ]; then
        INSTALL_DIR="/opt/swaan"
        mkdir -p "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        SCRIPT_DIR="$INSTALL_DIR"
        log_info "Running in server installation directory: ${SCRIPT_DIR}"
    fi

    # Check if docker-compose.prod.yml exists
    if [ -f "docker-compose.prod.yml" ]; then
        COMPOSE_FILE="docker-compose.prod.yml"
    elif [ ! -f "$COMPOSE_FILE" ]; then
        log_info "Generating production docker-compose.yml configured for Docker Hub registry (sanchit80)..."
        cat << 'COMPOSE_EOF' > "$COMPOSE_FILE"
version: '3.8'

services:
  db:
    image: pgvector/pgvector:pg16
    container_name: swaan-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-Password123!}
      POSTGRES_DB: ${POSTGRES_DB:-soar_intelligence}
    ports:
      - "5432:5432"
    volumes:
      - swaan_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: swaan-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - swaan_redisdata:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  backend:
    image: sanchit80/swaan-backend:latest
    container_name: swaan-backend
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD:-Password123!}@db:5432/${POSTGRES_DB:-soar_intelligence}?sslmode=disable
      - REDIS_URL=redis://redis:6379/0
    ports:
      - "8000:8000"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  frontend:
    image: sanchit80/swaan-frontend:latest
    container_name: swaan-frontend
    restart: unless-stopped
    ports:
      - "80:80"
      - "5173:80"
    depends_on:
      - backend

volumes:
  swaan_pgdata:
  swaan_redisdata:
COMPOSE_EOF
        log_info "Created production docker-compose.yml"
    fi
fi

# ── 1. OS & PERMISSION VERIFICATION ──────────────────────────────────────────
log_step "1/5: Checking Operating System & Privileges..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
    log_info "Detected OS: ${NAME} (${VERSION_ID})"
else
    OS_NAME="$(uname -s)"
    log_warn "Non-standard Linux distribution detected: ${OS_NAME}"
fi

# ── 2. DOCKER & DOCKER COMPOSE INSTALLATION ──────────────────────────────────
log_step "2/5: Verifying Docker Engine & Docker Compose Plugin..."

install_docker_ubuntu() {
    log_warn "Docker is not installed. Installing Docker Engine from official repository..."
    
    # Needs sudo/root
    SUDO=""
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            log_error "Please run this script as root or install sudo."
            exit 1
        fi
    fi

    $SUDO apt-get update -y
    $SUDO apt-get install -y ca-certificates curl gnupg lsb-release

    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker service
    $SUDO systemctl enable --now docker

    # Add current user to docker group if running under non-root
    if [ "$EUID" -ne 0 ]; then
        $SUDO usermod -aG docker "$USER" || true
    fi

    log_info "Docker Engine and Docker Compose installed successfully."
}

if ! command -v docker >/dev/null 2>&1; then
    install_docker_ubuntu
else
    log_info "Docker is already installed: $(docker --version)"
fi

# Ensure Docker Compose plugin is available
if ! docker compose version >/dev/null 2>&1; then
    log_warn "Docker Compose plugin missing. Installing docker-compose-plugin..."
    sudo apt-get update -y && sudo apt-get install -y docker-compose-plugin
fi
log_info "Docker Compose is ready: $(docker compose version)"

# Ensure Docker daemon is accessible
if ! docker info >/dev/null 2>&1; then
    if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        sudo systemctl start docker
    else
        log_error "Docker daemon is not running. Please start docker ('sudo systemctl start docker')."
        exit 1
    fi
fi

# ── 3. ENVIRONMENT & CONFIGURATION GENERATION ────────────────────────────────
log_step "3/5: Verifying Platform Environment Configuration (.env)..."

if [ ! -f "$ENV_FILE" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example "$ENV_FILE"
        log_info "Copied .env.example to .env"
    else
        # Generate secure random cryptographic secret
        RANDOM_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || openssl rand -hex 32 2>/dev/null || echo "swaan-enterprise-secret-key-32bytes-long")
        cat << ENV_EOF > "$ENV_FILE"
# ── PostgreSQL Database Credentials ──
POSTGRES_USER=postgres
POSTGRES_PASSWORD=Password123!
POSTGRES_DB=soar_intelligence
DATABASE_URL=postgresql://postgres:Password123!@db:5432/soar_intelligence?sslmode=disable

# ── Redis Cache ──
REDIS_URL=redis://redis:6379/0

# ── Multi-Tenant Deployment Mode (enterprise | standalone) ──
SWAAN_DEPLOYMENT_MODE=enterprise
SWAAN_DEFAULT_ORG_ID=default
SWAAN_DEFAULT_TENANT_ID=default

# ── Security & Authentication ──
SECRET_KEY=${RANDOM_SECRET}
ACCESS_TOKEN_EXPIRE_HOURS=24
PORT=8000
HOST=0.0.0.0

# ── Cryptographic Platform License (Enterprise POC Valid) ──
SWAAN_LICENSE_SECRET=swaan_super_secret_key_998877
SWAAN_LICENSE_KEY=eyJwYXlsb2FkIjogeyJsaWNlbnNlX2lkIjogIlNXQUFOLURFVi0wMDEiLCAib3JnYW5pemF0aW9uIjogIlNXQUFOIERldmVsb3BtZW50IiwgInRpZXIiOiAiZW50ZXJwcmlzZSIsICJtYXhfc2VhdHMiOiA1MCwgIm1heF9pbmNpZGVudHNfZGFpbHkiOiAxMDAwLCAibWF4X2FnZW50cyI6IDIwLCAiZmVhdHVyZXMiOiBbInNvYXIiLCAidGhyZWF0X2ludGVsIiwgIm1zc3AiLCAiYWlfYWdlbnRzIiwgImNvbXBsaWFuY2UiXSwgImlzc3VlZF9hdCI6ICIyMDI2LTA2LTEyVDE0OjU5OjM1LjY2MzIyNiswMDowMCIsICJleHBpcmVzX2F0IjogIjIwMjctMDYtMTJUMTQ6NTk6MzUuNjYzNzA0KzAwOjAwIn0sICJzaWduYXR1cmUiOiAiMjRjMmE3ZGM5MWNlYWI3NjJkYjMwNDlhYTgxM2UxNWFhYTU3MTc0NGNmNGUwMzgzNjE4ZTNiODAwMmIxNmNlNyJ9

# ── AI LLM Providers (Configure here or live in Web Settings) ──
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
DEEPSEEK_API_KEY=

# ── Threat Intelligence API Keys (Optional) ──
ABUSEIPDB_API_KEY=
VIRUSTOTAL_API_KEY=
SHODAN_API_KEY=
OTX_API_KEY=
URLSCAN_API_KEY=
THREATFOX_API_KEY=
IPINFO_TOKEN=
ENV_EOF
        log_info "Generated default production .env with secure random keys."
    fi
else
    log_info "Existing .env configuration found."
fi

# ── 4. PULL & START DOCKER CONTAINER STACK ──────────────────────────────────
log_step "4/5: Deploying SWAAN Container Cluster..."
echo -e "  • ${BOLD}swaan-postgres${NC}  (PostgreSQL 16 with pgvector & pg_trgm)"
echo -e "  • ${BOLD}swaan-redis${NC}     (Redis 7 in-memory cache)"
echo -e "  • ${BOLD}swaan-backend${NC}   (FastAPI multi-agent autonomous SOAR engine)"
echo -e "  • ${BOLD}swaan-frontend${NC}  (React SPA + Nginx reverse-proxy on port 80 & 5173)"
echo ""

if [ "${1:-}" == "--build" ] && [ -f "Dockerfile.backend" ]; then
    log_info "Building containers locally from source code..."
    docker compose -f "$COMPOSE_FILE" up -d --build
else
    log_info "Pulling container images from Docker Hub..."
    docker compose -f "$COMPOSE_FILE" pull || true
    docker compose -f "$COMPOSE_FILE" up -d
fi

log_info "All containers successfully launched in background."

# ── 5. HEALTH CHECK & DATABASE INITIALIZATION POLLING ─────────────────────────
log_step "5/5: Verifying Engine Initialization & Health Status..."

MAX_WAIT_SECONDS=60
ELAPSED=0
HEALTHY=false

while [ $ELAPSED -lt $MAX_WAIT_SECONDS ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "200" ]; then
        HEALTHY=true
        break
    fi
    printf "  ⏳ Waiting for database schemas, RLS migrations & AI agents to initialize... (%ds/%ds)\r" "$ELAPSED" "$MAX_WAIT_SECONDS"
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

echo ""

# Get Host IP address for user convenience
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

if [ "$HEALTHY" = true ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ SWAAN SOAR Platform is Fully Operational!                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "🌐 ${BOLD}Access SWAAN in your Browser:${NC}"
    echo -e "   • Primary Web Console: ${BOLD}${CYAN}http://${HOST_IP}${NC}  (or http://localhost)"
    echo -e "   • Direct Dev Port:     ${BOLD}${CYAN}http://${HOST_IP}:5173${NC}"
    echo -e "   • API Health Status:   ${BOLD}http://${HOST_IP}:8000/health${NC}"
    echo -e "   • Interactive Swagger: ${BOLD}http://${HOST_IP}:8000/docs${NC}"
    echo ""
    echo -e "🔑 ${BOLD}Default Super Admin & User Logins:${NC}"
    echo -e "   ┌──────────────────┬─────────────────┬─────────────────┐"
    echo -e "   │ Role             │ Username        │ Password        │"
    echo -e "   ├──────────────────┼─────────────────┼─────────────────┤"
    echo -e "   │ Super Admin      │ ${YELLOW}admin${NC}           │ ${YELLOW}Password123!${NC}    │"
    echo -e "   │ Super Admin      │ ${YELLOW}superadmin${NC}      │ ${YELLOW}Password123!${NC}    │"
    echo -e "   │ Org Admin (MSSP) │ ${YELLOW}orgadmin${NC}        │ ${YELLOW}Password123!${NC}    │"
    echo -e "   │ Analyst L2       │ ${YELLOW}analyst${NC}         │ ${YELLOW}Password123!${NC}    │"
    echo -e "   │ Read-Only Viewer │ ${YELLOW}viewer${NC}          │ ${YELLOW}Password123!${NC}    │"
    echo -e "   └──────────────────┴─────────────────┴─────────────────┘"
    echo -e "🛠️  ${BOLD}Unified Platform Operations (1-Script Management):${NC}"
    echo -e "   • Update Platform:    ${BOLD}./${SCRIPT_NAME} --update${NC}          (Updates images, keeps data safe)"
    echo -e "   • Health Status:      ${BOLD}./${SCRIPT_NAME} --status${NC}          (Checks cluster & API health)"
    echo -e "   • Deep Diagnostics:   ${BOLD}./${SCRIPT_NAME} --debug${NC}           (Full OS, network & DB audit)"
    echo -e "   • Database Backup:    ${BOLD}./${SCRIPT_NAME} --backup${NC}          (Instant PostgreSQL dump)"
    echo -e "   • Register Service:   ${BOLD}./${SCRIPT_NAME} --install-service${NC} (Auto-starts on server boot)"
    echo -e "   • Restart SWAAN:      ${BOLD}./${SCRIPT_NAME} --restart${NC}"
    echo -e "   • Stop SWAAN:         ${BOLD}./${SCRIPT_NAME} --stop${NC}"
    echo -e "   • Stream Logs:        ${BOLD}./${SCRIPT_NAME} --logs${NC}"
    echo -e "   • Uninstall SWAAN:    ${BOLD}./${SCRIPT_NAME} --uninstall${NC}       (Safe uninstall wizard)"
    echo ""
else
    log_warn "The backend took longer than ${MAX_WAIT_SECONDS}s to respond on /health."
    log_warn "Containers are still initializing. You can inspect logs with:"
    echo -e "   ${BOLD}docker compose logs -f backend${NC}"
fi
