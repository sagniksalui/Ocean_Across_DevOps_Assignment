FROM python:3.12-alpine

LABEL org.opencontainers.image.title="Ocean Across placeholder backend" \
      org.opencontainers.image.description="Non-production service for CI/CD demonstration"

ENV PORT=8080 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN addgroup -S app && adduser -S -G app app

WORKDIR /app

COPY --chown=app:app src/app.py ./app.py

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)" || exit 1

CMD ["python", "app.py"]
