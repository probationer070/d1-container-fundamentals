# syntax=docker/dockerfile:1.7
# =============================================================================
# Primary production image: multi-stage, slim base, non-root, healthcheck.
# Build:  docker build -t d1-health-api:slim .
# =============================================================================

# ---- builder: compile deps into an isolated venv -----------------------------
FROM python:3.12-slim AS builder
WORKDIR /app
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Copy ONLY the dependency manifest first. This layer is cached and reused as
# long as requirements.txt is unchanged, so editing app code does NOT trigger a
# full reinstall. (Cache ordering is the single biggest build-speed lever.)
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ---- runtime: copy only the venv + app, drop all build tooling ---------------
FROM python:3.12-slim AS runtime

# Version metadata is baked in at build time so the image can report itself
# (GET /version) without depending on external env at runtime.
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Run as an unprivileged user. A container breakout is far less dangerous when
# the process is not root.
RUN groupadd --system app && useradd --system --gid app --no-create-home app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app/ ./app/
USER app

EXPOSE 8000

# Shell-free probe works in slim and (later) distroless alike.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "app/healthcheck.py"]

# Exec form (no shell) => signals (SIGTERM) reach uvicorn for clean shutdown.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
