from unittest.mock import AsyncMock
import httpx
import pytest
from starlette.testclient import TestClient

from backend.services.auth_proxy import (
    AuthProxyInstance,
    render_rate_limit_html,
    render_upstream_error_html,
    safe_redirect_target,
)


def test_safe_redirect_target():
    # Safe relative paths
    assert safe_redirect_target("/") == "/"
    assert safe_redirect_target("/app") == "/app"
    assert safe_redirect_target("/app/view?t=123") == "/app/view?t=123"

    # Malicious open-redirect targets (M1)
    assert safe_redirect_target("https://evil.com") == "/"
    assert safe_redirect_target("//evil.com") == "/"
    assert safe_redirect_target("/\\evil.com") == "/"
    assert safe_redirect_target("javascript:alert(1)") == "/"
    assert safe_redirect_target(None) == "/"
    assert safe_redirect_target("") == "/"


def test_xss_protection_in_gate_screen():
    instance = AuthProxyInstance(target_port=5000, proxy_port=18788, access_code="ABCD-EFGH", is_public=False)
    client = TestClient(instance._app)

    # Malicious XSS vector in query path (C1)
    malicious_path = '/"><script>alert(1)</script>'
    resp = client.get(malicious_path)
    assert resp.status_code == 401
    assert "<script>alert(1)</script>" not in resp.text
    assert "&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;" in resp.text or "&quot;&gt;" in resp.text


def test_gzip_content_encoding_and_multi_cookie_handling():
    import gzip

    instance = AuthProxyInstance(target_port=5000, proxy_port=18788, access_code="ABCD-EFGH", is_public=True)

    raw_html = b"<!DOCTYPE html><html><body>Decompressed Content</body></html>"
    # Mock upstream response with multiple Set-Cookie and content-encoding: gzip (C2, M2)
    mock_resp = httpx.Response(
        status_code=200,
        headers=[
            ("content-type", "text/html; charset=utf-8"),
            ("content-encoding", "gzip"),
            ("content-length", "42"),
            ("set-cookie", "session_id=123; Path=/"),
            ("set-cookie", "theme=dark; Path=/"),
        ],
        content=gzip.compress(raw_html),
    )
    instance.client.request = AsyncMock(return_value=mock_resp)

    client = TestClient(instance._app)
    resp = client.get("/data")
    assert resp.status_code == 200

    # Content-Encoding and Content-Length must be stripped from response to prevent ERR_CONTENT_DECODING_FAILED
    assert "content-encoding" not in resp.headers
    assert resp.text == "<!DOCTYPE html><html><body>Decompressed Content</body></html>"

    # Multiple Set-Cookie headers must both be present
    cookies_header = resp.headers.get_list("set-cookie")
    assert any("session_id=123" in c for c in cookies_header)
    assert any("theme=dark" in c for c in cookies_header)


def test_strip_internal_cookie_before_upstream():
    instance = AuthProxyInstance(target_port=5000, proxy_port=18788, access_code="ABCD-EFGH", is_public=False)

    captured_headers = {}

    async def mock_upstream_request(**kwargs):
        nonlocal captured_headers
        captured_headers = kwargs.get("headers", {})
        return httpx.Response(status_code=200, content=b"OK")

    instance.client.request = AsyncMock(side_effect=mock_upstream_request)
    client = TestClient(instance._app)

    # Log in first to get session
    login_resp = client.post("/__pytunnel_gate/login", data={"code": "ABCD-EFGH", "redirect_to": "/app"}, follow_redirects=False)
    assert "pytunnel_session" in login_resp.cookies
    session_cookie = login_resp.cookies["pytunnel_session"]

    # Send request with both internal session cookie and upstream app cookie (M4)
    resp = client.get("/app", headers={"cookie": f"pytunnel_session={session_cookie}; app_auth=user_token"})
    assert resp.status_code == 200

    # pytunnel_session must NOT be forwarded upstream
    forwarded_cookie = captured_headers.get("cookie", "")
    assert "pytunnel_session" not in forwarded_cookie
    assert "app_auth=user_token" in forwarded_cookie


def test_protected_login_flow_and_bruteforce_lock():
    instance = AuthProxyInstance(target_port=5000, proxy_port=18788, access_code="TEST-1234", is_public=False)
    client = TestClient(instance._app)

    # 1. Unauthenticated -> 401 gate
    resp = client.get("/")
    assert resp.status_code == 401
    assert "PyTunnel Shield" in resp.text

    # 2. 4 wrong attempts
    for i in range(4):
        bad_resp = client.post("/__pytunnel_gate/login", data={"code": f"WRONG-{i}"}, headers={"cf-connecting-ip": "1.2.3.4"})
        assert bad_resp.status_code == 401

    # 3. 5th wrong attempt -> 429 Locked
    locked_resp = client.post("/__pytunnel_gate/login", data={"code": "WRONG-5"}, headers={"cf-connecting-ip": "1.2.3.4"})
    assert locked_resp.status_code == 429

    # 4. Correct attempt on different IP -> 302 and cookie
    ok_resp = client.post("/__pytunnel_gate/login", data={"code": "TEST-1234", "redirect_to": "/secret"}, headers={"cf-connecting-ip": "1.2.3.5"}, follow_redirects=False)
    assert ok_resp.status_code == 302
    assert ok_resp.headers["location"] == "/secret"
    assert "pytunnel_session" in ok_resp.cookies


def test_upstream_error_rendering():
    html_vi = render_upstream_error_html("vi")
    assert "502" in html_vi
    assert "Ứng dụng chưa phản hồi" in html_vi
    assert "continuousNeonFlow" in html_vi

    html_en = render_upstream_error_html("en")
    assert "502" in html_en
    assert "App is not responding" in html_en
    assert "continuousNeonFlow" in html_en


def test_visitor_rate_limiting_anti_f5():
    instance = AuthProxyInstance(target_port=5000, proxy_port=18788, access_code="TEST-1234", is_public=True)
    instance.rate_limiter.max_requests = 3
    instance.rate_limiter.window_seconds = 5
    instance.rate_limiter.cooldown_seconds = 10

    instance.client.request = AsyncMock(return_value=httpx.Response(status_code=200, content=b"OK"))
    client = TestClient(instance._app)

    ip_headers = {"cf-connecting-ip": "198.51.100.42"}

    # 3 normal requests pass
    for _ in range(3):
        res = client.get("/page", headers=ip_headers)
        assert res.status_code == 200

    # 4th request (rapid F5 spam) is blocked with 429
    spam_res = client.get("/page", headers=ip_headers)
    assert spam_res.status_code == 429
    assert "retry-after" in spam_res.headers
    assert int(spam_res.headers["retry-after"]) > 0
    assert "429" in spam_res.text

    # JSON request receives structured JSON with 429
    json_headers = {**ip_headers, "accept": "application/json"}
    json_res = client.get("/api/data", headers=json_headers)
    assert json_res.status_code == 429
    data = json_res.json()
    assert data["error_code"] == "error.rate_limited"
    assert "retry_after" in data

    # Static asset (.js, .wasm) receives clean plain text on 429, never syntax-breaking HTML
    js_headers = {**ip_headers, "accept": "*/*"}
    js_res = client.get("/main.dart.js", headers=js_headers)
    assert js_res.status_code == 429
    assert "<!DOCTYPE html>" not in js_res.text
    assert "Too Many Requests" in js_res.text


def test_rate_limit_html_rendering():
    html_vi = render_rate_limit_html("vi", retry_after=20)
    assert "429" in html_vi
    assert "Spam F5" in html_vi
    assert "continuousNeonFlow" in html_vi

    html_en = render_rate_limit_html("en", retry_after=20)
    assert "429" in html_en
    assert "Too Many Requests" in html_en
    assert "continuousNeonFlow" in html_en

