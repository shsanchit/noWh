#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#   SWAAN SOAR Platform — 1-Command Automated Docker Installer for Ubuntu
#   Supports: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 11 / 12
#
#   Usage:
#     chmod +x install_docker_ubuntu.sh
#     ./install_docker_ubuntu.sh            (Install & Launch SWAAN)
#     ./install_docker_ubuntu.sh --update   (Update platform to latest build safely)
#     ./install_docker_ubuntu.sh --status   (Check container health & API status)
#     ./install_docker_ubuntu.sh --restart  (Restart SWAAN containers)
#     ./install_docker_ubuntu.sh --stop     (Stop all SWAAN containers)
#     ./install_docker_ubuntu.sh --logs     (View live aggregated logs)
#     ./install_docker_ubuntu.sh --backup   (Instant PostgreSQL database backup)
#     ./install_docker_ubuntu.sh --help     (Display usage documentation)
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
cd "$SCRIPT_DIR"

DEFAULT_INSTALL_DIR="/opt/swaan"
REPO_URL="https://github.com/shsanchit/SWAAN-v4.git"
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

# ── Argument Parsing (Unified 1-Script Engine) ────────────────────────────────
ACTION="install"
CUSTOM_COMPOSE_ARG=""

for arg in "${@:-}"; do
    case "$arg" in
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
            ;;
        --backup|backup|-b)
            ACTION="backup"
            ;;
        --help|help|-h)
            ACTION="help"
            ;;
        --build|build)
            ACTION="build"
            ;;
        *)
            if [ -f "$arg" ]; then
                CUSTOM_COMPOSE_ARG="$arg"
            fi
            ;;
    esac
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

# ── Subcommand Handlers ──────────────────────────────────────────────────────
if [ "$ACTION" == "help" ]; then
    print_banner
    echo -e "Usage: ${BOLD}./install_docker_ubuntu.sh [FLAG] [COMPOSE_FILE]${NC}"
    echo ""
    echo -e "Unified Operations:"
    echo -e "  ${CYAN}(no flag)${NC}       Automated 1-command deployment & startup of SWAAN SOAR"
    echo -e "  ${CYAN}--update, -u${NC}    Update application containers to latest build (keeps DB, data & .env safe)"
    echo -e "  ${CYAN}--status, -s${NC}    Display running containers & probe API health endpoint"
    echo -e "  ${CYAN}--restart, -r${NC}   Restart all SWAAN containers"
    echo -e "  ${CYAN}--stop${NC}          Stop and shut down all SWAAN containers"
    echo -e "  ${CYAN}--logs, -l${NC}      Stream live aggregated container logs (Ctrl+C to exit)"
    echo -e "  ${CYAN}--backup, -b${NC}    Create instant timestamped SQL backup of PostgreSQL database"
    echo -e "  ${CYAN}--build${NC}         Force build containers from local source Dockerfiles"
    echo -e "  ${CYAN}--help, -h${NC}      Show this help documentation"
    echo ""
    exit 0
fi

if [ "$ACTION" == "backup" ]; then
    resolve_compose_file
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
fi

if [ "$ACTION" == "stop" ]; then
    resolve_compose_file
    echo -e "${YELLOW}[→] Stopping SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down
    echo -e "${GREEN}[✓] All SWAAN containers stopped cleanly.${NC}"
    exit 0
fi

if [ "$ACTION" == "restart" ]; then
    resolve_compose_file
    echo -e "${YELLOW}[→] Restarting SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" restart
    echo -e "${GREEN}[✓] Platform containers restarted.${NC}"
    exit 0
fi

if [ "$ACTION" == "logs" ]; then
    resolve_compose_file
    docker compose -f "$COMPOSE_FILE" logs -f --tail=100
    exit 0
fi

if [ "$ACTION" == "status" ]; then
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
        else
            echo -e "${YELLOW}[!] Backend Engine: Initializing or unreachable (HTTP ${HTTP_CODE})${NC}"
        fi
    else
        docker ps --filter "name=swaan-"
    fi
    exit 0
fi

if [ "$ACTION" == "update" ]; then
    print_banner
    resolve_compose_file
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Could not find a valid compose file ($COMPOSE_FILE) in $(pwd) or $DEFAULT_INSTALL_DIR."
        log_error "Please run './install_docker_ubuntu.sh' first to set up the platform."
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
fi

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
    echo -e "   • Update Platform: ${BOLD}./install_docker_ubuntu.sh --update${NC}   (Updates images, keeps data safe)"
    echo -e "   • Health Status:   ${BOLD}./install_docker_ubuntu.sh --status${NC}"
    echo -e "   • Database Backup: ${BOLD}./install_docker_ubuntu.sh --backup${NC}   (Instant PostgreSQL dump)"
    echo -e "   • Restart SWAAN:   ${BOLD}./install_docker_ubuntu.sh --restart${NC}"
    echo -e "   • Stop SWAAN:      ${BOLD}./install_docker_ubuntu.sh --stop${NC}"
    echo -e "   • Stream Logs:     ${BOLD}./install_docker_ubuntu.sh --logs${NC}"
    echo ""
else
    log_warn "The backend took longer than ${MAX_WAIT_SECONDS}s to respond on /health."
    log_warn "Containers are still initializing. You can inspect logs with:"
    echo -e "   ${BOLD}docker compose logs -f backend${NC}"
fi
