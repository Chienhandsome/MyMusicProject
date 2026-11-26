# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim AS javascript

FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    YTDLP_JS_RUNTIME=node \
    PORT=8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg ca-certificates libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=javascript /usr/local/bin/node /usr/local/bin/node

WORKDIR /app
COPY requirements.txt ./
# Keep downloaded packages in BuildKit's cache, outside the final image.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN useradd --create-home --uid 10001 appuser \
    && install -d -o appuser -g appuser /app/downloads
COPY --chown=appuser:appuser yt_dlp_server/main.py yt_dlp_server/download_auth.py ./
USER appuser

# Fail the build early if an executable or shared runtime library is missing.
RUN node --version \
    && yt-dlp --version \
    && ffmpeg -version \
    && ffprobe -version \
    && python -c "import fastapi, uvicorn, download_auth"

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/openapi.json', timeout=3)"

CMD ["sh", "-c", "exec uvicorn main:app --workers 1 --host 0.0.0.0 --port \"${PORT:-8000}\""]


