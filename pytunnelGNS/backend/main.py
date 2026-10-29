"""FastAPI Control Plane for PyTunnel Studio with CSRF defense, DNS rebinding guard, and i18n error handlers."""
from contextlib import asynccontextmanager
import asyncio
import logging
import os
import secrets

from fastapi import FastAPI, Request, status
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.templating import Jinja2Templates

from backend.api.routes import router as api_router
from backend.core.assets import static_url
from backend.core.config import (
    ALLOWED_DASHBOARD_HOSTS,
    CONTROL_PLANE_RATE_LIMIT,
    DASHBOARD_PORT,
    STATIC_DIR,
    TEMPLATES_DIR,
)
from backend.core.errors import AppError
from backend.core.i18n import normalize_lang, t
from backend.core.security import RequestRateLimiter
from backend.services.tunnel_manager import global_tunnel_manager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("pytunnel.main")

# Ephemeral CSRF token generated on server startup
SESSION_CSRF_TOKEN = secrets.token_hex(24)
control_plane_limiter = RequestRateLimiter(**CONTROL_PLANE_RATE_LIMIT)


class SecurityMiddleware(BaseHTTPMiddleware):
    """Guards against DNS Rebinding attacks and Cross-Site Request Forgery."""

    async def dispatch(self, request: Request, call_next):
        # 1. DNS Rebinding Guard
        host_header = request.headers.get("host", "").lower()
        host_without_port = host_header.split(":")[0]

        allowed = getattr(request.app.state, "allowed_hosts", ALLOWED_DASHBOARD_HOSTS)
        if host_without_port not in allowed:
            logger.warning("Rejected Host header (DNS Rebinding protection): %s", host_header)
            return JSONResponse(
                status_code=status.HTTP_403_FORBIDDEN,
                content={"error_code": "error.host_forbidden", "message": "Forbidden: DNS Rebinding Protection."},
            )

        # 2. Anti-CSRF Guard for state-changing API endpoints (terminal-logs is exempt for internal server log streaming)
        if request.url.path.startswith("/api/") and request.method in ("POST", "PUT", "DELETE", "PATCH") and not request.url.path.startswith("/api/terminal-logs"):
            token = request.headers.get("x-pytunnel-token")
            if not token or not secrets.compare_digest(token, SESSION_CSRF_TOKEN):
                logger.warning("Rejected request lacking valid CSRF token: %s %s", request.method, request.url.path)
                lang = normalize_lang(request.headers.get("accept-language"))
                return JSONResponse(
                    status_code=status.HTTP_403_FORBIDDEN,
                    content={"error_code": "error.csrf_failed", "message": t(lang, "error.csrf_failed")},
                )

        # 3. IP Rate Limiter for Control Plane
        client_ip = request.client.host if request.client else "127.0.0.1"
        allowed_req, retry_after = control_plane_limiter.check(client_ip)
        if not allowed_req:
            lang = normalize_lang(request.headers.get("accept-language"))
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                headers={"Retry-After": str(retry_after)},
                content={"error_code": "error.rate_limited", "message": t(lang, "error.rate_limited", seconds=retry_after)},
            )

        response = await call_next(request)
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("PyTunnel Control Plane starting on http://127.0.0.1:%d", DASHBOARD_PORT)
    app.state.csrf_token = SESSION_CSRF_TOKEN

    # Start idle monitor for safe automatic shutdown when all tabs are closed and 0 tunnels active
    from backend.services.lifecycle import global_idle_monitor
    await global_idle_monitor.start(lambda: len(global_tunnel_manager.tunnels))

    # Auto-open browser only when server is actively bound and listening
    if not os.environ.get("PYTUNNEL_NO_BROWSER"):
        async def _open_browser_when_ready():
            await asyncio.sleep(0.4)
            import time
            import webbrowser
            try:
                webbrowser.open(f"http://127.0.0.1:{DASHBOARD_PORT}/?_t={int(time.time())}")
            except Exception:
                pass
        asyncio.create_task(_open_browser_when_ready())

    yield
    logger.info("PyTunnel Control Plane shutting down: terminating all tunnels...")
    await global_idle_monitor.stop()
    await global_tunnel_manager.kill_all()


app = FastAPI(
    title="PyTunnel Studio",
    version="5.3.1",
    lifespan=lifespan,
)

app.state.csrf_token = SESSION_CSRF_TOKEN
app.add_middleware(SecurityMiddleware)

if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

app.include_router(api_router)


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError):
    lang = normalize_lang(request.headers.get("accept-language"))
    message = t(lang, exc.code, **exc.params)
    return JSONResponse(
        status_code=exc.status,
        content={"error_code": exc.code, "message": message, "params": exc.params},
    )


templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
templates.env.globals["static_url"] = static_url


@app.get("/", response_class=HTMLResponse)
async def serve_index(request: Request):
    index_file = TEMPLATES_DIR / "index.html"
    if not index_file.exists():
        return HTMLResponse("<h1>PyTunnel Studio</h1><p>frontend/templates/index.html is missing.</p>")
    response = templates.TemplateResponse(request=request, name="index.html")
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response
