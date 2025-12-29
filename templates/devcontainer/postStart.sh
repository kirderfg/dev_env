#!/bin/bash
# Runs every time container starts
set -e

BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[Start]${NC} $1"; }

# Wait for Docker daemon if using docker-in-docker
if [ -S /var/run/docker.sock ] || [ -f /.dockerenv ]; then
    log "Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi

# Start any docker-compose services if configured
if [ -f "docker-compose.yml" ] || [ -f "docker/docker-compose.yml" ]; then
    if docker info >/dev/null 2>&1; then
        log "Starting Docker services..."
        if [ -f "docker-compose.yml" ]; then
            docker compose up -d 2>/dev/null || true
        elif [ -f "docker/docker-compose.yml" ]; then
            docker compose -f docker/docker-compose.yml up -d 2>/dev/null || true
        fi
    fi
fi

# Ensure Tailscale is running (if installed)
if command -v tailscale &> /dev/null; then
    if ! pgrep -x tailscaled > /dev/null; then
        log "Starting Tailscale daemon..."
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock > /tmp/tailscaled.log 2>&1 &
        sleep 2
    fi
    if tailscale status &> /dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
        log "Tailscale connected: $TS_IP"
    fi
fi

log "Ready!"
