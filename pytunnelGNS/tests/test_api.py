from unittest.mock import AsyncMock, patch
import pytest
from starlette.testclient import TestClient

from backend.main import SESSION_CSRF_TOKEN, app
from backend.core.parser import Target
from backend.services.tunnel_manager import Tunnel, TunnelState, global_tunnel_manager


@pytest.fixture(autouse=True)
def cleanup():
    from backend.main import control_plane_limiter
    control_plane_limiter.reset("testclient")
    app.state.allowed_hosts = {"127.0.0.1", "localhost", "testserver"}
    global_tunnel_manager.tunnels.clear()
    yield
    global_tunnel_manager.tunnels.clear()
    control_plane_limiter.reset("testclient")


def test_dns_rebinding_defense():
    client = TestClient(app)

    # Allowed hosts
    resp_ok = client.get("/api/status", headers={"host": "127.0.0.1:8787"})
    assert resp_ok.status_code == 200

    # Evil external host (DNS Rebinding) -> 403 Forbidden
    resp_evil = client.get("/api/status", headers={"host": "evil-attacker.com"})
    assert resp_evil.status_code == 403
    assert resp_evil.json()["error_code"] == "error.host_forbidden"


def test_csrf_token_defense():
    client = TestClient(app)

    # POST without CSRF token (H5) -> 403 Forbidden
    resp_no_csrf = client.post("/api/parse", json={"raw_input": "5000"})
    assert resp_no_csrf.status_code == 403
    assert resp_no_csrf.json()["error_code"] == "error.csrf_failed"

    # POST with valid CSRF token -> 200 OK
    resp_with_csrf = client.post(
        "/api/parse",
        json={"raw_input": "5000"},
        headers={"x-pytunnel-token": SESSION_CSRF_TOKEN}
    )
    assert resp_with_csrf.status_code == 200
    assert resp_with_csrf.json()["valid"] is True
    assert resp_with_csrf.json()["port"] == 5000


def test_api_parse_endpoint():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN}

    # Valid input
    r1 = client.post("/api/parse", json={"raw_input": "http://127.0.0.1:58931?t=123"}, headers=headers)
    assert r1.status_code == 200
    d1 = r1.json()
    assert d1["valid"] is True
    assert d1["port"] == 58931
    assert d1["path"] == "?t=123"

    # Invalid input (forbidden port 3389)
    r2 = client.post("/api/parse", json={"raw_input": "3389"}, headers=headers)
    assert r2.status_code == 200
    d2 = r2.json()
    assert d2["valid"] is False
    assert d2["error_code"] == "error.port_blacklisted"


def test_tunnel_lifecycle_api():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN}

    # Seed a simulated tunnel
    target = Target(port=58931, path="?t=token")
    tunnel = Tunnel(target=target, is_public=False)
    tunnel.state = TunnelState.ONLINE
    tunnel.tunnel_url = "https://rapid-test-tunnel.trycloudflare.com"

    from backend.services.auth_proxy import AuthProxyInstance
    tunnel.proxy = AuthProxyInstance(target_port=58931, proxy_port=18788, access_code="ABCD-EFGH", is_public=False)
    global_tunnel_manager.tunnels[58931] = tunnel

    # 1. List tunnels
    resp_list = client.get("/api/tunnels")
    assert resp_list.status_code == 200
    assert len(resp_list.json()) == 1
    assert resp_list.json()[0]["port"] == 58931

    # 2. Hot-toggle to Public
    resp_toggle = client.post(
        "/api/tunnels/58931/toggle-mode",
        json={"is_public": True, "keep_sessions": True},
        headers=headers
    )
    assert resp_toggle.status_code == 200
    assert resp_toggle.json()["is_public"] is True

    # 3. Rotate Access Code
    resp_rotate = client.post(
        "/api/tunnels/58931/rotate-code",
        json={"revoke_all": False},
        headers=headers
    )
    assert resp_rotate.status_code == 200
    new_code = resp_rotate.json()["access_code"]
    assert new_code != "ABCD-EFGH"

    # 4. Stop Tunnel
    resp_stop = client.post("/api/tunnels/58931/stop", headers=headers)
    assert resp_stop.status_code == 200
    assert 58931 not in global_tunnel_manager.tunnels


def test_master_kill_all_api():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN}

    # Seed 2 tunnels
    global_tunnel_manager.tunnels[5000] = Tunnel(target=Target(5000), is_public=False)
    global_tunnel_manager.tunnels[3000] = Tunnel(target=Target(3000), is_public=False)
    assert len(global_tunnel_manager.tunnels) == 2

    resp = client.post("/api/kill-all", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["killed_count"] == 2
    assert len(global_tunnel_manager.tunnels) == 0


def test_shutdown_endpoint():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN}

    global_tunnel_manager.tunnels[5000] = Tunnel(target=Target(5000), is_public=False)

    with patch("os._exit") as mock_exit:
        resp = client.post("/api/shutdown", headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["message"] == "shutting_down"
        assert data["killed_count"] == 1
        assert len(global_tunnel_manager.tunnels) == 0


def test_shorten_tunnel_url_api():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN}

    tunnel = Tunnel(target=Target(58931, "?t=token123"), is_public=False)
    tunnel.tunnel_url = "https://mock-tunnel.trycloudflare.com"
    global_tunnel_manager.tunnels[58931] = tunnel

    class MockResp:
        status_code = 200
        text = '{"short_url": "https://spoo.me/auto_translator"}'
        def json(self):
            return {"short_url": "https://spoo.me/auto_translator"}

    with patch("httpx.AsyncClient.post", return_value=MockResp()):
        resp = client.post(
            "/api/tunnels/58931/shorten",
            json={"alias": "auto_translator"},
            headers=headers
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["short_url"] == "https://spoo.me/auto_translator"
        assert tunnel.short_url == "https://spoo.me/auto_translator"


def test_shorten_tunnel_url_alias_taken():
    client = TestClient(app)
    headers = {"x-pytunnel-token": SESSION_CSRF_TOKEN, "Accept-Language": "vi"}

    tunnel = Tunnel(target=Target(58932, "?t=token123"), is_public=False)
    tunnel.tunnel_url = "https://mock-tunnel.trycloudflare.com"
    global_tunnel_manager.tunnels[58932] = tunnel

    class MockErrResp:
        status_code = 400
        def json(self):
            return {"AliasError": "Alias 'auto_translator' already exists"}

    with patch("httpx.AsyncClient.post", return_value=MockErrResp()):
        resp = client.post(
            "/api/tunnels/58932/shorten",
            json={"alias": "auto_translator"},
            headers=headers
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "error"
        assert data["error_code"] == "alias_taken"
        assert "Tên link này đã có người sử dụng" in data["message"]


def test_control_plane_rate_limiter():
    from backend.main import control_plane_limiter
    control_plane_limiter.reset("testclient")
    original_max = control_plane_limiter.max_requests
    original_win = control_plane_limiter.window_seconds
    try:
        control_plane_limiter.max_requests = 3
        control_plane_limiter.window_seconds = 2

        client = TestClient(app)
        for _ in range(3):
            r = client.get("/api/status")
            assert r.status_code == 200

        r_blocked = client.get("/api/status")
        assert r_blocked.status_code == 429
        assert r_blocked.json()["error_code"] == "error.rate_limited"
        assert "retry-after" in r_blocked.headers
    finally:
        control_plane_limiter.max_requests = original_max
        control_plane_limiter.window_seconds = original_win
        control_plane_limiter.reset("testclient")


def test_heartbeat_api():
    client = TestClient(app)
    # Without CSRF token -> 403
    r_no_csrf = client.post("/api/heartbeat")
    assert r_no_csrf.status_code == 403

    # With CSRF token -> 200 OK
    r_ok = client.post("/api/heartbeat", headers={"x-pytunnel-token": SESSION_CSRF_TOKEN})
    assert r_ok.status_code == 200
    assert r_ok.json()["status"] == "ok"




