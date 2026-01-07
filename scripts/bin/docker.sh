#!/bin/bash
# =============================================================================
# DOCKER MANAGEMENT
# Command-line interface for Docker Compose operations
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
        echo "Use '--force' flag to restart, or 'stop' first."
        return 1
    fi

    if ! docker::validate; then
        log::error "Validation failed, aborting"
        return 1
    fi

    log::info "Starting services..."

    # local compose_args=("--detach" "--wait" "--wait-timeout" "120")
    local compose_args=("--detach")
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

    if [[ "${REMOVE_VOLUMES:-0}" == "1" ]]; then
        compose_args+=("--volumes")
        log::warn "Removing all persistent data volumes."
    fi

    local running_count
    running_count=$(compose::cmd ps --services --filter "status=running" 2>/dev/null | wc -l)

    if [[ $running_count -gt 0 ]]; then
        log::info "Stopping $running_count running service(s)..."
        compose::cmd stop --timeout 1
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

    local build_args=("--progress" "plain")
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

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}"
    local images=$(docker images --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null)

    if [[ -z "$images" ]]; then
        echo "  No images found for project $COMPOSE_PROJECT_NAME"
        return
    fi

    while read -r image; do
        local size created
        size=$(docker inspect --format='{{.Size}}' "$image" 2>/dev/null | numfmt --to=iec --format="%.2f" 2>/dev/null || echo "unknown")
        created=$(docker inspect --format='{{.Created}}' "$image" 2>/dev/null | cut -d'T' -f1 2>/dev/null || echo "unknown")

        printf "  %-60s %-10s %s\n" "$image" "$size" "$created"
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

    for arg in "$@"; do
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
        echo "Use 'stop' first or specify '--force' flag"
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

    local args=()
    for arg in "$@"; do
        if [[ "$arg" != "--" ]]; then
            services+=("$arg")
        fi
    done

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

            if ! compose::cmd logs "$service"; then
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

    docker stats "${container_ids[@]}" --no-stream "${@:-}"
}

docker::df() {
    log::header "Docker Disk Usage"

    if ! validate::docker_running; then
        return 1
    fi

    docker system df

    echo ""
    log::info "Detailed information:"
    echo "$(printf '─%.0s' {1..60})"
    docker system df --verbose 2>/dev/null || docker system df
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

    local ports_to_check=()

    [[ -n "${APP_PORT_DEV:-}" ]] && ports_to_check+=("APP_PORT_DEV:$APP_PORT_DEV")
    [[ -n "${APP_PORT_PROD:-}" ]] && ports_to_check+=("APP_PORT_PROD:$APP_PORT_PROD")
    [[ -n "${DB_PORT_DEV:-}" ]] && ports_to_check+=("DB_PORT_DEV:$DB_PORT_DEV")
    [[ -n "${DB_PORT_LOCAL:-}" ]] && ports_to_check+=("DB_PORT_LOCAL:$DB_PORT_LOCAL")
    [[ -n "${PGADMIN_PORT_DEV:-}" ]] && ports_to_check+=("PGADMIN_PORT_DEV:$PGADMIN_PORT_DEV")
    [[ -n "${PGADMIN_PORT_PROD:-}" ]] && ports_to_check+=("PGADMIN_PORT_PROD:$PGADMIN_PORT_PROD")

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

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------
main() {
    local parsed_args
    parsed_args=$(parse::flags "$@")

    mapfile -t args_array <<< "$parsed_args"

    local cmd="${args_array[0]:-help}"
    local remaining_args=("${args_array[@]:1}")

    if [[ -z "$cmd" ]] || [[ "$cmd" == "help" ]] || [[ "$cmd" == "--help" ]] || [[ "$cmd" == "-h" ]]; then
        cmd="help"
    fi

    if [[ "$cmd" != "help" ]]; then
        if ! validate::docker_running; then
            return 1
        fi
    fi

    case "$cmd" in
        up|down|stop|build)
            docker::$cmd "${remaining_args[@]}"
            ;;
        clean)
            docker::$cmd "${remaining_args[@]}"
            ;;
        ps|stats|df|inspect|ports|check-ports)
            docker::$cmd "${remaining_args[@]}"
            ;;
        logs|shell)
            docker::$cmd "${remaining_args[@]}"
            ;;
        validate|config)
            if [[ "$cmd" == "validate" ]]; then
                docker::validate "${remaining_args[@]}"
            else
                load::environment >/dev/null || exit 1
                compose::cmd config "${remaining_args[@]}"
            fi
            ;;
        images|exec|top|events)
            load::environment >/dev/null || exit 1
            compose::cmd "$cmd" "${remaining_args[@]}"
            ;;
        help|--help|-h)
            cat << "EOF"
Docker Management System

Usage: docker.sh [GLOBAL_FLAGS] COMMAND [COMMAND_ARGS...]

Global Flags (apply to all commands):
  --force, -f           Skip confirmations and force actions
  --volumes, -v         Remove volumes with 'down' command
  --no-cache           Disable build cache
  --help, -h           Show this help

Service Management Commands:
  up                    Start services
  stop                  Stop services
  down                  Remove services (use --volumes to remove data volumes)
  build                 Build images (use --no-cache to disable cache)

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

Interactive:
  logs [SERVICE...]     View logs
  shell [SERVICE]       Enter container shell

Validation:
  validate              Validate configuration
  config                Show raw configuration

Direct Docker Compose Commands:
  images                List images
  exec SERVICE CMD      Execute command in container
  top                   Display running processes
  events                Real-time container events

EOF
            ;;
        *)
            log::error "Unknown command: $cmd"
            echo "Use 'help' for usage information"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# EXECUTION GUARD
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
