FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY server.py .

EXPOSE 8080

# --proxy-headers tells uvicorn to honor X-Forwarded-Proto/Host/For from the
# nginx terminating TLS on the EC2; without it, scheme-aware redirects use
# `http://` (breaking MCP clients across the redirect) and the forwarded Host
# is rejected as Invalid. The container only listens on 127.0.0.1:8080 on the
# host so allowing any upstream IP is safe — nginx is the only thing reachable.
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
