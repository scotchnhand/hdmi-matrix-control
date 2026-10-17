FROM python:3.12-slim

LABEL org.opencontainers.image.title="HDMI Matrix UI" \
      org.opencontainers.image.description="LAN control surface for a generic 4x2 HDMI matrix" \
      org.opencontainers.image.source="https://github.com/scotchnhand/hdmi-matrix-control"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY hdmi-matrix-ui/backend /app/backend
COPY hdmi-matrix-ui/frontend /app/frontend

RUN chown -R app:app /app

USER app
WORKDIR /app/backend

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/healthz', timeout=3)"

CMD ["python", "server.py"]
