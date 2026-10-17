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
CMD ["python", "backend/server.py"]
