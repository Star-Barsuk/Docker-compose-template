# =============================================================================
# BUILDER STAGE
# =============================================================================
FROM python:3.14-slim-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv
RUN chmod +x /bin/uv

WORKDIR /app

# uv optimizations
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_CACHE_DIR=/root/.cache/uv \
    UV_PYTHON_DOWNLOADS=0 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Create virtual environment as root first
RUN uv venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv"

# Install dependencies (cached layer)
COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=cache,target=$UV_CACHE_DIR \
    uv sync --locked --no-dev --no-install-project

# Copy source and install project
COPY src/ src/
COPY scripts/ scripts/
RUN --mount=type=cache,target=$UV_CACHE_DIR \
    uv sync --locked --no-dev

# Fix permissions for runtime stage
RUN chmod -R go+rX /app/.venv && \
    find /app/.venv -type d -exec chmod go+rx {} \; && \
    chown -R 1000:1000 /app

# =============================================================================
# RUNTIME STAGE
# =============================================================================
FROM python:3.14-slim-bookworm AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with explicit UID/GID
RUN groupadd --system --gid 1000 appgroup && \
    useradd --system --no-create-home --uid 1000 --gid 1000 --shell /usr/sbin/nologin appuser

WORKDIR /app

# Copy application with correct ownership from builder
COPY --from=builder /app /app

# Ensure proper permissions
RUN chown -R appuser:appgroup /app && \
    chmod -R go-w /app && \
    chmod +x /app/scripts/entrypoint.app.sh

# Python environment
ENV PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv" \
    PYTHONPATH="/app/src" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1

# Switch to non-root user
USER appuser

# Default command
CMD ["python", "-m", "src.main"]
