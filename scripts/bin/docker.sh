#!/bin/bash
source "$(dirname "$0")/lib.sh"

# Docker Compose command executor with environment handling
docker::compose_cmd() {
    local cmd="$1"
    shift

    # Load environment and get active environment
    local env_name
    env_name="$(load::environment)" || return 1

    local compose_file
    compose_file="$(compose::path)/docker-compose.core.yml"

    if [[ ! -f "$compose_file" ]]; then
        log::error "Docker Compose file not found: $compose_file"
        return 1
    fi

    # Build Docker Compose command with environment variables
    local compose_args=(
        "--file" "$compose_file"
        "--project-directory" "$(compose::path)"
    )

    # Add project name if set
    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
        compose_args+=("--project-name" "$COMPOSE_PROJECT_NAME")
    fi

    # Add profile if set
    if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
        compose_args+=("--profile" "$COMPOSE_PROFILES")
    fi

    log::debug "Executing: docker compose ${compose_args[*]} $cmd $*"
    log::info "Using environment: $env_name, profile: ${COMPOSE_PROFILES:-default}"

    # Execute command
    docker compose "${compose_args[@]}" "$cmd" "$@"
}

# Validate Docker Compose configuration
docker::validate() {
    log::header "Validating Docker Compose Configuration"

    local env_name
    env_name="$(load::environment)" || return 1

    # Check Docker Compose file
    local compose_file
    compose_file="$(compose::path)/docker-compose.core.yml"

    if ! docker::compose_cmd config --quiet; then
        log::error "Docker Compose configuration is invalid"
        return 1
    fi

    log::success "Docker Compose configuration is valid"

    # Show active services
    echo ""
    log::info "Active profile: ${COMPOSE_PROFILES:-default}"
    log::info "Project name: ${COMPOSE_PROJECT_NAME:-not set}"

    # List services in the active profile
    if docker::compose_cmd config --services > /dev/null 2>&1; then
        local services
        services=$(docker::compose_cmd config --services 2>/dev/null | sort)
        if [[ -n "$services" ]]; then
            echo ""
            log::info "Services in active profile:"
            echo "$services" | while read -r service; do
                echo "  - $service"
            done
        fi
    fi
}

# Start services
docker::up() {
    log::header "Starting Docker Services"

    local env_name
    env_name="$(load::environment)" || return 1

    # Validate configuration first
    if ! docker::validate; then
        log::error "Validation failed. Aborting startup."
        return 1
    fi

    # Check for port conflicts
    log::info "Checking for port conflicts..."
    if docker::compose_cmd ps --services --filter "status=running" 2>/dev/null | grep -q .; then
        log::warn "Some services are already running"
        if [[ "${FORCE:-}" != "1" ]]; then
            echo "Use FORCE=1 to restart or run 'make stop' first"
            return 1
        fi
    fi

    # Start services
    log::info "Starting services..."
    if docker::compose_cmd up --detach --wait --wait-timeout 120; then
        log::success "Services started successfully"

        # Show service status
        echo ""
        docker::compose_cmd ps --all

        # Show URLs if available
        echo ""
        log::info "Service URLs:"
        if [[ -n "${APP_PORT_DEV:-}" ]]; then
            echo "  Application: http://localhost:${APP_PORT_DEV:-8000}"
        fi
        if [[ -n "${PGADMIN_PORT_DEV:-}" ]]; then
            echo "  PgAdmin: http://localhost:${PGADMIN_PORT_DEV:-8080}"
        fi
    else
        log::error "Failed to start services"
        return 1
    fi
}

# Stop services
docker::stop() {
    log::header "Stopping Docker Services"

    local env_name
    env_name="$(load::environment)" || return 1

    log::info "Stopping services..."
    if docker::compose_cmd stop --timeout 30; then
        log::success "Services stopped successfully"

        # Show stopped services
        echo ""
        docker::compose_cmd ps --all
    else
        log::error "Failed to stop services"
        return 1
    fi
}

# Remove services
docker::down() {
    log::header "Removing Docker Services"

    local env_name
    env_name="$(load::environment)" || return 1

    # Ask for confirmation when volumes are involved
    local remove_volumes=""
    if [[ "${REMOVE_VOLUMES:-}" == "1" ]]; then
        remove_volumes="--volumes"
        log::warn "WARNING: This will remove all data volumes!"
    fi

    if [[ "${FORCE:-}" != "1" ]] && [[ -n "$remove_volumes" ]]; then
        echo "Are you sure you want to remove services and all data volumes? (yes/no)"
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            log::info "Operation cancelled"
            return 0
        fi
    fi

    log::info "Removing services..."
    if docker::compose_cmd down $remove_volumes --remove-orphans; then
        log::success "Services removed successfully"
    else
        log::error "Failed to remove services"
        return 1
    fi
}

# Build images
docker::build() {
    log::header "Building Docker Images"

    local env_name
    env_name="$(load::environment)" || return 1

    # Build arguments from environment
    local build_args=()
    if [[ -n "${APP_VERSION:-}" ]]; then
        build_args+=("--build-arg" "APP_VERSION=${APP_VERSION}")
    fi

    log::info "Building images with cache..."
    if docker::compose_cmd build --pull --progress plain "${build_args[@]}"; then
        log::success "Images built successfully"

        # Show image information
        echo ""
        log::info "Built images:"
        docker::compose_cmd images --quiet | xargs docker inspect --format='{{.RepoTags}}' 2>/dev/null || true
    else
        log::error "Failed to build images"
        return 1
    fi
}

# Safe cleanup
docker::clean() {
    log::header "Cleaning Docker Resources"

    local env_name
    env_name="$(load::environment)" || return 1

    # Check if services are running
    if docker::compose_cmd ps --services --filter "status=running" 2>/dev/null | grep -q .; then
        log::error "Services are still running. Stop them first with 'make stop'"
        return 1
    fi

    log::info "Cleaning up resources..."

    # Remove containers
    if docker::compose_cmd ps --services --quiet 2>/dev/null | grep -q .; then
        log::info "Removing stopped containers..."
        docker::compose_cmd down --remove-orphans
    fi

    # Remove dangling images
    local dangling_images
    dangling_images=$(docker images --filter "dangling=true" -q 2>/dev/null | wc -l)
    if [[ "$dangling_images" -gt 0 ]]; then
        log::info "Removing $dangling_images dangling images..."
        docker image prune --force
    fi

    # Remove unused networks (except default ones)
    log::info "Cleaning unused networks..."
    docker network prune --force --filter "label!=com.docker.compose.network"

    log::success "Cleanup completed"
}

# Full cleanup (dangerous)
docker::nuke() {
    log::header "⚠️  FULL DOCKER CLEANUP (DANGEROUS)"

    echo "WARNING: This will remove ALL Docker resources for this project and environment."
    echo "This includes:"
    echo "  - All containers"
    echo "  - All images"
    echo "  - All volumes"
    echo "  - All networks"
    echo ""
    echo "Active environment: $(load::environment 2>/dev/null || echo "unknown")"
    echo "Project name: ${COMPOSE_PROJECT_NAME:-not set}"
    echo ""

    if [[ "${FORCE:-}" != "1" ]]; then
        echo "Are you absolutely sure? This cannot be undone. Type 'NUKE' to confirm:"
        read -r confirm
        if [[ "$confirm" != "NUKE" ]]; then
            log::info "Operation cancelled"
            return 0
        fi
    fi

    log::warn "Starting full cleanup..."

    # Load environment to get project name
    local env_name
    env_name="$(load::environment 2>/dev/null || true)"

    # Stop and remove all project containers
    log::info "Removing containers..."
    docker::compose_cmd down --volumes --remove-orphans --rmi all 2>/dev/null || true

    # Remove project images
    log::info "Removing images..."
    docker::compose_cmd images --quiet 2>/dev/null | xargs docker rmi --force 2>/dev/null || true

    # Remove project volumes
    log::info "Removing volumes..."
    docker volume ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | xargs docker volume rm --force 2>/dev/null || true

    # Remove project networks
    log::info "Removing networks..."
    docker network ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | xargs docker network rm 2>/dev/null || true

    # Full system cleanup
    log::info "Cleaning system..."
    docker system prune --all --force --volumes

    log::success "Full cleanup completed"
    log::warn "All Docker resources for project '${COMPOSE_PROJECT_NAME:-}' have been removed"
}

# View logs
docker::logs() {
    log::header "Viewing Docker Logs"

    local env_name
    env_name="$(load::environment)" || return 1

    local follow="${FOLLOW:-0}"
    local tail_lines="${TAIL:-100}"

    if [[ "$follow" == "1" ]]; then
        log::info "Following logs (Ctrl+C to stop)..."
        docker::compose_cmd logs --follow --tail="$tail_lines" "$@"
    else
        docker::compose_cmd logs --tail="$tail_lines" "$@"
    fi
}

# Execute command in container
docker::shell() {
    log::header "Container Shell Access"

    local env_name
    env_name="$(load::environment)" || return 1

    local service="${1:-app-dev}"

    # Check if service exists
    if ! docker::compose_cmd ps --services | grep -q "^$service$"; then
        log::error "Service '$service' not found in active profile"
        echo "Available services:"
        docker::compose_cmd ps --services | sort | sed 's/^/  - /'
        return 1
    fi

    # Check if service is running
    if ! docker::compose_cmd ps --services --filter "status=running" | grep -q "^$service$"; then
        log::warn "Service '$service' is not running. Starting it first..."
        docker::compose_cmd up --detach --wait "$service" || {
            log::error "Failed to start service '$service'"
            return 1
        }
    fi

    log::info "Entering shell in service: $service"
    echo "Use 'exit' to leave the container shell"
    echo ""

    docker::compose_cmd exec "$service" sh -c "which bash >/dev/null 2>&1 && exec bash || exec sh"
}

# Main dispatcher
main() {
    local command="${1:-}"

    case "$command" in
        up|down|stop|build|clean|nuke|logs|shell)
            docker::$command "${@:2}"
            ;;
        validate)
            docker::validate
            ;;
        ps|status)
            load::environment >/dev/null 2>&1 || exit 1
            docker::compose_cmd ps --all "${@:2}"
            ;;
        images)
            load::environment >/dev/null 2>&1 || exit 1
            docker::compose_cmd images "${@:2}"
            ;;
        exec)
            load::environment >/dev/null 2>&1 || exit 1
            docker::compose_cmd exec "${@:2}"
            ;;
        help|--help|-h)
            echo "Docker Management Commands"
            echo "Usage: $0 COMMAND [ARGS...]"
            echo ""
            echo "Commands:"
            echo "  up                 Start services"
            echo "  stop               Stop services"
            echo "  down               Remove services (add REMOVE_VOLUMES=1 for volumes)"
            echo "  build              Build images"
            echo "  clean              Safe cleanup (stopped containers, networks)"
            echo "  nuke               Full cleanup (WARNING: removes everything)"
            echo "  logs [SERVICE]     View logs (FOLLOW=1 to follow, TAIL=lines)"
            echo "  shell [SERVICE]    Enter container shell (default: app-dev)"
            echo "  ps|status          List containers"
            echo "  images             List images"
            echo "  exec SERVICE CMD   Execute command in container"
            echo "  validate           Validate configuration"
            echo ""
            echo "Environment variables:"
            echo "  FORCE=1            Skip confirmation prompts"
            echo "  FOLLOW=1           Follow log output"
            echo "  TAIL=100           Number of log lines to show"
            echo "  REMOVE_VOLUMES=1   Remove volumes with 'down' command"
            echo ""
            echo "Examples:"
            echo "  $0 up              # Start services"
            echo "  $0 logs app-dev    # View app logs"
            echo "  $0 shell           # Enter app container shell"
            echo "  FOLLOW=1 $0 logs   # Follow all logs"
            ;;
        *)
            if [[ -z "$command" ]]; then
                echo "No command specified"
            else
                echo "Unknown command: $command"
            fi
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
