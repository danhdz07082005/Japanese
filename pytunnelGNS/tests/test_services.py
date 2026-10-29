import platform
import re
import socket
from backend.core.config import cloudflared_asset
from backend.services.cloudflared import URL_PATTERN
from backend.services.tunnel_manager import find_free_socket
from backend.services.win_job import job_object


def test_cloudflared_url_pattern_excludes_api():
    # Regular tunnel URL -> match
    line_ok = "2026-10-07T00:00:00Z INF | https://rapid-silver-cat.trycloudflare.com |"
    m_ok = URL_PATTERN.search(line_ok)
    assert m_ok is not None
    assert m_ok.group(0) == "https://rapid-silver-cat.trycloudflare.com"

    # API URL in cloudflared error lines (H1) -> must NOT match
    line_err = "2026-10-07T00:00:00Z ERR Request failed uri=https://api.trycloudflare.com/tunnel"
    m_err = URL_PATTERN.search(line_err)
    assert m_err is None


def test_find_free_socket():
    # Socket binding probe ensures port collision immunity (C3)
    port, sock = find_free_socket(start_port=20000, attempts=50)
    assert 20000 <= port <= 20050
    assert sock is not None
    # Confirm it's actually bound
    assert sock.getsockname()[1] == port
    sock.close()


def test_cloudflared_asset_configuration():
    asset_name, sha256_hash = cloudflared_asset()
    assert "cloudflared-windows" in asset_name
    assert len(sha256_hash) == 64  # Valid SHA-256 length


def test_win_job_object_status():
    if platform.system() == "Windows":
        assert job_object.active is True
