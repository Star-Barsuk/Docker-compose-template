#!/bin/bash
# =============================================================================
# DOCKER MANAGEMENT SCRIPT
# =============================================================================

set -euo pipefail

# --- Source shared library ---
source "$(dirname "$0")/init.sh"

# --- Configuration Validation ---
docker::validate() {
    # Validate Docker Compose configuration.
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

# --- Service Management ---
docker::up() {
    # Start Docker services.
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
        return 0
    fi

    if ! docker::validate; then
        log::error "Validation failed, aborting"
        return 1
    fi

    log::info "Starting services..."

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
    # Stop Docker services.
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
    # Remove Docker services.
    log::header "Removing Services"

    if ! load::environment >/dev/null; then
        return 1
    fi

    docker::stop

    local compose_args=("--remove-orphans")

    if [[ "${REMOVE_VOLUMES:-0}" == "1" ]]; then
        compose_args+=("--volumes")
        log::warn "Removing all persistent data volumes."
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

# --- Build ---
docker::build() {
    # Build Docker images.
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
    # Display built Docker images.
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

# --- Cleanup ---
docker::clean() {
    # Clean Docker resources.
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

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"
    local running_count
    running_count=$(docker ps --filter "$project_filter" --filter "status=running" -q 2>/dev/null | wc -l)

    if [[ $running_count -gt 0 ]] && [[ "${FORCE:-}" != "1" ]]; then
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
    # Clean Docker containers.
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
    # Clean Docker images.
    log::info "Cleaning images..."

    local dangling_count
    dangling_count=$(docker images --filter "dangling=true" -q 2>/dev/null | wc -l)

    if [[ $dangling_count -gt 0 ]]; then
        log::info "Removing $dangling_count dangling image(s)..."
        docker image prune --force 2>/dev/null || true
    fi

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"
    local project_images=()
    mapfile -t project_images < <(docker images --filter "$project_filter" --format "{{.ID}}" 2>/dev/null)

    if [[ ${#project_images[@]} -gt 0 ]]; then
        log::info "Removing ${#project_images[@]} project image(s)..."
        for image_id in "${project_images[@]}"; do
            echo "  Removing image: ${image_id:0:12}..."
            docker rmi -f "$image_id" 2>/dev/null || true
        done
    fi
}

docker::_clean_volumes() {
    # Clean Docker volumes.
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
    # Clean Docker networks.
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
    # Clean Docker build cache.
    log::info "Cleaning build cache..."

    if docker buildx ls >/dev/null 2>&1; then
        docker builder prune --force 2>/dev/null || true
    fi

    docker system prune --force 2>/dev/null || true
}

# --- Logs ---
docker::logs() {
    # Display container logs.
    log::header "Container Logs"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local services=()
    local compose_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tail=*|--tail)
                compose_args+=("$1")
                if [[ "$1" == "--tail" ]] && [[ $# -gt 1 ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    compose_args+=("$2")
                    shift
                fi
                ;;
            --follow|-f|--timestamps|-t|--since=*|--until=*)
                compose_args+=("$1")
                ;;
            *)
                services+=("$1")
                ;;
        esac
        shift
    done

    if [[ ${#services[@]} -eq 0 ]]; then
        services=($(compose::cmd ps --services 2>/dev/null || true))

        if [[ ${#services[@]} -eq 0 ]]; then
            log::error "No services found"
            return 1
        fi

        log::info "Showing logs for all ${#services[@]} service(s):"
        printf '  %s\n' "${services[@]}"
        echo ""
    fi

    local has_errors=0
    for service in "${services[@]}"; do
        if compose::cmd ps "$service" 2>/dev/null | grep -q "$service"; then
            log::info "Logs for $service:"
            echo "$(printf '=%.0s' {1..60})"

            if ! compose::cmd logs "${compose_args[@]}" "$service"; then
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

# --- Shell ---
docker::shell() {
    # Enter a container shell.
    log::header "Container Shell"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local service="${1:-}"

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

    local container_id
    container_id=$(compose::cmd ps -q "$service" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        log::error "Container for service '$service' not found or not running"
        return 1
    fi

    log::info "Entering shell in $service (container: ${container_id:0:12})..."

    if docker exec "$container_id" which bash >/dev/null 2>&1; then
        docker exec -it "$container_id" bash
    elif docker exec "$container_id" which ash >/dev/null 2>&1; then
        docker exec -it "$container_id" ash
    else
        docker exec -it "$container_id" sh
    fi
}

# --- Monitoring ---
docker::ps() {
    # Display container status.
    log::header "Container Status"

    if ! load::environment >/dev/null 2>&1; then
        return 1
    fi

    if ! compose::cmd ps "$@"; then
        log::error "Failed to get container status"
        return 1
    fi
}

docker::stats() {
    # Display container statistics.
    log::header "Container Statistics"

    if ! load::environment >/dev/null; then
        return 1
    fi

    local container_ids=()

    local services
    services=($(compose::cmd ps --services 2>/dev/null || true))

    for service in "${services[@]}"; do
        local container_id
        container_id=$(compose::cmd ps -q "$service" 2>/dev/null)
        if [[ -n "$container_id" ]]; then
            container_ids+=("$container_id")
        fi
    done

    if [[ ${#container_ids[@]} -eq 0 ]]; then
        local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"
        mapfile -t container_ids < <(docker ps -q --filter "$project_filter" 2>/dev/null || true)
    fi

    if [[ ${#container_ids[@]} -eq 0 ]]; then
        log::info "No running containers found for project"
        return 0
    fi

    log::info "Showing statistics for ${#container_ids[@]} container(s):"
    for id in "${container_ids[@]}"; do
        local name
        name=$(docker inspect --format '{{.Name}}' "$id" 2>/dev/null | sed 's/^\///' || echo "$id")
        echo "  - $name"
    done
    echo ""

    if [[ $# -eq 0 ]]; then
        docker stats "${container_ids[@]}" --no-stream
    else
        docker stats "${container_ids[@]}" "$@"
    fi
}

docker::df() {
    # Display Docker disk usage.
    log::header "Docker Disk Usage"

    # First show system-wide usage
    echo "System-wide Docker disk usage:"
    echo "$(printf '─%.0s' {1..40})"
    if ! docker system df; then
        log::error "Failed to get Docker disk usage"
        return 1
    fi

    echo ""
    echo "Current Compose stack analysis:"
    echo "$(printf '─%.0s' {1..40})"

    if ! load::environment >/dev/null 2>&1; then
        log::warn "Cannot load environment, showing only system-wide usage"
        return 0
    fi

    # Get all services in the current stack
    local services
    services=($(compose::cmd config --services 2>/dev/null || true))

    if [[ ${#services[@]} -eq 0 ]]; then
        log::info "No services configured in current stack"
        return 0
    fi

    # Collect all container IDs in the stack
    local container_ids=()
    local total_cpu=0
    local total_memory=0
    local total_containers=0

    log::info "Stack services (${#services[@]}): ${services[*]}"

    # Show resources for each service
    echo ""
    printf "%-20s %-15s %-15s %-15s %s\n" "SERVICE" "STATUS" "CPU %" "MEM USAGE" "IMAGE"
    echo "$(printf '=%.0s' {1..80})"

    for service in "${services[@]}"; do
        local container_id
        container_id=$(compose::cmd ps -q "$service" 2>/dev/null || true)

        if [[ -n "$container_id" ]]; then
            total_containers=$((total_containers + 1))

            # Get container stats
            local container_stats
            container_stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}} {{.Name}} {{.Container}}" "$container_id" 2>/dev/null || echo "")

            if [[ -n "$container_stats" ]]; then
                local cpu_perc mem_usage container_name
                read -r cpu_perc mem_usage container_name _ <<< "$container_stats"

                # Extract image name
                local image_name
                image_name=$(docker inspect --format='{{.Config.Image}}' "$container_id" 2>/dev/null || echo "unknown")

                printf "%-20s %-15s %-15s %-15s %s\n" \
                    "$service" \
                    "RUNNING" \
                    "$cpu_perc" \
                    "$mem_usage" \
                    "$image_name"

                # Parse CPU percentage (remove %)
                local cpu_num
                cpu_num=$(echo "$cpu_perc" | sed 's/%//')
                total_cpu=$(awk "BEGIN {printf \"%.2f\", $total_cpu + $cpu_num}")

                # Parse memory usage
                local mem_num unit
                read -r mem_num unit <<< "$(echo "$mem_usage" | sed 's/[^0-9.]//g')"
                if [[ "$unit" == "GiB" ]]; then
                    mem_num=$(awk "BEGIN {printf \"%.2f\", $mem_num * 1024}")
                elif [[ "$unit" == "KiB" ]]; then
                    mem_num=$(awk "BEGIN {printf \"%.2f\", $mem_num / 1024}")
                fi
                total_memory=$(awk "BEGIN {printf \"%.2f\", $total_memory + $mem_num}")
            else
                printf "%-20s %-15s %-15s %-15s %s\n" \
                    "$service" \
                    "RUNNING" \
                    "N/A" \
                    "N/A" \
                    "$(docker inspect --format='{{.Config.Image}}' "$container_id" 2>/dev/null || echo "unknown")"
            fi
        else
            printf "%-20s %-15s %-15s %-15s %s\n" \
                "$service" \
                "STOPPED" \
                "─" \
                "─" \
                "$(grep -A5 "^\s*$service:" docker/compose/docker-compose.core.yml 2>/dev/null | grep "image:" | head -1 | awk '{print $2}' || echo "not built")"
        fi
    done

    # Show summary
    echo ""
    echo "Stack resource summary:"
    echo "$(printf '─%.0s' {1..30})"
    printf "  %-20s: %d/%d\n" "Containers running" "$total_containers" "${#services[@]}"
    if [[ $total_containers -gt 0 ]]; then
        printf "  %-20s: %.2f%%\n" "Total CPU usage" "$total_cpu"
        printf "  %-20s: %.2f MiB\n" "Total memory usage" "$total_memory"
    fi

    # Calculate total disk usage for the stack
    echo ""
    echo "Disk usage by resource type:"
    echo "$(printf '─%.0s' {1..30})"

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"

    # Images
    local image_ids=()
    mapfile -t image_ids < <(docker images --filter "$project_filter" -q 2>/dev/null || true)
    local total_image_size=0

    for image_id in "${image_ids[@]}"; do
        [[ -z "$image_id" ]] && continue
        local size
        size=$(docker inspect --format='{{.Size}}' "$image_id" 2>/dev/null || echo "0")
        total_image_size=$((total_image_size + size))
    done

    if [[ $total_image_size -gt 0 ]]; then
        local human_size
        human_size=$(echo "$total_image_size" | awk '{printf "%.2f MB", $1/1024/1024}')
        printf "  %-15s: %s (%d images)\n" "Images" "$human_size" "${#image_ids[@]}"
    else
        printf "  %-15s: %s\n" "Images" "0 MB (not built)"
    fi

    # Volumes
    local volume_count
    volume_count=$(docker volume ls --filter "$project_filter" -q 2>/dev/null | wc -l)

    if [[ $volume_count -gt 0 ]]; then
        local volume_size=0
        while read -r volume_name; do
            [[ -z "$volume_name" ]] && continue
            local mountpoint
            mountpoint=$(docker volume inspect --format='{{.Mountpoint}}' "$volume_name" 2>/dev/null || echo "")
            if [[ -n "$mountpoint" ]] && [[ -d "$mountpoint" ]]; then
                local vol_size
                vol_size=$(du -sb "$mountpoint" 2>/dev/null | awk '{print $1}' || echo "0")
                volume_size=$((volume_size + vol_size))
            fi
        done < <(docker volume ls --filter "$project_filter" -q 2>/dev/null)

        if [[ $volume_size -gt 0 ]]; then
            local human_size
            human_size=$(echo "$volume_size" | awk '{printf "%.2f MB", $1/1024/1024}')
            printf "  %-15s: %s (%d volumes)\n" "Volumes" "$human_size" "$volume_count"
        else
            printf "  %-15s: %s (%d volumes)\n" "Volumes" "unknown size" "$volume_count"
        fi
    else
        printf "  %-15s: %s\n" "Volumes" "0 MB (none)"
    fi

    # Networks
    local network_count
    network_count=$(docker network ls --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %s (%d networks)\n" "Networks" "minimal" "$network_count"

    # Show all containers in the project
    echo ""
    echo "Project containers status:"
    echo "$(printf '─%.0s' {1..30})"

    local all_containers
    all_containers=$(docker ps -a --filter "$project_filter" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null || true)

    if [[ -n "$all_containers" ]]; then
        echo "$all_containers"
    else
        echo "  No containers found"
    fi
}

docker::ports() {
    # Display service port mappings.
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

    printf "%-25s %-25s %s\n" "SERVICE" "CONTAINER PORT" "HOST ACCESS"
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
                declare -A seen_ports
                while IFS= read -r port_line; do
                    [[ -z "$port_line" ]] && continue

                    local container_port host_port
                    container_port=$(echo "$port_line" | awk '{print $1}')
                    host_port=$(echo "$port_line" | awk '{print $3}')

                    local port_num="${host_port##*:}"
                    local key="${container_port}-${port_num}"

                    if [[ -z "${seen_ports[$key]:-}" ]]; then
                        seen_ports[$key]=1
                        printf "%-25s %-25s %s\n" \
                            "$service" \
                            "$container_port" \
                            "http://${host_ip}:${port_num} (localhost:${port_num})"
                    fi
                done <<< "$port_output"
                unset seen_ports
            else
                printf "%-25s %-25s %s\n" "$service" "─" "No exposed ports"
            fi
        else
            printf "%-25s %-25s %s\n" "$service" "─" "Not running"
        fi
    done

    if [[ $has_ports -eq 0 ]]; then
        echo ""
        log::info "No exposed ports found"
    fi

    echo ""
    log::info "Host IP: $host_ip"
}

docker::ports-check() {
    # Check port availability.
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
        log::info "$busy_ports port(s) are busy"
    fi
}

# --- Resource Listing ---
docker::_list_resources() {
    # List Docker resources.
    local header="${1:-Project Resources}"

    log::info "$header"

    local project_filter="label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-}"

    local container_count
    container_count=$(docker ps -a --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Containers" "$container_count"

    local image_count
    image_count=$(docker images --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Images" "$image_count"

    local volume_count
    volume_count=$(docker volume ls --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Volumes" "$volume_count"

    local network_count
    network_count=$(docker network ls --filter "$project_filter" -q 2>/dev/null | wc -l)
    printf "  %-15s: %d\n" "Networks" "$network_count"
}

docker::get_service_image() {
    # Get image name for a service from compose files
    local service_name="$1"
    local compose_file="${2:-docker/compose/docker-compose.core.yml}"

    if [[ ! -f "$compose_file" ]]; then
        echo "unknown"
        return
    fi

    # Try to extract image from compose file
    local image_name
    image_name=$(awk -v service="$service_name" '
        $0 ~ "^[[:space:]]*" service ":" { in_service=1 }
        in_service && /^[[:space:]]*image:/ {
            gsub(/^[[:space:]]*image:[[:space:]]*/, "", $0)
            gsub(/^["'\'']|["'\'']$/, "", $0)
            print $0
            exit
        }
        /^[[:space:]]*[a-zA-Z]/ && !/^[[:space:]]*#/ && $0 !~ "^[[:space:]]*" service ":" {
            if (in_service) exit
        }
    ' "$compose_file")

    if [[ -n "$image_name" ]]; then
        echo "$image_name"
    else
        # Try from extends
        local extends
        extends=$(awk -v service="$service_name" '
            $0 ~ "^[[:space:]]*" service ":" { in_service=1 }
            in_service && /^[[:space:]]*extends:/ {
                getline
                if (/file:/) {
                    gsub(/.*file:[[:space:]]*/, "", $0)
                    gsub(/^["'\'']|["'\'']$/, "", $0)
                    file=$0
                    getline
                    if (/service:/) {
                        gsub(/.*service:[[:space:]]*/, "", $0)
                        gsub(/^["'\'']|["'\'']$/, "", $0)
                        print file ":" $0
                        exit
                    }
                }
            }
        ' "$compose_file")

        if [[ -n "$extends" ]]; then
            local extends_file="${extends%:*}"
            local extends_service="${extends#*:}"
            docker::get_service_image "$extends_service" "$extends_file"
        else
            echo "unknown"
        fi
    fi
}

# --- Help ---
docker::help() {
    # Display help information.
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
  ports                 Show port mappings
  ports-check           Check port availability

Cleanup:
  clean [TARGETS...]    Clean specific resources
                        (containers, images, volumes, networks, cache, all)

Interactive:
  logs [SERVICE...]     View logs
  shell [SERVICE]       Enter container shell

Validation:
  validate              Validate configuration
EOF
}

# --- Main Dispatcher ---
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
        ps|stats|df|ports)
            docker::$cmd "${remaining_args[@]}"
            ;;
        ports-check)
            docker::ports-check "${remaining_args[@]}"
            ;;
        logs|shell)
            docker::$cmd "${remaining_args[@]}"
            ;;
        validate)
            docker::validate "${remaining_args[@]}"
            ;;
        help|--help|-h)
            docker::help
            ;;
        *)
            log::error "Unknown command: $cmd"
            echo "Use 'help' for usage information"
            return 1
            ;;
    esac
}

# --- Execute Main ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
