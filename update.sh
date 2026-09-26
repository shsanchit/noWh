#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  update.sh — SWAAN Universal Platform Update Engine
#  Supports: Docker-based deployments & Native host deployments
# ══════════════════════════════════════════════════════════════════════════════

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}       SWAAN SOAR Platform — Automated System Update            ${NC}"
echo -e "${CYAN}================================================================${NC}"

# ── Detect if Docker deployment is running ───────────────────────────────────
DOCKER_RUNNING=false
COMPOSE_FILE=""

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if [ -f "docker-compose.prod.yml" ]; then
        COMPOSE_FILE="docker-compose.prod.yml"
        DOCKER_RUNNING=true
    elif [ -f "docker-compose.yml" ]; then
        COMPOSE_FILE="docker-compose.yml"
        DOCKER_RUNNING=true
    elif [ -f "/opt/swaan/docker-compose.yml" ]; then
        cd /opt/swaan
        COMPOSE_FILE="docker-compose.yml"
        DOCKER_RUNNING=true
    fi
fi

if [ "$DOCKER_RUNNING" = true ]; then
    echo -e "${GREEN}[*] Docker deployment detected (${COMPOSE_FILE}). Updating containers...${NC}"
    echo ""
    
    echo -e "${CYAN}[1/3] Pulling latest platform images from Docker Hub...${NC}"
    docker compose -f "$COMPOSE_FILE" pull
    
    echo -e "${CYAN}[2/3] Recreating and updating containers...${NC}"
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
    
    echo -e "${CYAN}[3/3] Verifying platform health...${NC}"
    MAX_TRIES=25
    COUNT=0
    HEALTHY=false
    while [ $COUNT -lt $MAX_TRIES ]; do
        COUNT=$((COUNT + 1))
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health || echo "000")
        if [ "$HTTP_CODE" == "200" ]; then
            HEALTHY=true
            break
        fi
        printf "  Waiting for backend services to complete initialization (%d/%d)...\r" "$COUNT" "$MAX_TRIES"
        sleep 2
    done
    echo ""
    
    if [ "$HEALTHY" = true ]; then
        echo -e "${GREEN}[✓] Docker containers updated and operational!${NC}"
    else
        echo -e "${YELLOW}[!] Containers refreshed. If health check is pending, inspect logs:${NC}"
        echo -e "    docker compose -f $COMPOSE_FILE logs -f"
    fi
    exit 0
fi

# ── Native Host Deployment Update ──────────────────────────────────────────
echo -e "${CYAN}[*] Native host deployment detected. Updating local codebase...${NC}"

# 1. Git pull if repository exists
if [ -d ".git" ]; then
    echo -e "${CYAN}[1/4] Pulling latest code changes from GitHub...${NC}"
    git pull origin main || echo -e "${YELLOW}Warning: Git pull encountered notices.${NC}"
fi

# 2. Frontend compilation
if [ -d "frontend" ] && command -v npm >/dev/null 2>&1; then
    echo -e "${CYAN}[2/4] Compiling frontend production bundle...${NC}"
    cd frontend && npm install && npm run build && cd ..
fi

# 3. Database migrations
echo -e "${CYAN}[3/4] Applying database schemas & RLS migrations...${NC}"
if [ -f "./venv/bin/python" ]; then
    ./venv/bin/python seed.py --no-demo 2>/dev/null || true
    ./venv/bin/python migrate_rls_policies.py 2>/dev/null || true
else
    python3 seed.py --no-demo 2>/dev/null || true
    python3 migrate_rls_policies.py 2>/dev/null || true
fi

# 4. Process restart
echo -e "${CYAN}[4/4] Refreshing native services...${NC}"
if [ -f "./stop.sh" ] && [ -f "./start.sh" ]; then
    ./stop.sh
    ./start.sh
fi

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  ✓ SWAAN Update Completed Successfully!                        ${NC}"
echo -e "${GREEN}================================================================${NC}"
