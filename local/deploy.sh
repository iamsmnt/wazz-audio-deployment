#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SERVICES="db rabbitmq backend worker frontend"

usage() {
    echo "Usage: ./deploy.sh <command> [service...]"
    echo ""
    echo "Commands:"
    echo "  start [service...]   Build and start services (all if none specified)"
    echo "  stop  [service...]   Stop services (all if none specified)"
    echo "  restart [service...] Restart services (all if none specified)"
    echo "  build [service...]   Build images without starting (all if none specified)"
    echo "  logs [service...]    Follow logs (all if none specified)"
    echo "  status               Show running containers"
    echo "  clean                Stop services and remove all volumes (data loss!)"
    echo ""
    echo "Services: ${SERVICES}"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh start                # Start everything"
    echo "  ./deploy.sh start backend        # Start backend + its dependencies"
    echo "  ./deploy.sh build worker         # Rebuild worker image only"
    echo "  ./deploy.sh restart backend worker  # Restart backend and worker"
    echo "  ./deploy.sh logs worker          # Follow worker logs"
    exit 1
}

start() {
    local services=("${@+"$@"}")
    if [ ${#services[@]} -eq 0 ]; then
        echo -e "${GREEN}Starting all services (local)...${NC}"
        docker compose up --build -d
    else
        echo -e "${GREEN}Starting ${services[*]} (local)...${NC}"
        docker compose up --build -d "${services[@]}"
    fi

    echo ""
    echo -e "${GREEN}Services started!${NC}"
    echo ""
    echo "Service URLs:"
    echo "  Frontend:     http://localhost:3000"
    echo "  Backend API:  http://localhost:8000"
    echo "  API Docs:     http://localhost:8000/docs"
    echo "  RabbitMQ UI:  http://localhost:15672 (guest/guest)"
}

stop() {
    local services=("${@+"$@"}")
    if [ ${#services[@]} -eq 0 ]; then
        echo -e "${YELLOW}Stopping all services (local)...${NC}"
        docker compose down
    else
        echo -e "${YELLOW}Stopping ${services[*]}...${NC}"
        docker compose stop "${services[@]}"
    fi
    echo -e "${GREEN}Stopped.${NC}"
}

build() {
    local services=("${@+"$@"}")
    if [ ${#services[@]} -eq 0 ]; then
        echo -e "${GREEN}Building all images...${NC}"
        docker compose build
    else
        echo -e "${GREEN}Building ${services[*]}...${NC}"
        docker compose build "${services[@]}"
    fi
    echo -e "${GREEN}Build complete.${NC}"
}

logs() {
    local services=("${@+"$@"}")
    if [ ${#services[@]} -eq 0 ]; then
        docker compose logs -f
    else
        docker compose logs -f "${services[@]}"
    fi
}

status() {
    docker compose ps
}

clean() {
    echo -e "${RED}WARNING: This will delete all data (database, uploaded files, processed audio).${NC}"
    read -p "Are you sure? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        docker compose down -v
        echo -e "${GREEN}Cleaned up.${NC}"
    else
        echo "Cancelled."
    fi
}

case "${1:-}" in
    start)   shift; start "$@" ;;
    stop)    shift; stop "$@" ;;
    restart) shift; stop "$@"; start "$@" ;;
    build)   shift; build "$@" ;;
    logs)    shift; logs "$@" ;;
    status)  status ;;
    clean)   clean ;;
    *)       usage ;;
esac
