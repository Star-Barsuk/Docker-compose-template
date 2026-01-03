#!/bin/bash
# =============================================================================
# DOCKER MANAGEMENT
# =============================================================================

set -euo pipefail

# Initialize paths and source lib.sh
source "$(dirname "$0")/init.sh"

# -----------------------------------------------------------------------------
# VALIDATION
# -----------------------------------------------------------------------------
docker::validate() {
    log::header "Validating Configuration"

    load::environment >/dev/null || return 1

    if compose::cmd config --quiet; then
        log::success "Docker Compose configuration is valid"

        local services
        services=$(compose::cmd config --services 2>/dev/null | sort)

        if [[ -n "$services" ]]; then
            echo ""
            log::info "Active services:"
            echo "$services" | sed 's/^/  /'
        fi
        return 0
    else
        log::error "Invalid Docker Compose configuration"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# SERVICE MANAGEMENT
# -----------------------------------------------------------------------------
docker::up() {
    log::header "Starting Services"

    load::environment >/dev/null || return 1

    if [[ "${FORCE:-}" != "1" ]] && \
       compose::cmd ps --services --filter "status=running" 2>/dev/null | grep -q .; then
        log::warn "Some services are already running."
        echo "Use FORCE=1 to restart, or 'make stop' first."
        return 1
    fi

    docker::validate || return 1

    log::info "Starting services..."
    if compose::cmd up --detach --wait --wait-timeout 120; then
        log::success "Services started successfully"

        echo ""
        compose::cmd ps --all

        echo ""
        log::info "Service URLs:"
        [[ -n "${APP_PORT_DEV:-}" ]] && echo "  Application: http://localhost:${APP_PORT_DEV}"
        [[ -n "${PGADMIN_PORT_DEV:-}" ]] && echo "  PgAdmin:     http://localhost:${PGADMIN_PORT_DEV}"
    else
        log::error "Failed to start services"
        return 1
    fi
}

docker::stop() {
    log::header "Stopping Services"

    load::environment >/dev/null || return 1

    log::info "Stopping services..."
    if compose::cmd stop --timeout 30; then
        log::success "Services stopped"
        echo ""
        compose::cmd ps --all
    else
        log::error "Failed to stop services"
        return 1
    fi
}

docker::down() {
    log::header "Removing Services"

    load::environment >/dev/null || return 1

    local args=("--remove-orphans")

    # Handle volume removal
    if [[ "${REMOVE_VOLUMES:-}" == "1" ]]; then
        args+=("--volumes")
        log::warn "WARNING: This will remove ALL data volumes!"

        if [[ "${FORCE:-}" != "1" ]]; then
            read -rp "Are you sure? Type 'YES' to confirm: " confirm
            if [[ "$confirm" != "YES" ]]; then
                log::info "Operation cancelled."
                return 0
            fi
        fi
    fi

    log::info "Removing services..."
    if compose::cmd down "${args[@]}"; then
        log::success "Services removed"
    else
        log::error "Failed to remove services"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# BUILD
# -----------------------------------------------------------------------------
docker::build() {
    log::header "Building Images"

    load::environment >/dev/null || return 1

    local args=("--pull" "--progress" "plain")
    [[ -n "${APP_VERSION:-}" ]] && args+=("--build-arg" "APP_VERSION=${APP_VERSION}")

    log::info "Building images..."
    if compose::cmd build "${args[@]}"; then
        log::success "Images built successfully"

        echo ""
        log::info "Built images:"
        compose::cmd images --quiet 2>/dev/null | while read -r image; do
            docker inspect --format='{{range .RepoTags}}{{.}}{{end}}' "$image" 2>/dev/null || true
        done | sort
    else
        log::error "Build failed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# CLEANUP
# -----------------------------------------------------------------------------
docker::clean() {
    log::header "Cleaning Up"

    load::environment >/dev/null || return 1

    # Stop if services are running
    if compose::cmd ps --services --filter "status=running" 2>/dev/null | grep -q .; then
        log::error "Services are running. Stop them first with 'make stop'"
        return 1
    fi

    log::info "Cleaning Docker resources..."

    # Remove stopped containers
    compose::cmd down --remove-orphans 2>/dev/null || true

    # Remove dangling images
    local dangling
    dangling=$(docker images --filter "dangling=true" -q 2>/dev/null | wc -l)
    if [[ $dangling -gt 0 ]]; then
        log::info "Removing $dangling dangling images..."
        docker image prune --force 2>/dev/null || true
    fi

    # Clean networks
    docker network prune --force --filter "label!=com.docker.compose.network" 2>/dev/null || true

    log::success "Cleanup completed"
}

docker::nuke() {
    log::header "⚠️  FULL CLEANUP"

    echo "WARNING: This will remove ALL Docker resources for this project!"
    echo "Including: containers, images, volumes, networks"
    echo ""

    if [[ "${FORCE:-}" != "1" ]]; then
        read -rp "Type 'NUKE' to confirm: " confirm
        if [[ "$confirm" != "NUKE" ]]; then
            log::info "Operation cancelled."
            return 0
        fi
    fi

    load::environment >/dev/null 2>&1 || true

    log::warn "Starting nuclear cleanup..."

    # Remove everything
    compose::cmd down --volumes --remove-orphans --rmi all 2>/dev/null || true

    # Force remove any remaining images
    compose::cmd images --quiet 2>/dev/null | xargs -r docker rmi --force 2>/dev/null || true

    # Remove volumes
    docker volume ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | \
        xargs -r docker volume rm --force 2>/dev/null || true

    # System prune
    docker system prune --all --force --volumes 2>/dev/null || true

    log::success "Nuclear cleanup completed"
    log::warn "All Docker resources for this project have been removed"
}

# -----------------------------------------------------------------------------
# LOGS & SHELL
# -----------------------------------------------------------------------------
docker::logs() {
    log::header "Viewing Logs"

    load::environment >/dev/null || return 1

    local args=()
    [[ "${FOLLOW:-}" == "1" ]] && args+=("--follow")
    args+=("--tail=${TAIL:-100}")

    compose::cmd logs "${args[@]}" "$@"
}

docker::shell() {
    log::header "Container Shell"

    load::environment >/dev/null || return 1

    local service="${1:-app-dev}"

    # Check service exists
    if ! compose::cmd ps --services 2>/dev/null | grep -q "^$service$"; then
        log::error "Service '$service' not found"
        echo "Available services:"
        compose::cmd ps --services 2>/dev/null | sed 's/^/  /'
        return 1
    fi

    # Ensure service is running
    if ! compose::cmd ps --services --filter "status=running" 2>/dev/null | grep -q "^$service$"; then
        log::warn "Service '$service' not running. Starting..."
        compose::cmd up --detach --wait "$service" || return 1
    fi

    log::info "Entering shell in: $service"
    compose::cmd exec "$service" sh -c "exec \${SHELL:-sh}"
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        up|down|stop|build|clean|nuke|logs|shell|validate)
            docker::$cmd "${@:2}"
            ;;
        ps)
            load::environment >/dev/null || exit 1
            compose::cmd ps "${@:2}"
            ;;
        images)
            load::environment >/dev/null || exit 1
            compose::cmd images "${@:2}"
            ;;
        exec)
            load::environment >/dev/null || exit 1
            compose::cmd exec "${@:2}"
            ;;
        config)
            load::environment >/dev/null || exit 1
            compose::cmd config "${@:2}"
            ;;
        help|--help|-h)
            cat << EOF
Docker Management

Usage: $0 COMMAND [ARGS...]

Commands:
  up                   Start services
  stop                 Stop services
  down                 Remove services
  build                Build images
  clean                Safe cleanup
  nuke                 Remove everything (danger!)
  logs [SERVICE]       View logs
  shell [SERVICE]      Enter container shell
  ps                   List containers
  images               List images
  exec SERVICE CMD     Execute command in container
  config               Validate configuration
  validate             Alias for config --quiet

Options (environment variables):
  FORCE=1              Skip confirmations
  FOLLOW=1             Follow log output
  TAIL=N               Number of log lines (default: 100)
  REMOVE_VOLUMES=1     Remove volumes with 'down'

Examples:
  $0 up
  $0 logs app-dev
  $0 shell db-dev
  FOLLOW=1 TAIL=50 $0 logs
EOF
            ;;
        *)
            log::error "Unknown command: $cmd"
            echo "Use '$0 help' for usage"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
