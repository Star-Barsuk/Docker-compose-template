#!/bin/bash

# =============================================================================
# RESOURCE OPTIMIZATION SCRIPT v2.1
# =============================================================================

# Ensure LOG_LEVEL exists before strict mode
: "${LOG_LEVEL:=INFO}"

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION (EXTENSIBLE)
# ─────────────────────────────────────────────────────────────────────────────

PROFILES=(
  "dev:Development"
  "prod:Production"
  "local:LocalDB"
  "test:Testing"
)

# Global scaling based on RAM
SCALE_RAM_LT_4=0.8
SCALE_RAM_4_8=1.0
SCALE_RAM_8_16=1.2
SCALE_RAM_GT_16=1.5

# Profile-level scaling
declare -A PROFILE_SCALE=(
  [dev]=1.0
  [prod]=1.0
  [local]=1.0
  [test]=1.0
)

# Variable-level scaling
declare -A VARIABLE_SCALE=(
  [APP_CPU_LIMIT]=1.0
  [APP_MEMORY_LIMIT]=1.0
  [DB_CPU_LIMIT]=1.0
  [DB_MEMORY_LIMIT]=1.0
  [PGADMIN_CPU_LIMIT]=1.0
  [PGADMIN_MEMORY_LIMIT]=1.0
)

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4

declare -A LOG_LEVEL_MAP=(
  [ERROR]=1 [WARN]=2 [INFO]=3 [DEBUG]=4
)

CURRENT_LOG_LEVEL=${LOG_LEVEL_MAP[${LOG_LEVEL^^}]:-${LOG_LEVEL_INFO}}

log_error()   { [[ $CURRENT_LOG_LEVEL -ge 1 ]] && echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { [[ $CURRENT_LOG_LEVEL -ge 2 ]] && echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_info()    { [[ $CURRENT_LOG_LEVEL -ge 3 ]] && echo -e "${BLUE}[INFO]${NC}  $1"; }
log_debug()   { [[ $CURRENT_LOG_LEVEL -ge 4 ]] && echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCY CHECK
# ─────────────────────────────────────────────────────────────────────────────

validate_dependencies() {
  for cmd in bc free nproc sed grep awk; do
    command -v "$cmd" &>/dev/null || {
      log_error "Missing dependency: $cmd"
      exit 1
    }
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM INFO
# ─────────────────────────────────────────────────────────────────────────────

get_system_info() {
  TOTAL_CPUS=$(nproc)
  TOTAL_MEMORY=$(free -b | awk '/^Mem:/{print $2}')
  MEMORY_GB=$((TOTAL_MEMORY / 1073741824))

  if (( MEMORY_GB < 4 )); then
    RESOURCE_FACTOR=$SCALE_RAM_LT_4
  elif (( MEMORY_GB < 8 )); then
    RESOURCE_FACTOR=$SCALE_RAM_4_8
  elif (( MEMORY_GB < 16 )); then
    RESOURCE_FACTOR=$SCALE_RAM_8_16
  else
    RESOURCE_FACTOR=$SCALE_RAM_GT_16
  fi

  log_info "Detected system: ${TOTAL_CPUS} CPUs, ${MEMORY_GB}GB RAM"
  log_debug "Global RESOURCE_FACTOR=${RESOURCE_FACTOR}"
}

# ─────────────────────────────────────────────────────────────────────────────
# SCALING LOG OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

log_scaling_summary() {
  log_info "Scaling configuration:"

  log_info " Global scaling (RAM-based):"
  log_info "   <4GB=${SCALE_RAM_LT_4}, 4–8GB=${SCALE_RAM_4_8}, 8–16GB=${SCALE_RAM_8_16}, >16GB=${SCALE_RAM_GT_16}"

  log_info " Profile scaling:"
  for p in "${!PROFILE_SCALE[@]}"; do
    log_info "   ${p}=${PROFILE_SCALE[$p]}"
  done

  log_info " Variable scaling:"
  for v in "${!VARIABLE_SCALE[@]}"; do
    log_info "   ${v}=${VARIABLE_SCALE[$v]}"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# SCALING CALCULATION
# ─────────────────────────────────────────────────────────────────────────────

calc_final_factor() {
  local profile="$1"
  local variable="$2"

  local g="$RESOURCE_FACTOR"
  local p="${PROFILE_SCALE[$profile]:-1.0}"
  local v="${VARIABLE_SCALE[$variable]:-1.0}"

  echo "$g $p $v"
}

# ─────────────────────────────────────────────────────────────────────────────
# FORMATTERS
# ─────────────────────────────────────────────────────────────────────────────

format_cpu_value() {
  local value="$1" factor="$2"
  local num scaled

  num=$(sed 's/[^0-9.]//g' <<< "$value")
  [[ -z "$num" || "$num" == "0" ]] && echo "0.10" && return

  scaled=$(echo "$num * $factor" | bc -l)

  (( $(echo "$scaled > $TOTAL_CPUS" | bc -l) )) && scaled="$TOTAL_CPUS"
  (( $(echo "$scaled < 0.1" | bc -l) )) && scaled="0.10"

  printf "%.2f\n" "$scaled"
}

format_memory_value() {
  local value="$1" factor="$2"
  local num unit scaled

  num=$(sed -E 's/[^0-9].*$//' <<< "$value")
  unit=$(sed -E 's/^[0-9]+//' <<< "$value")
  unit=${unit:-M}

  num=$(sed 's/[^0-9]//g' <<< "$num")
  [[ -z "$num" || "$num" == "0" ]] && echo "64M" && return

  scaled=$(echo "$num * $factor" | bc -l | awk '{printf "%.0f",$1}')

  [[ "$unit" == "M" && "$scaled" -lt 64 ]] && scaled=64
  [[ "$unit" == "G" && "$scaled" -lt 1  ]] && scaled=1

  echo "${scaled}${unit}"
}

# ─────────────────────────────────────────────────────────────────────────────
# FILE UPDATE
# ─────────────────────────────────────────────────────────────────────────────

update_if_exists() {
  local file="$1" key="$2" value="$3"
  grep -q "^[[:space:]]*${key}=" "$file" || return 0
  sed -i "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
}

# ─────────────────────────────────────────────────────────────────────────────
# PROFILE PROCESSING
# ─────────────────────────────────────────────────────────────────────────────

optimize_profile() {
  local suffix="$1"
  local desc="$2"

  local template="${PROJECT_ROOT}/envs/.env.${suffix}.example"
  local output="${PROJECT_ROOT}/envs/.env.${suffix}.optimized"

  [[ -f "$template" ]] || {
    log_warning "Template not found: ${template}"
    return
  }

  cp "$template" "$output"
  log_info "Processing ${desc}"

  for var in "${!VARIABLE_SCALE[@]}"; do
    grep -q "^[[:space:]]*${var}=" "$template" || continue

    value=$(grep "^[[:space:]]*${var}=" "$template" | head -1 | cut -d= -f2)

    read g p v <<< "$(calc_final_factor "$suffix" "$var")"
    factor=$(echo "$g * $p * $v" | bc -l)

    if [[ "$var" == *_CPU_LIMIT ]]; then
      new_value=$(format_cpu_value "$value" "$factor")
    elif [[ "$var" == *_MEMORY_LIMIT ]]; then
      new_value=$(format_memory_value "$value" "$factor")
    else
      continue
    fi

    update_if_exists "$output" "$var" "$new_value"

    log_debug "$var: $value → $new_value (factor=$(printf "%.3f" "$factor") [g=$g × p=$p × v=$v])"
  done

  log_success ".env.${suffix}.optimized created"
}

# ───────────────────────────────────────────────────────────────
# MAIN
# ───────────────────────────────────────────────────────────────

main() {
  log_info "Resource Optimization Script v9.1"

  PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  mkdir -p "${PROJECT_ROOT}/envs"

  validate_dependencies
  get_system_info
  log_scaling_summary

  for entry in "${PROFILES[@]}"; do
    IFS=: read -r suffix desc <<< "$entry"
    optimize_profile "$suffix" "$desc"
  done

  log_success "Optimization complete"
}

trap 'log_error "Script failed at line $LINENO"' ERR
main "$@"
