# Read-only MongoDB demo API. Non-root, no secrets baked in.
FROM python:3.12-slim AS base

# PYTHONDONTWRITEBYTECODE prevents .pyc generation at runtime; no telemetry/buffering issues.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install runtime deps first for layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Create the non-root user BEFORE copying source so ownership can be set on copy.
RUN useradd --create-home --uid 10001 appuser

# Copy application source owned by the non-root user. Host files may be mode 600;
# COPY would otherwise carry that through and appuser could not read them.
COPY --chown=appuser:appuser app ./app

# Normalize read/traverse permissions on the copied application source only
# (files readable, directories traversable; no write bit added).
RUN chmod -R a+rX /app/app

USER appuser

EXPOSE 8080

# MONGODB_URI and API_KEY are provided at runtime (Secrets Manager in ECS),
# never built into the image. The container runs the ASGI server bound to 0.0.0.0.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
