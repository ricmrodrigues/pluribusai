# PluribusAI — OSS image (SQLite or Postgres via env).
FROM python:3.12-slim

ARG PIP_INDEX_URL=
ARG PIP_TRUSTED_HOST=

RUN if [ -n "$PIP_INDEX_URL" ]; then \
      pip install --no-cache-dir \
        --index-url "$PIP_INDEX_URL" \
        --trusted-host "${PIP_TRUSTED_HOST:-pypi.org}" \
        "pg8000>=1.30" "boto3>=1.34"; \
    else \
      pip install --no-cache-dir "pg8000>=1.30" "boto3>=1.34"; \
    fi

WORKDIR /app
COPY server.py store.py /app/

ENV PLURIBUSAI_STORE=sqlite \
    PLURIBUSAI_HTTP_PORT=8787 \
    PLURIBUSAI_DB=/data/queue.db

RUN mkdir -p /data
VOLUME /data
EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=4s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8787/health',timeout=3).status==200 else 1)"

CMD ["python3", "server.py"]