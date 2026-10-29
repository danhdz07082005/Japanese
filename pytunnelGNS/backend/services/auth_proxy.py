"""Reverse proxy shield with HMAC-only sessions, WebSocket support, decompression safety, and Cyber Gate."""
import asyncio
import collections
import html
import logging
import secrets
import time
from typing import Any
from urllib.parse import urlsplit

import httpx
from starlette.applications import Starlette
from starlette.middleware.gzip import GZipMiddleware
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from starlette.routing import Route, WebSocketRoute
from starlette.websockets import WebSocket, WebSocketDisconnect
import websockets
import uvicorn

from backend.core.config import BRUTE_FORCE, MAX_LOG_ENTRIES, ONLINE_WINDOW_SECONDS, PROXY_RATE_LIMIT, SESSION_MAX_AGE
from backend.core.i18n import DEFAULT_LANG, normalize_lang, t
from backend.core.security import (
    BruteForceLimiter,
    RequestRateLimiter,
    generate_access_code,
    sign_session,
    verify_access_code,
    verify_session,
)

logger = logging.getLogger("pytunnel.proxy")

# Headers that must not be forwarded between proxy hops
HOP_BY_HOP = frozenset({
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
    "content-encoding", "content-length",
})


def safe_redirect_target(raw: str | None) -> str:
    """Ensure redirect_to is a safe relative path. Disallow //, /\\, scheme, or empty."""
    val = (raw or "").strip()
    if not val or not val.startswith("/") or val.startswith("//") or val.startswith("/\\"):
        return "/"
    parsed = urlsplit(val)
    if parsed.scheme or parsed.netloc:
        return "/"
    return val


def render_gate_html(lang: str, redirect_to: str, error_msg: str = "", lock_seconds: int = 0) -> str:
    esc_redirect = html.escape(redirect_to, quote=True)
    esc_error = html.escape(error_msg)
    lang_code = normalize_lang(lang)
    alt_lang = "en" if lang_code == "vi" else "vi"

    error_box = ""
    if lock_seconds > 0:
        minutes = max(1, lock_seconds // 60)
        lock_text = t(lang_code, "gate.locked", minutes=minutes)
        error_box = f'<div class="error-banner locked">{html.escape(lock_text)}</div>'
    elif error_msg:
        error_box = f'<div class="error-banner">{esc_error}</div>'

    title = html.escape(t(lang_code, "gate.title"))
    desc = html.escape(t(lang_code, "gate.desc"))
    label = html.escape(t(lang_code, "gate.label"))
    placeholder = html.escape(t(lang_code, "gate.placeholder"))
    submit_btn = html.escape(t(lang_code, "gate.submit"))
    hint = html.escape(t(lang_code, "gate.hint"))
    switch_lang_btn = html.escape(t(lang_code, "gate.switch_lang"))

    return f"""<!DOCTYPE html>
<html lang="{lang_code}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} · PyTunnel Shield</title>
    <style>
        :root {{
            --bg-canvas: #03050a;
            --surface-glass: rgba(14, 21, 42, 0.75);
            --border-glass: rgba(255, 255, 255, 0.12);
            --neon-cyan: #00f5d4;
            --neon-emerald: #10b981;
            --neon-violet: #8b5cf6;
            --neon-rose: #f43f5e;
            --text-primary: #f8fafc;
            --text-muted: #94a3b8;
            --text-subtle: #64748b;
        }}
        @keyframes continuousNeonFlow {{
            0% {{ background-position: 0% 50%; }}
            50% {{ background-position: 100% 50%; }}
            100% {{ background-position: 0% 50%; }}
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            background-color: var(--bg-canvas);
            background-image:
                radial-gradient(ellipse 70% 45% at 50% -15%, rgba(139, 92, 246, 0.16), transparent 65%),
                radial-gradient(ellipse 55% 40% at 85% 25%, rgba(0, 245, 212, 0.12), transparent 60%),
                radial-gradient(ellipse 50% 45% at 15% 65%, rgba(16, 185, 129, 0.10), transparent 60%),
                radial-gradient(circle at 50% 95%, rgba(244, 63, 94, 0.08), transparent 65%);
            background-attachment: fixed;
            color: var(--text-primary);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1.5rem;
        }}
        .card {{
            background: var(--surface-glass);
            backdrop-filter: blur(24px) saturate(190%);
            -webkit-backdrop-filter: blur(24px) saturate(190%);
            border: 1px solid var(--border-glass);
            border-radius: 1.5rem;
            max-width: 26rem;
            width: 100%;
            padding: 2.25rem 2rem 2rem;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.65), 0 0 40px rgba(0, 245, 212, 0.12);
            position: relative;
            overflow: hidden;
            animation: fadeIn 0.35s cubic-bezier(0.16, 1, 0.3, 1);
        }}
        .card::before {{
            content: "";
            position: absolute;
            top: 0; left: 0; right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--neon-cyan), var(--neon-violet), var(--neon-rose), var(--neon-emerald), var(--neon-cyan));
            background-size: 300% 100%;
            animation: continuousNeonFlow 5s linear infinite;
            box-shadow: 0 0 14px rgba(0, 245, 212, 0.6);
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(12px) scale(0.98); }}
            to {{ opacity: 1; transform: translateY(0) scale(1); }}
        }}
        .header {{ text-align: center; margin-bottom: 1.75rem; }}
        .icon-wrap {{
            width: 3.75rem;
            height: 3.75rem;
            margin: 0 auto 1.25rem;
            border-radius: 1.125rem;
            background: rgba(0, 245, 212, 0.12);
            border: 1px solid rgba(0, 245, 212, 0.4);
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--neon-cyan);
            box-shadow: 0 0 25px rgba(0, 245, 212, 0.35);
        }}
        h1 {{ font-size: 1.25rem; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 0.5rem; color: #fff; }}
        p.subtitle {{ font-size: 0.8125rem; color: var(--text-muted); line-height: 1.5; }}
        .lang-switch {{
            position: absolute;
            top: 1.25rem;
            right: 1.25rem;
            background: rgba(255, 255, 255, 0.06);
            border: 1px solid var(--border-glass);
            color: var(--text-muted);
            border-radius: 9999px;
            font-size: 0.6875rem;
            font-weight: 600;
            padding: 0.3rem 0.75rem;
            cursor: pointer;
            text-decoration: none;
            transition: all 0.2s ease;
        }}
        .lang-switch:hover {{
            color: #fff;
            border-color: rgba(255, 255, 255, 0.3);
            background: rgba(255, 255, 255, 0.12);
        }}
        .error-banner {{
            padding: 0.75rem 1rem;
            border-radius: 0.875rem;
            background: rgba(244, 63, 94, 0.15);
            border: 1px solid rgba(244, 63, 94, 0.4);
            color: #fecdd3;
            font-size: 0.8125rem;
            line-height: 1.4;
            margin-bottom: 1.25rem;
            text-align: center;
            box-shadow: 0 0 20px rgba(244, 63, 94, 0.2);
        }}
        .field {{ margin-bottom: 1.25rem; }}
        label {{ display: block; font-size: 0.75rem; font-weight: 600; color: var(--text-muted); margin-bottom: 0.5rem; }}
        input[type="text"] {{
            width: 100%;
            background: rgba(18, 27, 54, 0.75);
            border: 1px solid var(--border-glass);
            border-radius: 0.875rem;
            padding: 0.875rem 1rem;
            font-size: 1.25rem;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-weight: 700;
            text-align: center;
            letter-spacing: 0.15em;
            color: var(--neon-cyan);
            outline: none;
            transition: all 0.2s ease;
        }}
        input[type="text"]:focus {{
            border-color: var(--neon-cyan);
            box-shadow: 0 0 20px rgba(0, 245, 212, 0.4);
            background: rgba(18, 27, 54, 0.95);
        }}
        button[type="submit"] {{
            width: 100%;
            background: linear-gradient(135deg, var(--neon-cyan), var(--neon-emerald));
            color: #03050a;
            border: none;
            border-radius: 0.875rem;
            padding: 0.875rem 1rem;
            font-size: 0.8125rem;
            font-weight: 700;
            letter-spacing: 0.05em;
            text-transform: uppercase;
            cursor: pointer;
            box-shadow: 0 0 25px rgba(0, 245, 212, 0.35);
            transition: all 0.2s ease;
        }}
        button[type="submit"]:hover {{ filter: brightness(1.1); transform: translateY(-1px); }}
        button[type="submit"]:active {{ transform: translateY(0); }}
        .hint {{ font-size: 0.6875rem; color: var(--text-subtle); text-align: center; margin-top: 1.25rem; line-height: 1.4; }}
    </style>
</head>
<body>
    <div class="card">
        <a class="lang-switch" href="?lang={alt_lang}&redirect_to={esc_redirect}">{switch_lang_btn}</a>
        <div class="header">
            <div class="icon-wrap">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                    <path d="m9 12 2 2 4-4"/>
                </svg>
            </div>
            <h1>{title}</h1>
            <p class="subtitle">{desc}</p>
        </div>

        {error_box}

        <form method="POST" action="/__pytunnel_gate/login">
            <input type="hidden" name="redirect_to" value="{esc_redirect}">
            <div class="field">
                <label>{label}</label>
                <input type="text" name="code" required autocomplete="off" autofocus placeholder="{placeholder}" maxlength="12">
            </div>
            <button type="submit">{submit_btn}</button>
        </form>

        <p class="hint">{hint}</p>
    </div>
</body>
</html>"""


def render_upstream_error_html(lang: str) -> str:
    lang_code = normalize_lang(lang)
    title = html.escape(t(lang_code, "upstream.title"))
    body = html.escape(t(lang_code, "upstream.body"))
    refresh_btn = html.escape(t(lang_code, "action.refresh"))

    return f"""<!DOCTYPE html>
<html lang="{lang_code}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>502 · {title}</title>
    <style>
        :root {{
            --bg-canvas: #03050a;
            --surface-glass: rgba(14, 21, 42, 0.75);
            --border-glass: rgba(255, 255, 255, 0.12);
            --neon-rose: #f43f5e;
            --neon-violet: #8b5cf6;
            --neon-cyan: #00f5d4;
            --text-primary: #f8fafc;
            --text-muted: #94a3b8;
        }}
        @keyframes continuousNeonFlow {{
            0% {{ background-position: 0% 50%; }}
            50% {{ background-position: 100% 50%; }}
            100% {{ background-position: 0% 50%; }}
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            background-color: var(--bg-canvas);
            background-image:
                radial-gradient(ellipse 70% 45% at 50% -15%, rgba(244, 63, 94, 0.18), transparent 65%),
                radial-gradient(ellipse 55% 40% at 85% 25%, rgba(139, 92, 246, 0.14), transparent 60%),
                radial-gradient(ellipse 50% 45% at 15% 65%, rgba(0, 245, 212, 0.10), transparent 60%);
            background-attachment: fixed;
            color: var(--text-primary);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1.5rem;
        }}
        .card {{
            background: var(--surface-glass);
            backdrop-filter: blur(24px) saturate(190%);
            -webkit-backdrop-filter: blur(24px) saturate(190%);
            border: 1px solid var(--border-glass);
            border-radius: 1.5rem;
            max-width: 26rem;
            width: 100%;
            padding: 2.25rem 2rem 2rem;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.65), 0 0 40px rgba(244, 63, 94, 0.2);
            position: relative;
            overflow: hidden;
            text-align: center;
            animation: fadeIn 0.35s cubic-bezier(0.16, 1, 0.3, 1);
        }}
        .card::before {{
            content: "";
            position: absolute;
            top: 0; left: 0; right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--neon-rose), var(--neon-violet), var(--neon-cyan), var(--neon-rose));
            background-size: 300% 100%;
            animation: continuousNeonFlow 5s linear infinite;
            box-shadow: 0 0 14px rgba(244, 63, 94, 0.6);
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(12px) scale(0.98); }}
            to {{ opacity: 1; transform: translateY(0) scale(1); }}
        }}
        .icon-wrap {{
            width: 3.75rem;
            height: 3.75rem;
            margin: 0 auto 1.25rem;
            border-radius: 1.125rem;
            background: rgba(244, 63, 94, 0.12);
            border: 1px solid rgba(244, 63, 94, 0.4);
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--neon-rose);
            box-shadow: 0 0 25px rgba(244, 63, 94, 0.35);
        }}
        .badge {{
            display: inline-block;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 0.6875rem;
            font-weight: 700;
            color: var(--neon-rose);
            background: rgba(244, 63, 94, 0.12);
            border: 1px solid rgba(244, 63, 94, 0.3);
            border-radius: 9999px;
            padding: 0.2rem 0.65rem;
            margin-bottom: 0.75rem;
            letter-spacing: 0.05em;
        }}
        h2 {{ font-size: 1.25rem; font-weight: 700; margin-bottom: 0.5rem; color: #fff; }}
        p {{ font-size: 0.8125rem; color: var(--text-muted); line-height: 1.5; margin-bottom: 1.5rem; }}
        .btn {{
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 0.5rem;
            width: 100%;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid var(--border-glass);
            color: #fff;
            border-radius: 0.875rem;
            padding: 0.75rem 1rem;
            font-size: 0.8125rem;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            transition: all 0.2s ease;
        }}
        .btn:hover {{
            background: rgba(255, 255, 255, 0.15);
            border-color: rgba(255, 255, 255, 0.25);
            transform: translateY(-1px);
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon-wrap">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="10"/>
                <line x1="12" y1="8" x2="12" y2="12"/>
                <line x1="12" y1="16" x2="12.01" y2="16"/>
            </svg>
        </div>
        <div class="badge">502 BAD GATEWAY</div>
        <h2>{title}</h2>
        <p>{body}</p>
        <button class="btn" onclick="location.reload()">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
                <path d="M3 3v5h5"/>
                <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/>
                <path d="M16 21h5v-5"/>
            </svg>
            <span>{refresh_btn}</span>
        </button>
    </div>
</body>
</html>"""


def render_rate_limit_html(lang: str, retry_after: int) -> str:
    lang_code = normalize_lang(lang)
    title = html.escape(t(lang_code, "rate_limit.title"))
    body = html.escape(t(lang_code, "rate_limit.body", seconds=retry_after))
    retry_btn = html.escape(t(lang_code, "rate_limit.retry"))

    return f"""<!DOCTYPE html>
<html lang="{lang_code}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>429 · {title}</title>
    <style>
        :root {{
            --bg-canvas: #03050a;
            --surface-glass: rgba(14, 21, 42, 0.75);
            --border-glass: rgba(255, 255, 255, 0.12);
            --neon-amber: #f59e0b;
            --neon-rose: #f43f5e;
            --neon-cyan: #00f5d4;
            --text-primary: #f8fafc;
            --text-muted: #94a3b8;
        }}
        @keyframes continuousNeonFlow {{
            0% {{ background-position: 0% 50%; }}
            50% {{ background-position: 100% 50%; }}
            100% {{ background-position: 0% 50%; }}
        }}
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            background-color: var(--bg-canvas);
            background-image:
                radial-gradient(ellipse 70% 45% at 50% -15%, rgba(245, 158, 11, 0.16), transparent 65%),
                radial-gradient(ellipse 55% 40% at 85% 25%, rgba(244, 63, 94, 0.14), transparent 60%),
                radial-gradient(ellipse 50% 45% at 15% 65%, rgba(0, 245, 212, 0.10), transparent 60%);
            background-attachment: fixed;
            color: var(--text-primary);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 1.5rem;
        }}
        .card {{
            background: var(--surface-glass);
            backdrop-filter: blur(24px) saturate(190%);
            -webkit-backdrop-filter: blur(24px) saturate(190%);
            border: 1px solid var(--border-glass);
            border-radius: 1.5rem;
            max-width: 26rem;
            width: 100%;
            padding: 2.25rem 2rem 2rem;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.65), 0 0 40px rgba(245, 158, 11, 0.2);
            position: relative;
            overflow: hidden;
            text-align: center;
            animation: fadeIn 0.35s cubic-bezier(0.16, 1, 0.3, 1);
        }}
        .card::before {{
            content: "";
            position: absolute;
            top: 0; left: 0; right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--neon-amber), var(--neon-rose), var(--neon-cyan), var(--neon-amber));
            background-size: 300% 100%;
            animation: continuousNeonFlow 5s linear infinite;
            box-shadow: 0 0 14px rgba(245, 158, 11, 0.6);
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(12px) scale(0.98); }}
            to {{ opacity: 1; transform: translateY(0) scale(1); }}
        }}
        .icon-wrap {{
            width: 3.75rem;
            height: 3.75rem;
            margin: 0 auto 1.25rem;
            border-radius: 1.125rem;
            background: rgba(245, 158, 11, 0.12);
            border: 1px solid rgba(245, 158, 11, 0.4);
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--neon-amber);
            box-shadow: 0 0 25px rgba(245, 158, 11, 0.35);
        }}
        .badge {{
            display: inline-block;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 0.6875rem;
            font-weight: 700;
            color: var(--neon-amber);
            background: rgba(245, 158, 11, 0.12);
            border: 1px solid rgba(245, 158, 11, 0.3);
            border-radius: 9999px;
            padding: 0.2rem 0.65rem;
            margin-bottom: 0.75rem;
            letter-spacing: 0.05em;
        }}
        h2 {{ font-size: 1.25rem; font-weight: 700; margin-bottom: 0.5rem; color: #fff; }}
        p {{ font-size: 0.8125rem; color: var(--text-muted); line-height: 1.5; margin-bottom: 1.5rem; }}
        .btn {{
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 0.5rem;
            width: 100%;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid var(--border-glass);
            color: #fff;
            border-radius: 0.875rem;
            padding: 0.75rem 1rem;
            font-size: 0.8125rem;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            transition: all 0.2s ease;
        }}
        .btn:hover {{
            background: rgba(255, 255, 255, 0.15);
            border-color: rgba(255, 255, 255, 0.25);
            transform: translateY(-1px);
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon-wrap">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 2v4"/><path d="m4.93 4.93 2.83 2.83"/><path d="M2 12h4"/><path d="m4.93 19.07 2.83-2.83"/><path d="M12 22v-4"/><path d="m19.07 19.07-2.83-2.83"/><path d="M22 12h-4"/><path d="m19.07 4.93-2.83 2.83"/>
            </svg>
        </div>
        <div class="badge">429 TOO MANY REQUESTS · ANTI-SPAM</div>
        <h2>{title}</h2>
        <p>{body}</p>
        <button class="btn" onclick="location.reload()">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>
                <path d="M3 3v5h5"/>
                <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/>
                <path d="M16 21h5v-5"/>
            </svg>
            <span>{retry_btn}</span>
        </button>
    </div>
</body>
</html>"""


class AuthProxyInstance:
    """Reverse proxy running on 127.0.0.1:<proxy_port> that shields one target application."""

    def __init__(self, target_port: int, proxy_port: int, access_code: str, is_public: bool = False) -> None:
        self.target_port = target_port
        self.proxy_port = proxy_port
        self.access_code = access_code
        self.is_public = is_public
        self.session_secret: bytes = secrets.token_bytes(32)

        self.limiter = BruteForceLimiter(**BRUTE_FORCE)
        self.rate_limiter = RequestRateLimiter(**PROXY_RATE_LIMIT)
        self.recent_logs: collections.deque[dict[str, Any]] = collections.deque(maxlen=MAX_LOG_ENTRIES)
        self.active_visitor_timestamps: dict[str, float] = {}

        self.total_requests: int = 0
        self.blocked_count: int = 0

        limits = httpx.Limits(max_connections=400, max_keepalive_connections=150, keepalive_expiry=30.0)
        self.client = httpx.AsyncClient(limits=limits, timeout=httpx.Timeout(120.0, connect=10.0, read=120.0), follow_redirects=False)
        self.server: uvicorn.Server | None = None
        self._app = self._build_app()

    def set_public(self, public: bool, keep_sessions: bool = True) -> None:
        """Hot-toggle between Public (bypass PIN) and Protected modes without restarting tunnel."""
        if not self.is_public and public:
            self.is_public = True
            logger.info("Port %d: Switched to PUBLIC mode", self.target_port)
        elif self.is_public and not public:
            self.is_public = False
            if keep_sessions:
                # Keep current session_secret: visitors who already received a session cookie keep access
                logger.info("Port %d: Switched to PROTECTED mode (retaining existing visitor sessions)", self.target_port)
            else:
                # Revoke all: new session_secret invalidates all existing HMAC cookies instantly
                self.session_secret = secrets.token_bytes(32)
                logger.info("Port %d: Switched to PROTECTED mode (all sessions revoked)", self.target_port)

    def rotate_code(self, revoke_all: bool = False) -> str:
        """Issue a new access code; optionally revoke all existing visitor sessions."""
        self.access_code = generate_access_code()
        if revoke_all:
            self.session_secret = secrets.token_bytes(32)
            logger.info("Port %d: Access code rotated & all sessions revoked", self.target_port)
        else:
            logger.info("Port %d: Access code rotated (existing sessions kept)", self.target_port)
        return self.access_code

    def active_visitors_count(self) -> int:
        now = time.time()
        cutoff = now - ONLINE_WINDOW_SECONDS
        self.active_visitor_timestamps = {k: ts for k, ts in self.active_visitor_timestamps.items() if ts > cutoff}
        return len(self.active_visitor_timestamps)

    def _log_request(self, ip: str, country: str, method: str, path: str, status: int, latency_ms: float, auth_status: str) -> None:
        self.total_requests += 1
        self.active_visitor_timestamps[ip] = time.time()
        entry = {
            "time": time.strftime("%H:%M:%S"),
            "ip": ip,
            "country": country,
            "method": method,
            "path": path[:80] + ("…" if len(path) > 80 else ""),
            "status": status,
            "latency_ms": round(latency_ms, 1),
            "auth_status": auth_status,
        }
        self.recent_logs.appendleft(entry)

    def _build_app(self) -> Starlette:
        def enforce_rate_limit(request: Request) -> Response | None:
            client_ip = request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "127.0.0.1")
            allowed, retry_after = self.rate_limiter.check(client_ip)
            if not allowed:
                self.blocked_count += 1
                country = request.headers.get("cf-ipcountry", "VN")
                path = request.url.path
                if request.url.query:
                    path += f"?{request.url.query}"
                self._log_request(client_ip, country, request.method, path, 429, 0.2, "auth.rate_limited")

                accept = request.headers.get("accept", "")
                lang = request.headers.get("accept-language", DEFAULT_LANG)
                headers = {"Retry-After": str(retry_after)}

                sec_dest = request.headers.get("sec-fetch-dest", "")
                path_lower = request.url.path.lower()
                is_static_asset = sec_dest in ("script", "style", "image", "font", "empty") or any(
                    path_lower.endswith(ext)
                    for ext in (".js", ".mjs", ".css", ".wasm", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".map", ".json")
                )

                if is_static_asset:
                    if "application/json" in accept:
                        lang_code = normalize_lang(lang)
                        return JSONResponse(
                            {
                                "error_code": "error.rate_limited",
                                "message": t(lang_code, "rate_limit.body", seconds=retry_after),
                                "retry_after": retry_after,
                            },
                            status_code=429,
                            headers=headers,
                        )
                    return Response(
                        content=f"Too Many Requests. Retry after {retry_after}s.",
                        status_code=429,
                        headers=headers,
                        media_type="text/plain",
                    )

                if "text/html" in accept or "*/*" in accept:
                    return HTMLResponse(
                        render_rate_limit_html(lang=lang, retry_after=retry_after),
                        status_code=429,
                        headers=headers,
                    )
                elif "application/json" in accept:
                    lang_code = normalize_lang(lang)
                    return JSONResponse(
                        {
                            "error_code": "error.rate_limited",
                            "message": t(lang_code, "rate_limit.body", seconds=retry_after),
                            "retry_after": retry_after,
                        },
                        status_code=429,
                        headers=headers,
                    )
                return Response(
                    content=f"Too Many Requests. Retry after {retry_after}s.",
                    status_code=429,
                    headers=headers,
                    media_type="text/plain",
                )
            return None

        async def gate_view(request: Request) -> Response:
            rate_resp = enforce_rate_limit(request)
            if rate_resp:
                return rate_resp
            client_ip = request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "127.0.0.1")
            lock_rem = self.limiter.locked_for(client_ip)
            lang = request.query_params.get("lang") or request.headers.get("accept-language", DEFAULT_LANG)
            redirect_to = safe_redirect_target(request.query_params.get("redirect_to", "/"))
            content = render_gate_html(lang=lang, redirect_to=redirect_to, lock_seconds=lock_rem)
            return HTMLResponse(content, status_code=200 if lock_rem == 0 else 429)

        async def login_handler(request: Request) -> Response:
            rate_resp = enforce_rate_limit(request)
            if rate_resp:
                return rate_resp
            client_ip = request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "127.0.0.1")
            lang = request.headers.get("accept-language", DEFAULT_LANG)
            lang_code = normalize_lang(lang)

            lock_rem = self.limiter.locked_for(client_ip)
            if lock_rem > 0:
                self.blocked_count += 1
                return HTMLResponse(render_gate_html(lang=lang, redirect_to="/", lock_seconds=lock_rem), status_code=429)

            form = await request.form()
            code = str(form.get("code", "")).strip()
            redirect_to = safe_redirect_target(str(form.get("redirect_to", "/")))

            if verify_access_code(code, self.access_code):
                self.limiter.record_success(client_ip)
                cookie_val = sign_session(self.session_secret)
                resp = RedirectResponse(url=redirect_to, status_code=302)
                resp.set_cookie(
                    key="pytunnel_session",
                    value=cookie_val,
                    max_age=SESSION_MAX_AGE,
                    httponly=True,
                    secure=True,
                    samesite="lax",
                    path="/",
                )
                self._log_request(client_ip, request.headers.get("cf-ipcountry", "VN"), "POST", "/login", 302, 0.5, "auth.login_ok")
                return resp
            else:
                self.blocked_count += 1
                rem_attempts = self.limiter.record_failure(client_ip)
                if rem_attempts <= 0:
                    lock_sec = BRUTE_FORCE["lock_seconds"]
                    err_msg = t(lang_code, "gate.locked", minutes=lock_sec // 60)
                    self._log_request(client_ip, request.headers.get("cf-ipcountry", "VN"), "POST", "/login", 429, 0.5, "auth.locked")
                    return HTMLResponse(render_gate_html(lang=lang, redirect_to=redirect_to, error_msg=err_msg, lock_seconds=lock_sec), status_code=429)
                else:
                    err_msg = t(lang_code, "gate.wrong", remaining=rem_attempts)
                    self._log_request(client_ip, request.headers.get("cf-ipcountry", "VN"), "POST", "/login", 401, 0.5, "auth.login_fail")
                    return HTMLResponse(render_gate_html(lang=lang, redirect_to=redirect_to, error_msg=err_msg), status_code=401)

        async def http_proxy_handler(request: Request) -> Response:
            rate_resp = enforce_rate_limit(request)
            if rate_resp:
                return rate_resp
            start_ts = time.time()
            client_ip = request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "127.0.0.1")
            country = request.headers.get("cf-ipcountry", "VN")
            path = request.url.path
            if request.url.query:
                path += f"?{request.url.query}"

            # Check Authentication
            authenticated = False
            auth_status = "auth.public"
            cookie_to_set = None

            if self.is_public:
                authenticated = True
                # In public mode, proactively issue session cookie so transitions to Protected with keep_sessions=True work seamlessly
                cur_cookie = request.cookies.get("pytunnel_session")
                if not verify_session(cur_cookie, self.session_secret, SESSION_MAX_AGE):
                    cookie_to_set = sign_session(self.session_secret)
            else:
                cur_cookie = request.cookies.get("pytunnel_session")
                if verify_session(cur_cookie, self.session_secret, SESSION_MAX_AGE):
                    authenticated = True
                    auth_status = "auth.session"
                else:
                    self.blocked_count += 1
                    latency = (time.time() - start_ts) * 1000
                    self._log_request(client_ip, country, request.method, path, 401, latency, "auth.gate")
                    accept = request.headers.get("accept", "")
                    if "text/html" in accept or "*/*" in accept:
                        lang = request.headers.get("accept-language", DEFAULT_LANG)
                        html_content = render_gate_html(lang=lang, redirect_to=safe_redirect_target(path))
                        return HTMLResponse(html_content, status_code=401)
                    return Response(content="Unauthorized (PyTunnel Shield)", status_code=401, media_type="text/plain")

            # Forward request upstream to localhost:target_port
            upstream_url = f"http://127.0.0.1:{self.target_port}{request.url.path}"
            if request.url.query:
                upstream_url += f"?{request.url.query}"

            # Clean headers: remove hop-by-hop and internal pytunnel session cookie
            fwd_headers = {
                k: v for k, v in request.headers.items()
                if k.lower() not in HOP_BY_HOP and k.lower() != "host"
            }
            fwd_headers["host"] = f"127.0.0.1:{self.target_port}"
            fwd_headers["x-forwarded-proto"] = "https"
            fwd_headers["x-forwarded-for"] = client_ip

            # Strip pytunnel_session from Cookie header before forwarding to target app
            client_cookies = [
                c.strip() for c in request.headers.get("cookie", "").split(";")
                if c.strip() and not c.strip().startswith("pytunnel_session=")
            ]
            if client_cookies:
                fwd_headers["cookie"] = "; ".join(client_cookies)
            else:
                fwd_headers.pop("cookie", None)

            body = await request.body()

            try:
                upstream_resp = await self.client.request(
                    method=request.method,
                    url=upstream_url,
                    headers=fwd_headers,
                    content=body,
                )

                # Strip hop-by-hop & compression headers so decompressed content length doesn't mismatch
                resp_headers = {
                    k: v for k, v in upstream_resp.headers.items()
                    if k.lower() not in HOP_BY_HOP
                }

                # Rewrite Location header if upstream redirected to localhost:{target_port}
                if "location" in resp_headers:
                    loc = resp_headers["location"]
                    parsed_loc = urlsplit(loc)
                    if parsed_loc.hostname in ("127.0.0.1", "localhost") and parsed_loc.port == self.target_port:
                        new_loc = parsed_loc.path or "/"
                        if parsed_loc.query:
                            new_loc += f"?{parsed_loc.query}"
                        resp_headers["location"] = new_loc

                latency = (time.time() - start_ts) * 1000
                self._log_request(client_ip, country, request.method, path, upstream_resp.status_code, latency, auth_status)

                response = Response(
                    content=upstream_resp.content,
                    status_code=upstream_resp.status_code,
                    headers=resp_headers,
                )

                # Multi-headers: preserve all Set-Cookie headers from upstream
                for cookie in upstream_resp.headers.get_list("set-cookie"):
                    response.headers.append("set-cookie", cookie)

                # Proactively issue session cookie in public mode
                if cookie_to_set:
                    response.set_cookie(
                        key="pytunnel_session",
                        value=cookie_to_set,
                        max_age=SESSION_MAX_AGE,
                        httponly=True,
                        secure=True,
                        samesite="lax",
                        path="/",
                    )

                return response

            except Exception as e:
                latency = (time.time() - start_ts) * 1000
                self._log_request(client_ip, country, request.method, path, 502, latency, "auth.upstream_error")
                lang = request.headers.get("accept-language", DEFAULT_LANG)
                return HTMLResponse(render_upstream_error_html(lang), status_code=502)

        async def websocket_proxy_handler(websocket: WebSocket) -> None:
            client_ip = websocket.headers.get("cf-connecting-ip") or (websocket.client.host if websocket.client else "127.0.0.1")
            allowed, _ = self.rate_limiter.check(client_ip)
            if not allowed:
                await websocket.close(code=1008)
                return

            # Check auth for WebSocket
            authenticated = False
            if self.is_public:
                authenticated = True
            else:
                cookie_val = websocket.cookies.get("pytunnel_session")
                if verify_session(cookie_val, self.session_secret, SESSION_MAX_AGE):
                    authenticated = True

            if not authenticated:
                await websocket.close(code=1008)
                return

            await websocket.accept()
            path = websocket.url.path
            if websocket.url.query:
                path += f"?{websocket.url.query}"
            ws_target = f"ws://127.0.0.1:{self.target_port}{path}"

            try:
                async with websockets.connect(ws_target) as upstream_ws:
                    async def client_to_upstream():
                        try:
                            while True:
                                data = await websocket.receive()
                                if "text" in data and data["text"] is not None:
                                    await upstream_ws.send(data["text"])
                                elif "bytes" in data and data["bytes"] is not None:
                                    await upstream_ws.send(data["bytes"])
                        except (WebSocketDisconnect, asyncio.CancelledError):
                            pass

                    async def upstream_to_client():
                        try:
                            async for msg in upstream_ws:
                                if isinstance(msg, str):
                                    await websocket.send_text(msg)
                                else:
                                    await websocket.send_bytes(msg)
                        except (WebSocketDisconnect, asyncio.CancelledError):
                            pass

                    t1 = asyncio.create_task(client_to_upstream())
                    t2 = asyncio.create_task(upstream_to_client())
                    done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
                    for p in pending:
                        p.cancel()
            except Exception as e:
                logger.warning("WebSocket upstream connect error on port %d: %s", self.target_port, e)
                try:
                    await websocket.close(code=1011)
                except Exception:
                    pass

        routes = [
            Route("/__pytunnel_gate", gate_view, methods=["GET"]),
            Route("/__pytunnel_gate/login", login_handler, methods=["POST"]),
            WebSocketRoute("/{path:path}", websocket_proxy_handler),
            Route("/{path:path}", http_proxy_handler, methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]),
        ]
        app = Starlette(routes=routes)
        app.add_middleware(GZipMiddleware, minimum_size=1024)
        return app

    async def serve(self, bound_sock: Any) -> None:
        cfg = uvicorn.Config(
            app=self._app,
            log_level="critical",
            access_log=False,
            timeout_keep_alive=15,
        )
        self.server = uvicorn.Server(cfg)
        logger.info("AuthProxy starting on port %d -> %d", self.proxy_port, self.target_port)
        await self.server.serve(sockets=[bound_sock])

    async def stop(self) -> None:
        if self.server:
            self.server.should_exit = True
        await self.client.aclose()
