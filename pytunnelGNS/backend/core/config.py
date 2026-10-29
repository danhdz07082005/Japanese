"""Static configuration. Zero-config by design: no .env, no secrets."""
import platform
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent
BIN_DIR = BASE_DIR / "bin"
TEMPLATES_DIR = BASE_DIR / "frontend" / "templates"
STATIC_DIR = BASE_DIR / "frontend" / "static"

DASHBOARD_HOST = "127.0.0.1"
DASHBOARD_PORT = 8787
ALLOWED_DASHBOARD_HOSTS = frozenset({"127.0.0.1", "localhost"})

# Pinned cloudflared release + official SHA-256 digests published by GitHub.
CLOUDFLARED_VERSION = "2026.10.0"
CLOUDFLARED_ASSETS = {
    "amd64": ("cloudflared-windows-amd64.exe", "86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c"),
    "386": ("cloudflared-windows-386.exe", "0630a8779e9823a1a3b091698b8e71874e0f7b205559219f52fdd301466b5546"),
}
CLOUDFLARED_EXE = BIN_DIR / f"cloudflared-{CLOUDFLARED_VERSION}.exe"
TUNNEL_START_TIMEOUT = 30.0

# Visitor-facing proxy
SESSION_MAX_AGE = 86400
ONLINE_WINDOW_SECONDS = 300
MAX_LOG_ENTRIES = 200
BRUTE_FORCE = {"max_attempts": 5, "window_seconds": 600, "lock_seconds": 900}
PROXY_RATE_LIMIT = {"max_requests": 350, "window_seconds": 10, "cooldown_seconds": 15}
CONTROL_PLANE_RATE_LIMIT = {"max_requests": 120, "window_seconds": 10, "cooldown_seconds": 15}

# Ports that must never be exposed to the Internet.
BLACKLISTED_PORTS = {
    1433: "Microsoft SQL Server",
    1521: "Oracle Database",
    3306: "MySQL",
    3389: "Remote Desktop (RDP)",
    5432: "PostgreSQL",
    5985: "WinRM",
    5986: "WinRM (HTTPS)",
    6379: "Redis",
    27017: "MongoDB",
    DASHBOARD_PORT: "PyTunnel Dashboard",
}


def cloudflared_asset() -> tuple[str, str]:
    """Return (asset_name, sha256) for this machine, or raise if unsupported."""
    machine = platform.machine().lower()
    arch = "amd64" if machine in ("amd64", "x86_64", "arm64", "aarch64") else "386" if machine in ("x86", "i386", "i686") else ""
    if not arch:
        raise RuntimeError(f"Unsupported CPU architecture: {machine}")
    return CLOUDFLARED_ASSETS[arch]
