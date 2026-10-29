import asyncio
import os
from fastapi import APIRouter, Request

from backend.api.schemas import CreateTunnelRequest, ParseRequest, RotateCodeRequest, ShortenLinkRequest, ToggleModeRequest
from backend.core.config import DASHBOARD_PORT
from backend.core.errors import AppError
from backend.core.i18n import MESSAGES, normalize_lang, t
from backend.core.parser import parse_target
from backend.services.engine import engine
from backend.services.tunnel_manager import global_tunnel_manager

router = APIRouter(prefix="/api")


@router.get("/status")
async def get_status(request: Request):
    csrf_token = getattr(request.app.state, "csrf_token", "")
    return {
        "status": "online",
        "dashboard_port": DASHBOARD_PORT,
        "engine": engine.status(),
        "active_tunnels": len(global_tunnel_manager.tunnels),
        "csrf_token": csrf_token,
    }


@router.get("/i18n")
async def get_i18n():
    """Return central catalog so frontend stays 100% in sync without duplicating text."""
    return MESSAGES


@router.post("/parse")
async def parse_input(req: ParseRequest, request: Request):
    """Validate target input and return detected port and path with localized messages."""
    lang = normalize_lang(request.headers.get("accept-language"))
    try:
        target = parse_target(req.raw_input)
        desc = t(lang, "launch.detected", port=target.port, path=target.path) if target.path else t(lang, "launch.detected_root", port=target.port)
        return {"valid": True, "port": target.port, "path": target.path, "description": desc}
    except AppError as exc:
        msg = t(lang, exc.code, **exc.params)
        return {"valid": False, "port": None, "path": "", "error_code": exc.code, "description": msg}


@router.get("/tunnels")
async def list_tunnels():
    return global_tunnel_manager.list_all()


@router.post("/tunnels")
async def create_tunnel(req: CreateTunnelRequest):
    target = parse_target(req.target_input)
    tunnel = await global_tunnel_manager.create_tunnel(target=target, is_public=req.is_public)
    return tunnel.to_dict()


@router.post("/tunnels/{port}/stop")
async def stop_tunnel(port: int):
    success = await global_tunnel_manager.stop_tunnel(port)
    if not success:
        raise AppError("error.tunnel_not_found", status=404, port=port)
    return {"status": "ok", "port": port}


@router.post("/tunnels/{port}/toggle-mode")
async def toggle_mode(port: int, req: ToggleModeRequest):
    tunnel = global_tunnel_manager.get(port)
    if not tunnel:
        raise AppError("error.tunnel_not_found", status=404, port=port)
    if not tunnel.proxy:
        raise AppError("error.tunnel_not_ready", status=503, port=port)

    tunnel.proxy.set_public(req.is_public, keep_sessions=req.keep_sessions)
    tunnel.is_public = req.is_public
    return tunnel.to_dict()


@router.post("/tunnels/{port}/rotate-code")
async def rotate_code(port: int, req: RotateCodeRequest):
    tunnel = global_tunnel_manager.get(port)
    if not tunnel:
        raise AppError("error.tunnel_not_found", status=404, port=port)
    if not tunnel.proxy:
        raise AppError("error.tunnel_not_ready", status=503, port=port)

    tunnel.proxy.rotate_code(revoke_all=req.revoke_all)
    return tunnel.to_dict()


@router.post("/tunnels/{port}/shorten")
async def shorten_tunnel_url(port: int, req: ShortenLinkRequest, request: Request):
    """Create a clean, customizable short link (spoo.me / ulvis / is.gd) for easy sharing and QR codes."""
    tunnel = global_tunnel_manager.get(port)
    if not tunnel:
        raise AppError("error.tunnel_not_found", status=404, port=port)
    if not tunnel.tunnel_url:
        raise AppError("error.tunnel_not_ready", status=503, port=port)

    lang = normalize_lang(request.headers.get("accept-language"))
    full_url = tunnel.tunnel_url + tunnel.path
    alias = (req.alias or "").strip()

    import re
    if alias and not re.match(r"^[a-zA-Z0-9_-]{2,60}$", alias):
        return {
            "status": "error",
            "error_code": "invalid_alias",
            "message": t(lang, "error.shorten_invalid_alias"),
        }

    import httpx

    # 1. Primary: spoo.me (fully supports trycloudflare.com & custom aliases)
    try:
        async with httpx.AsyncClient(timeout=7.0) as client:
            payload = {"url": full_url}
            if alias:
                payload["alias"] = alias
            resp = await client.post("https://spoo.me/", data=payload, headers={"Accept": "application/json"})
            if resp.status_code == 200:
                data = resp.json()
                short_url = data.get("short_url", "")
                if short_url.startswith("http://"):
                    short_url = "https://" + short_url[7:]
                if short_url:
                    tunnel.short_url = short_url
                    return {"status": "ok", "short_url": short_url}
            elif resp.status_code == 400:
                try:
                    data = resp.json()
                    err_msg = str(data.get("AliasError", ""))
                    if "already exists" in err_msg.lower():
                        return {
                            "status": "error",
                            "error_code": "alias_taken",
                            "message": t(lang, "error.shorten_alias_taken"),
                        }
                    elif "invalid" in err_msg.lower():
                        return {
                            "status": "error",
                            "error_code": "invalid_alias",
                            "message": t(lang, "error.shorten_invalid_alias"),
                        }
                except Exception:
                    pass
    except Exception:
        pass

    # 2. Fallback: ulvis.net (supports trycloudflare.com & custom aliases)
    try:
        async with httpx.AsyncClient(timeout=7.0) as client:
            params = {"url": full_url, "type": "json"}
            if alias:
                params["custom"] = alias
            resp = await client.get("https://ulvis.net/API/write/get", params=params)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("success") and "data" in data and "url" in data["data"]:
                    tunnel.short_url = data["data"]["url"]
                    return {"status": "ok", "short_url": tunnel.short_url}
    except Exception:
        pass

    # 3. Fallback: is.gd (works if not trycloudflare or if whitelist changed)
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            params = {"format": "json", "url": full_url}
            if alias:
                params["shorturl"] = alias
            resp = await client.get("https://is.gd/create.php", params=params)
            data = resp.json()
            if "shorturl" in data:
                tunnel.short_url = data["shorturl"]
                return {"status": "ok", "short_url": data["shorturl"]}
            elif "errormessage" in data:
                err_text = data["errormessage"]
                if "already in use" in err_text.lower():
                    return {
                        "status": "error",
                        "error_code": "alias_taken",
                        "message": t(lang, "error.shorten_alias_taken"),
                    }
    except Exception:
        pass

    return {
        "status": "error",
        "error_code": "service_unavailable",
        "message": t(lang, "error.shorten_service_unavailable"),
    }


@router.get("/tunnels/{port}/logs")
async def get_logs(port: int):
    tunnel = global_tunnel_manager.get(port)
    if not tunnel or not tunnel.proxy:
        return {"logs": [], "total_requests": 0, "blocked_count": 0, "active_visitors_count": 0}

    return {
        "logs": list(tunnel.proxy.recent_logs),
        "total_requests": tunnel.proxy.total_requests,
        "blocked_count": tunnel.proxy.blocked_count,
        "active_visitors_count": tunnel.proxy.active_visitors_count(),
    }


@router.post("/kill-all")
async def kill_all():
    count = await global_tunnel_manager.kill_all()
    return {"status": "ok", "killed_count": count}


@router.post("/shutdown")
async def shutdown_app():
    """Kill all tunnels, stop background tasks, and cleanly exit process so CMD auto-closes."""
    count = await global_tunnel_manager.kill_all()

    async def _delayed_exit():
        await asyncio.sleep(0.5)
        os._exit(0)

    asyncio.create_task(_delayed_exit())
    return {"status": "ok", "message": "shutting_down", "killed_count": count}


@router.post("/heartbeat")
async def heartbeat():
    """Receive heartbeat from active dashboard tab to keep background session alive."""
    from backend.services.lifecycle import global_idle_monitor
    global_idle_monitor.record_heartbeat()
    return {"status": "ok"}



import collections
import time

terminal_logs: collections.deque[dict[str, str]] = collections.deque(maxlen=300)
terminal_logs.append({
    "time": time.strftime("%H:%M:%S"),
    "source": "SYSTEM",
    "level": "INFO",
    "message": "PyTunnel Mission Control Station online. Ready to monitor game servers."
})


@router.get("/terminal-logs")
async def get_terminal_logs():
    return {
        "status": "ok",
        "logs": list(terminal_logs),
        "count": len(terminal_logs),
    }


@router.post("/terminal-logs")
async def broadcast_terminal_log(request: Request):
    try:
        data = await request.json()
        entry = {
            "time": str(data.get("time") or time.strftime("%H:%M:%S")),
            "source": str(data.get("source", "SERVER")).upper(),
            "level": str(data.get("level", "INFO")).upper(),
            "message": str(data.get("message", "")),
        }
        terminal_logs.append(entry)
        return {"status": "ok"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


@router.post("/terminal-logs/clear")
async def clear_terminal_logs():
    terminal_logs.clear()
    terminal_logs.append({
        "time": time.strftime("%H:%M:%S"),
        "source": "SYSTEM",
        "level": "INFO",
        "message": "Terminal log buffer cleared."
    })
    return {"status": "ok"}
