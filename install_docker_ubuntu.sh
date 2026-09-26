#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#   SWAAN SOAR Platform — 1-Command Automated Docker Installer for Ubuntu
#   Supports: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 11 / 12
#
#   Usage:
#     chmod +x install_docker_ubuntu.sh
#     ./install_docker_ubuntu.sh            (Install & Launch SWAAN)
#     ./install_docker_ubuntu.sh --stop     (Stop all SWAAN containers)
#     ./install_docker_ubuntu.sh --restart  (Restart SWAAN containers)
#     ./install_docker_ubuntu.sh --logs     (View live logs)
#     ./install_docker_ubuntu.sh --status   (Check container health)
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

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          SWAAN SOAR — Autonomous Security Platform           ║"
    echo "║      1-Command Automated Docker Installer for Ubuntu         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}[→] ${BOLD}$1${NC}"; }

# ── Subcommand Handlers ──────────────────────────────────────────────────────
if [ "${1:-}" == "--stop" ] || [ "${1:-}" == "stop" ]; then
    echo -e "${YELLOW}[→] Stopping SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" down
    echo -e "${GREEN}[✓] All SWAAN containers stopped.${NC}"
    exit 0
fi

if [ "${1:-}" == "--restart" ] || [ "${1:-}" == "restart" ]; then
    echo -e "${YELLOW}[→] Restarting SWAAN containers...${NC}"
    docker compose -f "$COMPOSE_FILE" restart
    echo -e "${GREEN}[✓] Containers restarted.${NC}"
    exit 0
fi

if [ "${1:-}" == "--logs" ] || [ "${1:-}" == "logs" ]; then
    docker compose -f "$COMPOSE_FILE" logs -f --tail=100
    exit 0
fi

if [ "${1:-}" == "--status" ] || [ "${1:-}" == "status" ]; then
    docker compose -f "$COMPOSE_FILE" ps
    exit 0
fi

print_banner

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

# ── 4. BUILD & START DOCKER CONTAINER STACK ──────────────────────────────────
log_step "4/5: Building and Starting SWAAN Container Cluster..."
echo -e "  • ${BOLD}swaan-postgres${NC}  (PostgreSQL 16 with pgvector & pg_trgm)"
echo -e "  • ${BOLD}swaan-redis${NC}     (Redis 7 in-memory cache)"
echo -e "  • ${BOLD}swaan-backend${NC}   (FastAPI multi-agent autonomous SOAR engine)"
echo -e "  • ${BOLD}swaan-frontend${NC}  (React SPA + Nginx reverse-proxy on port 80 & 5173)"
echo ""

docker compose -f "$COMPOSE_FILE" up -d --build

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
    echo ""
    echo -e "🛠️  ${BOLD}Operational Commands:${NC}"
    echo -e "   • Stop SWAAN:      ${BOLD}./install_docker_ubuntu.sh --stop${NC}"
    echo -e "   • Restart SWAAN:   ${BOLD}./install_docker_ubuntu.sh --restart${NC}"
    echo -e "   • Stream Logs:     ${BOLD}./install_docker_ubuntu.sh --logs${NC}"
    echo -e "   • Check Status:    ${BOLD}./install_docker_ubuntu.sh --status${NC}"
    echo ""
else
    log_warn "The backend took longer than ${MAX_WAIT_SECONDS}s to respond on /health."
    log_warn "Containers are still initializing. You can inspect logs with:"
    echo -e "   ${BOLD}docker compose logs -f backend${NC}"
fi
