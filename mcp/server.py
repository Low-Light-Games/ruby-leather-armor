"""MCP sidecar for the GM AI Rails app.

Exposes read-only tools that proxy to /api/mcp/* on the Rails container
over the internal docker network. Bearer-token authenticated end-to-end:
the same token clients present to this server is forwarded to Rails.
"""
from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Mount, Route

BEARER_TOKEN = os.environ["MCP_BEARER_TOKEN"]
RAILS_URL = os.environ.get("APP_INTERNAL_URL", "http://app:3000")

# DNS-rebinding allowlist for the FastMCP Streamable HTTP transport. Bearer
# auth is the real gate; this is belt-and-suspenders. Defaults cover dev
# (localhost) — prod sets MCP_ALLOWED_HOSTS via .env to include the public host.
_ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get("MCP_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",")
    if h.strip()
]
_TRANSPORT_SECURITY = TransportSecuritySettings(
    enable_dns_rebinding_protection=True,
    allowed_hosts=_ALLOWED_HOSTS,
)

mcp = FastMCP("gm-prod", instructions="Read-only access to GM AI production data.")

_rails: httpx.AsyncClient | None = None


def _client() -> httpx.AsyncClient:
    if _rails is None:
        raise RuntimeError("HTTP client not initialized — server not started via lifespan")
    return _rails


async def _get(path: str, **params: Any) -> Any:
    clean = {k: v for k, v in params.items() if v is not None}
    r = await _client().get(path, params=clean)
    if r.status_code == 404:
        return {"error": "not_found", "path": path, "params": clean}
    r.raise_for_status()
    return r.json()


# --- Tools -----------------------------------------------------------------

@mcp.tool()
async def find_user(email: str | None = None, id: int | None = None) -> Any:
    """Find a user by email or numeric id. Exactly one of `email` or `id` is required."""
    if (email is None) == (id is None):
        return {"error": "invalid_arguments", "detail": "Provide exactly one of `email` or `id`."}
    return await _get("/api/mcp/users/find", email=email, id=id)


@mcp.tool()
async def get_user(id: int) -> Any:
    """Fetch a user by id."""
    return await _get(f"/api/mcp/users/{id}")


@mcp.tool()
async def list_stories(
    user_id: int | None = None,
    include_hidden: bool = False,
    limit: int = 25,
) -> Any:
    """List stories ordered by recent update. Respects hidden_from_players unless include_hidden=True."""
    return await _get(
        "/api/mcp/stories",
        user_id=user_id,
        include_hidden="1" if include_hidden else None,
        limit=limit,
    )


@mcp.tool()
async def get_story(id: int) -> Any:
    """Fetch a story including premise and opening_message."""
    return await _get(f"/api/mcp/stories/{id}")


@mcp.tool()
async def list_adventures(
    story_id: int | None = None,
    user_id: int | None = None,
    limit: int = 25,
) -> Any:
    """List adventures, most recently updated first. Filter by story_id and/or user_id."""
    return await _get(
        "/api/mcp/adventures",
        story_id=story_id,
        user_id=user_id,
        limit=limit,
    )


@mcp.tool()
async def get_adventure(id: int) -> Any:
    """Fetch an adventure with current_location and DM settings."""
    return await _get(f"/api/mcp/adventures/{id}")


@mcp.tool()
async def list_adventure_messages(
    adventure_id: int,
    since: str | None = None,
    limit: int = 50,
) -> Any:
    """List messages for an adventure in chronological order. `since` is ISO8601."""
    return await _get(
        f"/api/mcp/adventures/{adventure_id}/messages",
        since=since,
        limit=limit,
    )


@mcp.tool()
async def get_adventure_message(id: int) -> Any:
    """Fetch one adventure message."""
    return await _get(f"/api/mcp/adventure_messages/{id}")


@mcp.tool()
async def list_feedback(
    user_id: int | None = None,
    since: str | None = None,
    limit: int = 25,
) -> Any:
    """List feedback rows newest-first. `since` is ISO8601."""
    return await _get(
        "/api/mcp/feedbacks",
        user_id=user_id,
        since=since,
        limit=limit,
    )


@mcp.tool()
async def list_play_logs(
    adventure_id: int | None = None,
    status: str | None = None,
    event_type: str | None = None,
    registry_entry_uuid: str | None = None,
    limit: int = 50,
) -> Any:
    """List PlayLog rows newest-first with optional filters."""
    return await _get(
        "/api/mcp/play_logs",
        adventure_id=adventure_id,
        status=status,
        event_type=event_type,
        registry_entry_uuid=registry_entry_uuid,
        limit=limit,
    )


@mcp.tool()
async def list_play_log_pipelines(limit: int = 50) -> Any:
    """List play log pipelines (grouped by registry_entry_uuid) with aggregate stats."""
    return await _get("/api/mcp/play_logs/pipelines", limit=limit)


# --- ASGI app + bearer middleware -----------------------------------------

class BearerAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/healthz":
            return await call_next(request)
        header = request.headers.get("authorization", "")
        if header != f"Bearer {BEARER_TOKEN}":
            return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)


async def healthz(_: Request) -> PlainTextResponse:
    return PlainTextResponse("ok")


# FastMCP's streamable_http_app needs its session_manager running for the
# lifetime of the parent app — mounting alone isn't enough. We co-own the
# httpx client lifecycle here too so it's properly closed on shutdown.
@asynccontextmanager
async def lifespan(_app: Starlette):
    global _rails
    _rails = httpx.AsyncClient(
        base_url=RAILS_URL,
        headers={"Authorization": f"Bearer {BEARER_TOKEN}"},
        timeout=20.0,
    )
    try:
        async with mcp.session_manager.run():
            yield
    finally:
        await _rails.aclose()
        _rails = None


app = Starlette(
    routes=[
        Route("/healthz", healthz),
        Mount("/", app=mcp.streamable_http_app(transport_security=_TRANSPORT_SECURITY)),
    ],
    middleware=[Middleware(BearerAuthMiddleware)],
    lifespan=lifespan,
)
