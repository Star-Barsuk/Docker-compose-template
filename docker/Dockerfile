# docker/Dockerfile

FROM python:3.14.2-slim-bookworm AS builder

# Copy latest uv from official Astral image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

WORKDIR /app

# uv optimizations
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1

# Cache dependencies (cacheable layer)
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project

# Copy source and finalize venv
COPY src/ src/
RUN uv sync --locked

# Runtime stage
FROM python:3.14.2-slim-bookworm

# Create non-root user
RUN useradd --system --no-create-home --uid 1000 --shell /usr/sbin/nologin appuser

# Copy app and venv
COPY --from=builder --chown=appuser:appuser /app /app

WORKDIR /app

# Activate venv
ENV PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv"

# Run as non-root
USER appuser

CMD ["python", "-m", "src.main"]
