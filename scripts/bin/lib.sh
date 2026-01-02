#!/bin/bash
# =============================================================================
# CORE LIBRARY - Logging, assertions and utilities
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# PATH CONSTANTS
# -----------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$BIN_DIR/../.." && pwd)"

# -----------------------------------------------------------------------------
# COLOR CONSTANTS
# -----------------------------------------------------------------------------
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GRAY='\033[0;90m'
readonly COLOR_BOLD='\033[1m'

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log::header()  { printf "${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$1"; }
log::info()    { printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$1"; }
log::success() { printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$1"; }
log::warn()    { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$1" >&2; }
log::error()   { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$1" >&2; }
log::debug()   { [[ "${DEBUG:-0}" == "1" ]] && printf "${COLOR_GRAY}[DEBUG]${COLOR_RESET} %s\n" "$1"; }
log::fatal()   { log::error "$1"; exit 1; }

# -----------------------------------------------------------------------------
# PATH HELPERS
# -----------------------------------------------------------------------------
bin::path()  { echo "$BIN_DIR"; }
root::path() { echo "$PROJECT_ROOT"; }
