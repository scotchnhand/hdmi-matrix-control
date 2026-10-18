# Web app image: the stdlib backend serving the static frontend.
# Configure with environment variables (MATRIX_HOST, MATRIX_USERNAME,
# MATRIX_PASSWORD, LISTEN_PORT) or mount a config.json at
# /app/backend/config.json. MATRIX_HOST=mock runs the demo matrix.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LISTEN_HOST=0.0.0.0 \
    LISTEN_PORT=8765

WORKDIR /app
COPY backend/ backend/
COPY frontend/ frontend/

RUN useradd --system --no-create-home matrix
USER matrix

EXPOSE 8765

# Python as PID 1 has no SIGTERM handler, so `docker stop` would wait out
# its timeout and SIGKILL. SIGINT raises KeyboardInterrupt, which
# server.py catches to exit cleanly.
STOPSIGNAL SIGINT

# Probe the static index, not /api/state: a health check must never poll
# the matrix, whose embedded HTTP server is fragile.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/' % os.environ.get('LISTEN_PORT', '8765'), timeout=4)"]

CMD ["python", "backend/server.py"]
