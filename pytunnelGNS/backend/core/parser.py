"""Turn whatever the user pastes (port, host:port, full URL) into a validated local target."""
import re
from dataclasses import dataclass
from urllib.parse import urlsplit

from backend.core.config import BLACKLISTED_PORTS, DASHBOARD_PORT
from backend.core.errors import AppError

LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1", "0.0.0.0"})
_HAS_SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*://", re.IGNORECASE)


@dataclass(frozen=True)
class Target:
    port: int
    path: str = ""  # path + query (+ fragment) appended to the public link, e.g. "?t=123"


def validate_port(port: int) -> int:
    if not 1024 <= port <= 65535:
        raise AppError("error.port_out_of_range")
    if port == DASHBOARD_PORT:
        raise AppError("error.port_internal", port=port, desc="Dashboard quản trị")
    if port in BLACKLISTED_PORTS:
        raise AppError("error.port_blacklisted", port=port, service=BLACKLISTED_PORTS[port])
    return port


def parse_target(raw: str) -> Target:
    value = (raw or "").strip()
    if not value:
        raise AppError("error.input_required")
    if value.isdigit():
        return Target(validate_port(int(value)))

    parts = urlsplit(value if _HAS_SCHEME.match(value) else f"http://{value}")
    host = (parts.hostname or "").lower()
    if host not in LOCAL_HOSTS:
        raise AppError("error.host_not_local", host=host or value)
    try:
        port = parts.port
    except ValueError:  # e.g. ":99999" or ":abc"
        raise AppError("error.port_out_of_range")
    if port is None:
        raise AppError("error.port_not_found", value=value)

    path = parts.path if parts.path not in ("", "/") else ""
    if parts.query:
        path += f"?{parts.query}"
    if parts.fragment:
        path += f"#{parts.fragment}"
    return Target(validate_port(port), path)
