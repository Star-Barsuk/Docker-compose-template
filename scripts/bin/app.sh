#!/bin/bash
# =============================================================================
# APPLICATION MANAGEMENT SCRIPT
# =============================================================================

set -euo pipefail

# --- Source shared library ---
source "$(dirname "$0")/lib.sh"

# --- Constants ---
readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly PYTHON_MODULE="src.main"
readonly REQUIREMENTS_FILE="pyproject.toml"
readonly RUFF_CONFIG="pyproject.toml"

# --- Tool Detection ---
app::detect_tools() {
    # Check if required tools (python3, pip, uv) are installed.
    local tools=("python3" "pip" "uv")
    local missing=()

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log::error "Missing tools: ${missing[*]}"
        echo "Install missing tools and try again."
        return 1
    fi

    return 0
}

# --- Virtual Environment Management ---
app::venv::path() {
    # Return the path to the virtual environment.
    echo "$PROJECT_ROOT/.venv"
}

app::venv::exists() {
    # Check if the virtual environment exists.
    [[ -d "$(app::venv::path)" ]] && [[ -f "$(app::venv::path)/bin/activate" ]]
}

app::venv::activate() {
    # Activate the virtual environment.
    if app::venv::exists; then
        source "$(app::venv::path)/bin/activate"
        return 0
    else
        return 1
    fi
}

app::venv::create() {
    # Create a new virtual environment.
    local venv_path="$(app::venv::path)"

    if app::venv::exists; then
        log::info "Virtual environment already exists at $venv_path"
        return 0
    fi

    log::header "Creating virtual environment with uv"

    local python_version="3.14"

    if uv python find "$python_version" >/dev/null 2>&1; then
        log::info "Using Python $python_version from uv"
        if uv venv --python "$python_version" "$venv_path" 2>/dev/null; then
            log::success "Virtual environment created at $venv_path with Python $python_version"
            return 0
        fi
    fi

    log::info "Falling back to system Python"
    if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 14) else 1)" 2>/dev/null; then
        log::error "Python 3.14+ is required"
        log::info "Current version: $(python3 --version 2>/dev/null || echo 'Not found')"
        log::info "Available via uv: $(uv python list | grep -E '^cpython-3\.(1[3-9]|2[0-9])' | head -5 | sed 's/^/  /')"
        return 1
    fi

    if python3 -m venv "$venv_path" 2>/dev/null; then
        log::success "Virtual environment created at $venv_path"
        return 0
    else
        log::error "Failed to create virtual environment."
        return 1
    fi
}

# --- Dependency Management ---
app::deps::check() {
    # Check if all dependencies are installed.
    log::header "Checking dependencies"

    if ! app::venv::exists; then
        log::warn "Virtual environment not found"
        echo "Run 'make app-sync' first."
        return 1
    fi

    app::venv::activate || return 1

    log::info "Python environment:"
    echo "  Version: $(python --version 2>&1)"
    echo "  Path: $(which python)"
    echo "  Virtual env: $(app::venv::path)"

    echo ""
    log::info "Checking required tools..."
    local missing=0

    if command -v pip >/dev/null 2>&1; then
        log::success "pip: $(pip --version | cut -d' ' -f2)"
    else
        log::error "pip not found in virtual environment"
        missing=$((missing + 1))
    fi

    if command -v ruff >/dev/null 2>&1; then
        log::success "ruff: $(ruff --version 2>/dev/null | head -1 || echo 'found')"
    else
        log::warn "ruff not found (install with: make app-sync-dev)"
    fi

    echo ""
    log::info "Checking Python version compatibility..."
    python3 -c "
import sys
version = sys.version_info
print(f'  Python {version.major}.{version.minor}.{version.micro}')
if version >= (3, 14):
    print('  ✅ Meets requirement (>=3.14)')
else:
    print(f'  ❌ Below minimum requirement (3.14+)')
    sys.exit(1)
" || missing=$((missing + 1))

    return $missing
}

# --- UV-Specific Commands ---
app::uv::sync() {
    # Sync dependencies using uv.
    log::header "Syncing dependencies with uv"

    if ! app::venv::exists; then
        app::venv::create || return 1
    fi

    app::venv::activate || return 1

    local with_dev="${1:-0}"
    local uv_args=("sync")

    if [[ "$with_dev" == "1" ]]; then
        uv_args+=("--all-extras")
    fi

    log::info "Running uv ${uv_args[*]}"

    if uv "${uv_args[@]}"; then
        log::success "Dependencies synced successfully"

        echo ""
        log::info "Installed packages:"
        uv pip list | grep -E "(Package|----|ruff|my-awesome-app)" | head -10
    else
        log::error "Failed to sync dependencies"
        return 1
    fi
}

# --- Application Commands ---
app::run() {
    # Run the application.
    log::header "Running Application"

    if ! app::venv::exists; then
        log::warn "Virtual environment not found"
        echo "Run 'make app-sync' first"
        return 1
    fi

    app::venv::activate || return 1

    app::deps::check >/dev/null 2>&1 || log::warn "Some dependencies may be missing"

    log::info "Starting $PYTHON_MODULE..."
    echo "$(printf '=%.0s' {1..60})"

    cd "$PROJECT_ROOT" && python -m "$PYTHON_MODULE"
}

app::shell() {
    # Start a Python REPL with project context.
    log::header "Python Shell"

    if ! app::venv::exists; then
        log::error "Virtual environment not found"
        echo "Run 'make app-install' first"
        return 1
    fi

    app::venv::activate || return 1

    log::info "Starting Python REPL with project context..."
    echo "  Project root: $PROJECT_ROOT"
    echo "  Python: $(python --version)"
    echo "  Virtual env: $(app::venv::path)"
    echo ""
    echo "Available imports:"
    echo "  import sys, os"
    echo "  from src.main import main"
    echo ""

    cd "$PROJECT_ROOT" && python
}

# --- Code Quality Tools ---
app::lint() {
    # Lint code using Ruff.
    log::header "Linting Code (Ruff)"

    if ! command -v ruff >/dev/null 2>&1; then
        log::error "ruff not found in PATH"
        echo "Install with: make app-sync-dev"
        return 1
    fi

    local args=("check" "--config" "$RUFF_CONFIG")

    if [[ $# -gt 0 ]]; then
        args+=("$@")
    else
        args+=("src/" "scripts/")
    fi

    log::info "Running ruff ${args[*]}"
    echo ""

    if ruff "${args[@]}"; then
        echo ""
        log::success "Linting passed!"
    else
        echo ""
        log::warn "Linting found issues"
        return 1
    fi
}

app::format() {
    # Format code using Ruff.
    log::header "Formatting Code (Ruff)"

    if ! command -v ruff >/dev/null 2>&1; then
        log::error "ruff not found in PATH"
        echo "Install with: make app-sync-dev"
        return 1
    fi

    local args=("format" "--config" "$RUFF_CONFIG")

    if [[ $# -gt 0 ]]; then
        args+=("$@")
    else
        args+=("src/" "scripts/")
    fi

    log::info "Running ruff ${args[*]}"
    echo ""

    if ruff "${args[@]}"; then
        echo ""
        log::success "Formatting completed!"
    else
        echo ""
        log::error "Formatting failed"
        return 1
    fi
}

app::check() {
    # Run comprehensive code checks.
    log::header "Checking Code (Ruff comprehensive)"

    if ! command -v ruff >/dev/null 2>&1; then
        log::error "ruff not found in PATH"
        echo "Install with: make app-sync-dev"
        return 1
    fi

    log::info "1. Checking formatting..."
    if ruff format --check --config "$RUFF_CONFIG" src/ scripts/ 2>/dev/null; then
        log::success "  Formatting is correct"
    else
        log::warn "  Formatting issues found"
    fi

    echo ""

    log::info "2. Running linter..."
    local lint_output
    lint_output=$(ruff check --config "$RUFF_CONFIG" src/ scripts/ 2>&1)
    local lint_status=$?

    if [[ $lint_status -eq 0 ]]; then
        log::success "  No linting issues found"
    else
        echo "$lint_output" | sed 's/^/  /'
        log::warn "  Linting issues found"
    fi

    echo ""

    if [[ $lint_status -eq 0 ]]; then
        log::success "All checks passed!"
        return 0
    else
        log::info "Some checks failed. Run 'make app-format' to auto-fix formatting issues."
        return 1
    fi
}

app::fix() {
    # Auto-fix code issues.
    log::header "Fixing Code Issues (Ruff)"

    if ! command -v ruff >/dev/null 2>&1; then
        log::error "ruff not found in PATH"
        echo "Install with: make app-sync-dev"
        return 1
    fi

    log::info "1. Formatting code..."
    if app::format "$@" >/dev/null 2>&1; then
        log::success "  Formatting applied"
    else
        log::warn "  Formatting had issues"
    fi

    echo ""

    log::info "2. Fixing linting issues..."
    local args=("check" "--fix" "--config" "$RUFF_CONFIG")

    if [[ $# -gt 0 ]]; then
        args+=("$@")
    else
        args+=("src/" "scripts/")
    fi

    if ruff "${args[@]}"; then
        log::success "  Auto-fixes applied"
    else
        log::warn "  Some issues require manual fixing"
    fi

    echo ""
    log::info "3. Running final check..."
    if app::check >/dev/null 2>&1; then
        log::success "All issues fixed!"
    else
        log::info "Some issues remain. Check with 'make app-check'"
    fi
}

app::clean() {
    # Clean Python artifacts.
    log::header "Cleaning Python Artifacts"

    local to_remove=(
        ".venv"
        "__pycache__"
        "*.pyc"
        "*.pyo"
        "*.pyd"
        ".Python"
        ".coverage"
        ".pytest_cache"
        ".ruff_cache"
        ".mypy_cache"
        ".hypothesis"
        "htmlcov"
        ".tox"
        ".eggs"
        "*.egg-info"
        "build"
        "dist"
    )

    local removed_count=0

    for pattern in "${to_remove[@]}"; do
        local matches
        matches=$(find "$PROJECT_ROOT" -name "$pattern" -type d 2>/dev/null | wc -l)
        if [[ $matches -gt 0 ]]; then
            log::info "Removing $pattern..."
            find "$PROJECT_ROOT" -name "$pattern" -type d -exec rm -rf {} + 2>/dev/null || true
            removed_count=$((removed_count + matches))
        fi
    done

    local pyc_files
    pyc_files=$(find "$PROJECT_ROOT" -name "*.pyc" -type f 2>/dev/null | wc -l)
    if [[ $pyc_files -gt 0 ]]; then
        log::info "Removing $pyc_files .pyc files..."
        find "$PROJECT_ROOT" -name "*.pyc" -type f -delete 2>/dev/null
        removed_count=$((removed_count + pyc_files))
    fi

    if [[ $removed_count -gt 0 ]]; then
        log::success "Removed $removed_count artifacts"
    else
        log::info "No artifacts to clean"
    fi
}

# --- Help ---
app::help() {
    # Display help information.
    cat << "EOF"
Application Management Commands

Usage: app.sh COMMAND [ARGS...]

Development Environment:
  check-deps         Check dependency status
  clean              Clean build artifacts and caches

UV-Specific:
  uv-sync [--dev]    Sync dependencies with uv (use --dev for dev deps)

Application:
  run                Run the application
  shell              Start Python REPL with project context

Code Quality (Ruff):
  lint [PATHS]       Lint code (default: src/ scripts/)
  format [PATHS]     Format code
  check [PATHS]      Comprehensive check (format + lint)
  fix [PATHS]        Auto-fix issues (format + fix)
EOF
}

# --- Main Dispatcher ---
main() {
    local command="${1:-help}"

    case "$command" in
        check-deps)
            app::deps::check
            ;;
        clean)
            app::clean
            ;;
        uv-sync)
            local with_dev=0
            [[ "${2:-}" == "--dev" ]] && with_dev=1
            app::uv::sync "$with_dev"
            ;;
        run)
            app::run
            ;;
        shell)
            app::shell
            ;;
        lint)
            shift
            app::lint "$@"
            ;;
        format)
            shift
            app::format "$@"
            ;;
        check)
            shift
            app::check "$@"
            ;;
        fix)
            shift
            app::fix "$@"
            ;;
        help|--help|-h)
            app::help
            ;;
        *)
            log::error "Unknown command: $command"
            echo ""
            app::help
            exit 1
            ;;
    esac
}

# --- Execute Main ---
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
