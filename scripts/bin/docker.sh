#!/bin/bash
# =============================================================================
# DOCKER MANAGEMENT
# =============================================================================

set -euo pipefail

# Initialize paths
source "$(dirname "$0")/init.sh"

# -----------------------------------------------------------------------------
# CONFIGURATION VALIDATION
# -----------------------------------------------------------------------------
docker::validate() {
    log::header "Validating Configuration"

    if ! load::environment >/dev/null; then
        log::error "Failed to load environment"
        return 1
    fi

    local validation_output
    if validation_output=$(compose::cmd config --quiet 2>&1); then
        log::success "Docker Compose configuration is valid"

        local services
        if services=$(compose::cmd config --services 2>/dev/null); then
            echo ""
            log::info "Configured services:"
            echo "$services" | while read -r service; do
                echo "  - $service"
            done
        fi
        return 0
    else
        log::error "Invalid Docker Compose configuration"
        echo "$validation_output" | sed 's/^/  /'
        return 1
    fi
}

# -----------------------------------------------------------------------------
# SERVICE MANAGEMENT
# -----------------------------------------------------------------------------
docker::up() {
    log::header "Starting Services"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local running_services
    running_services=$(compose::cmd ps --services --filter "status=running" 2>/dev/null || true)

    if [[ -n "$running_services" ]] && [[ "${FORCE:-}" != "1" ]]; then
        log::warn "Some services are already running:"
        echo "$running_services" | sed 's/^/  /'
        echo ""
        echo "Use FORCE=1 to restart, or 'make stop' first."
        return 1
    fi

    if ! docker::validate; then
        log::error "Validation failed, aborting"
        return 1
    fi

    log::info "Starting services..."

    local compose_args=("--detach" "--wait" "--wait-timeout" "120")
    [[ "${FORCE:-}" == "1" ]] && compose_args+=("--force-recreate")

    if compose::cmd up "${compose_args[@]}"; then
        log::success "Services started successfully"

        echo ""
        docker::ps

        echo ""
        docker::ports

        echo ""
        docker::check_ports
    else
        log::error "Failed to start services"
        return 1
    fi
}

docker::stop() {
    log::header "Stopping Services"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local running_services
    running_services=$(compose::cmd ps --services --filter "status=running" 2>/dev/null || true)

    if [[ -z "$running_services" ]]; then
        log::info "No running services found"
        return 0
    fi

    log::info "Stopping $(( $(echo "$running_services" | wc -l) )) service(s)..."

    local stop_args=("--timeout" "30")
    [[ "${FORCE:-}" == "1" ]] && stop_args+=("--timeout" "1")

    if compose::cmd stop "${stop_args[@]}"; then
        log::success "Services stopped successfully"

        echo ""
        docker::ps
    else
        log::error "Failed to stop services"
        return 1
    fi
}

docker::down() {
    log::header "Removing Services"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local compose_args=("--remove-orphans")

    if [[ "${REMOVE_VOLUMES:-}" == "1" ]]; then
        compose_args+=("--volumes")
        log::warn "⚠️  WARNING: This will remove ALL persistent data volumes!"

        if [[ "${FORCE:-}" != "1" ]]; then
            local confirm=""
            read -rp "Type 'DELETE VOLUMES' to confirm: " confirm
            if [[ "$confirm" != "DELETE VOLUMES" ]]; then
                log::info "Operation cancelled."
                return 0
            fi
        fi
    fi

    local running_count
    running_count=$(compose::cmd ps --services --filter "status=running" 2>/dev/null | wc -l)

    if [[ $running_count -gt 0 ]]; then
        log::warn "Found $running_count running service(s)"
        if [[ "${FORCE:-}" != "1" ]]; then
            log::error "Cannot remove running services. Use 'make stop' first or FORCE=1"
            return 1
        else
            log::info "Force removing running services..."
        fi
    fi

    log::info "Removing services..."
    if compose::cmd down "${compose_args[@]}"; then
        log::success "Services removed successfully"

        echo ""
        docker::_list_resources "Remaining project resources:"
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

    if ! load::environment >/dev/null; then
        return 1
    fi

    local build_args=("--pull" "--progress" "plain")
    [[ -n "${APP_VERSION:-}" ]] && build_args+=("--build-arg" "APP_VERSION=${APP_VERSION}")
    [[ "${NO_CACHE:-}" == "1" ]] && build_args+=("--no-cache")
    [[ "${FORCE:-}" == "1" ]] && build_args+=("--force-rm")

    log::info "Building images with args: ${build_args[*]}"

    local start_time
    start_time=$(date +%s)

    if compose::cmd build "${build_args[@]}"; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))

        log::success "Images built successfully in ${elapsed}s"

        echo ""
        docker::_show_built_images
    else
        log::error "Build failed"
        return 1
    fi
}

docker::_show_built_images() {
    log::info "Built images:"

    local images
    images=$(compose::cmd images --quiet 2>/dev/null | sort -u)

    if [[ -z "$images" ]]; then
        echo "  No images found"
        return
    fi

    while read -r image_id; do
        local tags size created
        tags=$(docker inspect --format='{{range .RepoTags}}{{.}} {{end}}' "$image_id" 2>/dev/null | xargs)
        size=$(docker inspect --format='{{.Size}}' "$image_id" 2>/dev/null | numfmt --to=iec --format="%.2f" 2>/dev/null || echo "unknown")
        created=$(docker inspect --format='{{.Created}}' "$image_id" 2>/dev/null | cut -d'T' -f1 2>/dev/null || echo "unknown")

        if [[ -n "$tags" ]]; then
            printf "  %-60s %-10s %s\n" "$tags" "$size" "$created"
        fi
    done <<< "$images"
}

# -----------------------------------------------------------------------------
# CLEANUP
# -----------------------------------------------------------------------------
docker::clean() {
    log::header "Cleaning Docker Resources"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local targets=()

    for arg in "${@}"; do
        case "$arg" in
            containers) targets+=("containers") ;;
            images)     targets+=("images") ;;
            volumes)    targets+=("volumes") ;;
            networks)   targets+=("networks") ;;
            cache)      targets+=("cache") ;;
            all)        targets=("containers" "images" "volumes" "networks" "cache") ;;
        esac
    done

    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=("containers" "images" "cache")
    fi

    local running_count
    running_count=$(compose::cmd ps --services --filter "status=running" 2>/dev/null | wc -l)

    if [[ $running_count -gt 0 ]]; then
        log::error "Cannot clean while $running_count service(s) are running"
        echo "Use 'make stop' first or specify FORCE=1 to stop them"
        return 1
    fi

    for target in "${targets[@]}"; do
        case "$target" in
            containers)  docker::_clean_containers ;;
            images)      docker::_clean_images ;;
            volumes)     docker::_clean_volumes ;;
            networks)    docker::_clean_networks ;;
            cache)       docker::_clean_cache ;;
        esac
    done

    log::success "Cleanup completed"
}

docker::_clean_containers() {
    log::info "Cleaning containers..."

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"

    local stopped_count
    stopped_count=$(docker ps -a --filter "$project_filter" --filter "status=exited" -q 2>/dev/null | wc -l)

    if [[ $stopped_count -gt 0 ]]; then
        log::info "Removing $stopped_count stopped container(s)..."
        docker ps -a --filter "$project_filter" --filter "status=exited" -q 2>/dev/null | \
            xargs -r docker rm 2>/dev/null || true
    fi

    local created_count
    created_count=$(docker ps -a --filter "$project_filter" --filter "status=created" -q 2>/dev/null | wc -l)

    if [[ $created_count -gt 0 ]]; then
        log::info "Removing $created_count created container(s)..."
        docker ps -a --filter "$project_filter" --filter "status=created" -q 2>/dev/null | \
            xargs -r docker rm 2>/dev/null || true
    fi
}

docker::_clean_images() {
    log::info "Cleaning images..."

    local dangling_count
    dangling_count=$(docker images --filter "dangling=true" -q 2>/dev/null | wc -l)

    if [[ $dangling_count -gt 0 ]]; then
        log::info "Removing $dangling_count dangling image(s)..."
        docker image prune --force 2>/dev/null || true
    fi

    if [[ "${FORCE:-}" == "1" ]]; then
        local unused_count
        unused_count=$(docker images --filter "dangling=false" -q 2>/dev/null | wc -l)

        if [[ $unused_count -gt 0 ]]; then
            log::info "Removing $unused_count unused image(s)..."
            docker image prune --all --force 2>/dev/null || true
        fi
    fi
}

docker::_clean_volumes() {
    log::info "Cleaning volumes..."

    if [[ "${FORCE:-}" != "1" ]]; then
        log::warn "Volume removal requires FORCE=1"
        return 0
    fi

    local volume_count
    volume_count=$(docker volume ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | wc -l)

    if [[ $volume_count -gt 0 ]]; then
        log::info "Removing $volume_count volume(s)..."
        docker volume ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | \
            xargs -r docker volume rm --force 2>/dev/null || true
    fi
}

docker::_clean_networks() {
    log::info "Cleaning networks..."

    if [[ "${FORCE:-}" != "1" ]]; then
        log::warn "Network removal requires FORCE=1"
        return 0
    fi

    local network_count
    network_count=$(docker network ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | wc -l)

    if [[ $network_count -gt 0 ]]; then
        log::info "Removing $network_count network(s)..."
        docker network ls --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}" -q 2>/dev/null | \
            xargs -r docker network rm 2>/dev/null || true
    fi
}

docker::_clean_cache() {
    log::info "Cleaning build cache..."

    if docker buildx ls >/dev/null 2>&1; then
        docker builder prune --force 2>/dev/null || true
    fi

    docker system prune --force 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# LOGS
# -----------------------------------------------------------------------------
docker::logs() {
    log::header "Container Logs"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local services=()
    local follow="${FOLLOW:-0}"
    local tail="${TAIL:-100}"
    local since="${SINCE:-}"
    local until="${UNTIL:-}"
    local timestamps="${TIMESTAMPS:-0}"

    # Parse arguments
    local args=()
    for arg in "$@"; do
        if [[ "$arg" == "--follow" ]] || [[ "$arg" == "-f" ]]; then
            follow=1
        elif [[ "$arg" =~ ^--tail= ]] || [[ "$arg" =~ ^-n ]]; then
            tail="${arg#*=}"
            [[ "$tail" == "$arg" ]] && tail="${arg#* }"
        elif [[ "$arg" =~ ^--since= ]]; then
            since="${arg#*=}"
        elif [[ "$arg" =~ ^--until= ]]; then
            until="${arg#*=}"
        elif [[ "$arg" == "--timestamps" ]] || [[ "$arg" == "-t" ]]; then
            timestamps=1
        elif [[ "$arg" != "--" ]]; then
            services+=("$arg")
        fi
    done

    local log_args=()
    [[ "$follow" == "1" ]] && log_args+=("--follow")
    log_args+=("--tail" "$tail")
    [[ -n "$since" ]] && log_args+=("--since" "$since")
    [[ -n "$until" ]] && log_args+=("--until" "$until")
    [[ "$timestamps" == "1" ]] && log_args+=("--timestamps")

    if [[ ${#services[@]} -eq 0 ]]; then
        services=($(compose::cmd ps --services 2>/dev/null || true))

        if [[ ${#services[@]} -eq 0 ]]; then
            log::error "No services found"
            return 1
        fi

        log::info "Showing logs for all ${#services[@]} service(s):"
        echo "${services[@]}" | tr ' ' '\n' | sed 's/^/  /'
        echo ""
    fi

    local has_errors=0
    for service in "${services[@]}"; do
        if compose::cmd ps "$service" 2>/dev/null | grep -q "$service"; then
            log::info "Logs for $service:"
            echo "$(printf '=%.0s' {1..60})"

            if ! compose::cmd logs "${log_args[@]}" "$service"; then
                log::warn "Failed to get logs for $service"
                has_errors=1
            fi

            echo ""
        else
            log::warn "Service '$service' not found or not running"
            has_errors=1
        fi
    done

    return $has_errors
}

# -----------------------------------------------------------------------------
# SHELL
# -----------------------------------------------------------------------------
docker::shell() {
    log::header "Container Shell"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local service="${1:-}"
    local user="${2:-}"

    if [[ -z "$service" ]]; then
        local services
        services=($(compose::cmd ps --services 2>/dev/null | sort))

        if [[ ${#services[@]} -eq 0 ]]; then
            log::error "No services available"
            return 1
        fi

        echo "Select a service to access:"
        select service in "${services[@]}" "Cancel"; do
            [[ "$service" == "Cancel" ]] && { log::info "Cancelled"; return 0; }
            [[ -n "$service" ]] && break
        done
    fi

    if ! compose::cmd ps --services 2>/dev/null | grep -q "^$service$"; then
        log::error "Service '$service' not found"
        echo "Available services:"
        compose::cmd ps --services 2>/dev/null | sed 's/^/  /'
        return 1
    fi

    local service_status
    service_status=$(compose::cmd ps --services --filter "status=running" 2>/dev/null | grep "^$service$" || true)

    if [[ -z "$service_status" ]]; then
        log::warn "Service '$service' is not running"

        if [[ "${FORCE:-}" != "1" ]]; then
            read -rp "Start the service? (y/N): " -n 1 confirm
            echo ""
            [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]] && return 0
        fi

        log::info "Starting $service..."
        if ! compose::cmd up --detach --wait "$service"; then
            log::error "Failed to start $service"
            return 1
        fi
    fi

    local shell_cmd="sh"
    local service_image
    service_image=$(compose::cmd config --services | grep "^$service$" | head -1)

    if compose::cmd exec "$service" which bash >/dev/null 2>&1; then
        shell_cmd="bash"
    elif compose::cmd exec "$service" which zsh >/dev/null 2>&1; then
        shell_cmd="zsh"
    fi

    local exec_args=()
    [[ -n "$user" ]] && exec_args+=("--user" "$user")

    log::info "Entering $shell_cmd shell in $service..."
    compose::cmd exec "${exec_args[@]}" "$service" "$shell_cmd"
}

# -----------------------------------------------------------------------------
# MONITORING
# -----------------------------------------------------------------------------
docker::ps() {
    log::header "Container Status"

    if ! load::environment >/dev/null; then
        return 1
    fi

    compose::cmd ps "${@:-}"
}

docker::stats() {
    log::header "Container Statistics"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local services
    services=($(compose::cmd ps --services 2>/dev/null))

    if [[ ${#services[@]} -eq 0 ]]; then
        log::info "No services found"
        return 0
    fi

    # Get container IDs
    local container_ids=()
    for service in "${services[@]}"; do
        local container_id
        container_id=$(compose::cmd ps -q "$service" 2>/dev/null)
        [[ -n "$container_id" ]] && container_ids+=("$container_id")
    done

    if [[ ${#container_ids[@]} -eq 0 ]]; then
        log::info "No running containers found"
        return 0
    fi

    # Show stats
    docker stats "${container_ids[@]}" --no-stream "${@:-}"
}

docker::df() {
    log::header "Docker Disk Usage"

    if ! validate::docker_running; then
        return 1
    fi

    docker system df "${@:-}"

    echo ""
    log::info "Detailed information:"
    echo "$(printf '─%.0s' {1..60})"
    docker system df --verbose
}

docker::inspect() {
    log::header "Container Inspection"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local service="${1:-}"

    if [[ -z "$service" ]]; then
        log::info "Inspecting all services..."
        compose::cmd ps --all
        return 0
    fi

    local container_id
    container_id=$(compose::cmd ps -q "$service" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        log::error "Container for service '$service' not found"
        return 1
    fi

    docker inspect "$container_id" "${@:2}"
}

docker::ports() {
    log::header "Service Port Mapping"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local services
    services=($(compose::cmd ps --services 2>/dev/null))

    if [[ ${#services[@]} -eq 0 ]]; then
        log::info "No services found"
        return 0
    fi

    local host_ip
    host_ip=$(network::get_host_ip)

    printf "%-25s %-30s %s\n" "SERVICE" "CONTAINER PORT" "HOST ACCESS"
    echo "$(printf '=%.0s' {1..80})"

    local has_ports=0
    for service in "${services[@]}"; do
        local container_id
        container_id=$(compose::cmd ps -q "$service" 2>/dev/null)

        if [[ -n "$container_id" ]]; then
            local port_output
            port_output=$(docker port "$container_id" 2>/dev/null || true)

            if [[ -n "$port_output" ]]; then
                has_ports=1
                while IFS= read -r port_line; do
                    [[ -z "$port_line" ]] && continue

                    local container_port host_port
                    container_port=$(echo "$port_line" | awk '{print $1}')
                    host_port=$(echo "$port_line" | awk '{print $3}')

                    printf "%-25s %-30s %s\n" \
                        "$service" \
                        "$container_port" \
                        "http://${host_ip}:${host_port##*:} (localhost:${host_port##*:})"
                done <<< "$port_output"
            else
                printf "%-25s %-30s %s\n" "$service" "─" "No exposed ports"
            fi
        else
            printf "%-25s %-30s %s\n" "$service" "─" "Not running"
        fi
    done

    if [[ $has_ports -eq 0 ]]; then
        echo ""
        log::info "No exposed ports found"
    fi

    echo ""
    log::info "Host IP: $host_ip"
}

docker::check_ports() {
    log::header "Port Availability Check"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local services
    services=($(compose::cmd config --services 2>/dev/null))

    if [[ ${#services[@]} -eq 0 ]]; then
        log::info "No services configured"
        return 0
    fi

    # Check common service ports from environment
    local ports_to_check=()

    # Add ports from environment variables
    [[ -n "${APP_PORT_DEV:-}" ]] && ports_to_check+=("APP_PORT_DEV:$APP_PORT_DEV")
    [[ -n "${APP_PORT_PROD:-}" ]] && ports_to_check+=("APP_PORT_PROD:$APP_PORT_PROD")
    [[ -n "${DB_PORT_DEV:-}" ]] && ports_to_check+=("DB_PORT_DEV:$DB_PORT_DEV")
    [[ -n "${DB_PORT_LOCAL:-}" ]] && ports_to_check+=("DB_PORT_LOCAL:$DB_PORT_LOCAL")
    [[ -n "${PGADMIN_PORT_DEV:-}" ]] && ports_to_check+=("PGADMIN_PORT_DEV:$PGADMIN_PORT_DEV")
    [[ -n "${PGADMIN_PORT_PROD:-}" ]] && ports_to_check+=("PGADMIN_PORT_PROD:$PGADMIN_PORT_PROD")

    # Default ports if not specified
    [[ ${#ports_to_check[@]} -eq 0 ]] && ports_to_check=(
        "PostgreSQL:5432"
        "PgAdmin:8080"
        "App:8000"
    )

    echo "Checking port availability:"
    echo "$(printf '─%.0s' {1..50})"

    local busy_ports=0
    for port_spec in "${ports_to_check[@]}"; do
        local service_name="${port_spec%:*}"
        local port="${port_spec#*:}"

        if network::check_port "$port" "$service_name"; then
            :
        else
            busy_ports=$((busy_ports + 1))
        fi
    done

    echo "$(printf '─%.0s' {1..50})"

    if [[ $busy_ports -eq 0 ]]; then
        log::success "All ports are available"
    else
        log::warn "$busy_ports port(s) are busy"
        echo "Check running services with: $0 ps"
    fi
}

# -----------------------------------------------------------------------------
# RESOURCE LISTING
# -----------------------------------------------------------------------------
docker::_list_resources() {
    local header="${1:-Project Resources}"

    log::info "$header"

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"

    # Containers
    local container_count
    container_count=$(docker ps -a --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Containers" "$container_count"

    # Images
    local image_count
    image_count=$(docker images --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Images" "$image_count"

    # Volumes
    local volume_count
    volume_count=$(docker volume ls --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Volumes" "$volume_count"

    # Networks
    local network_count
    network_count=$(docker network ls --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Networks" "$network_count"
}

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    if [[ "$cmd" != "help" ]] && [[ "$cmd" != "--help" ]] && [[ "$cmd" != "-h" ]]; then
        if ! validate::docker_running; then
            return 1
        fi
    fi

    case "$cmd" in
        up|down|stop|build)
            docker::$cmd "$@"
            ;;

        clean|nuke)
            docker::$cmd "$@"
            ;;

        ps|stats|df|inspect|ports|check-ports)
            docker::$cmd "$@"
            ;;

        logs|shell)
            docker::$cmd "$@"
            ;;

        validate|config)
            if [[ "$cmd" == "validate" ]]; then
                docker::validate "$@"
            else
                load::environment >/dev/null || exit 1
                compose::cmd config "$@"
            fi
            ;;

        images|exec|top|events)
            load::environment >/dev/null || exit 1
            compose::cmd "$cmd" "$@"
            ;;

        help|--help|-h)
            cat << "EOF"
Docker Management System

Usage: $0 COMMAND [ARGS...]

Service Management:
  up                    Start services
  stop                  Stop services
  down                  Remove services
  build                 Build images

Monitoring & Inspection:
  ps                    List containers
  stats                 Live container statistics
  df                    Disk usage analysis
  inspect [SERVICE]     Inspect container details
  ports                 Show port mappings
  check-ports           Check port availability

Cleanup:
  clean [TARGETS...]    Clean specific resources
                        (containers, images, volumes, networks, cache, all)
  nuke                  Remove ALL project resources (danger!)

Interactive:
  logs [SERVICE...]     View logs (supports: --follow, --tail=N, --since, --until)
  shell [SERVICE]       Enter container shell

Validation:
  validate              Validate configuration
  config                Show raw configuration

Direct Docker Compose Commands:
  images                List images
  exec SERVICE CMD      Execute command in container
  top                   Display running processes
  events                Real-time container events

Options (environment variables):
  FORCE=1               Skip confirmations
  FOLLOW=1              Follow log output
  TAIL=N                Number of log lines (default: 100)
  REMOVE_VOLUMES=1      Remove volumes with 'down'
  NO_CACHE=1            Disable build cache
  SINCE=TIMESTAMP       Logs since timestamp
  UNTIL=TIMESTAMP       Logs until timestamp

Examples:
  $0 up
  $0 logs app-dev --follow --tail=50
  $0 shell db-dev
  $0 clean images cache
  $0 ports
  $0 check-ports
  FORCE=1 $0 nuke

TODO/Future Features:
  • Implement service scaling (docker::scale)
  • Add health check monitoring
  • Implement backup/restore functionality
  • Add resource usage alerts
  • Support for Docker Swarm mode
  • Implement rolling updates
  • Add configuration templates
  • Support multiple compose files
EOF
            ;;

        *)
            log::error "Unknown command: $cmd"
            echo "Use '$0 help' for usage information"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# EXECUTION GUARD
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # TODO: Add command line argument parsing
    # TODO: Implement --verbose/--quiet flags
    # TODO: Add --version flag
    main "$@"
fi
