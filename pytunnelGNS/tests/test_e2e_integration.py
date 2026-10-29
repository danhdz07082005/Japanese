import asyncio
from unittest.mock import MagicMock, patch
import pytest
from starlette.testclient import TestClient

from backend.core.config import DASHBOARD_PORT
from backend.core.parser import parse_target
from backend.main import app
from backend.services.tunnel_manager import Tunnel, TunnelState, global_tunnel_manager


@pytest.fixture(autouse=True)
def allow_testserver_host():
    app.state.allowed_hosts = frozenset({"127.0.0.1", "localhost", "testserver"})
    yield
    app.state.allowed_hosts = None


def test_ui_and_assets_end_to_end():
    client = TestClient(app, base_url="http://127.0.0.1:8787")
    
    # 1. Main index page
    res_index = client.get("/")
    assert res_index.status_code == 200
    assert "Content-Security-Policy" in res_index.text
    assert "PyTunnel Studio" in res_index.text
    assert "data-i18n" in res_index.text

    # 2. Static CSS
    res_css = client.get("/static/css/style.css")
    assert res_css.status_code == 200
    assert "--neon-emerald" in res_css.text

    # 3. Static JS
    res_js = client.get("/static/js/app.js")
    assert res_js.status_code == 200
    assert "escapeHtml" in res_js.text

    # 4. Confirm Cyber Tunnel and 3D Canvas are eradicated, Silky Liquid Screens present
    res_tunnel = client.get("/static/js/cyber_tunnel.js")
    assert res_tunnel.status_code == 404
    assert "<canvas" not in res_index.text
    assert "cyber-hello-screen" not in res_index.text
    assert "cyber-goodbye-screen" not in res_index.text
    assert "liquid-hello-screen" in res_index.text
    assert "liquid-goodbye-screen" in res_index.text

    # 5. Central i18n endpoint with Hello & Goodbye keys
    res_i18n = client.get("/api/i18n")
    assert res_i18n.status_code == 200
    data = res_i18n.json()
    assert "vi" in data and "en" in data
    assert "hello.title" in data["vi"]
    assert "goodbye.title" in data["en"]


@pytest.mark.anyio
async def test_full_tunnel_aggregate_lifecycle():
    # Test lifecycle of Tunnel aggregate root directly
    target = parse_target("http://127.0.0.1:58931?t=1791247438")
    assert target.port == 58931
    assert target.path == "?t=1791247438"

    tunnel = Tunnel(target=target, is_public=True)
    assert tunnel.state == TunnelState.STARTING
    assert tunnel.port == 58931
    assert tunnel.path == "?t=1791247438"

    with patch("backend.services.engine.engine.ensure") as mock_ensure, \
         patch("backend.services.cloudflared.CloudflaredProcess.start") as mock_start, \
         patch("backend.services.cloudflared.CloudflaredProcess.wait_for_url") as mock_url:
        
        mock_ensure.return_value = "cloudflared.exe"
        mock_url.return_value = "https://cyber-tunnel-xyz.trycloudflare.com"

        await tunnel.start()

        assert tunnel.state == TunnelState.ONLINE
        assert tunnel.tunnel_url == "https://cyber-tunnel-xyz.trycloudflare.com"
        assert tunnel.proxy_port > 0
        assert tunnel.proxy is not None

        info = tunnel.to_dict()
        assert info["full_tunnel_url"] == "https://cyber-tunnel-xyz.trycloudflare.com?t=1791247438"
        assert info["is_public"] is True

        # Test hot toggle to protected with keep_sessions=True
        tunnel.proxy.set_public(False, keep_sessions=True)
        assert tunnel.to_dict()["is_public"] is False

        # Test access code rotation
        old_code = tunnel.proxy.access_code
        new_code = tunnel.proxy.rotate_code(revoke_all=False)
        assert old_code != new_code
        assert len(new_code) == 9

        # Test clean stop
        await tunnel.stop()
        assert tunnel.state == TunnelState.STOPPED
        assert tunnel.proxy is None
        assert tunnel.process is None
