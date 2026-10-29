import pytest

from backend.core.errors import AppError
from backend.core.parser import parse_target, validate_port
from backend.core.security import (
    BruteForceLimiter,
    RequestRateLimiter,
    generate_access_code,
    sign_session,
    verify_access_code,
    verify_session,
)


def test_validate_port():
    assert validate_port(5000) == 5000
    assert validate_port(3000) == 3000
    assert validate_port(58931) == 58931

    with pytest.raises(AppError) as exc:
        validate_port(80)
    assert exc.value.code == "error.port_out_of_range"

    with pytest.raises(AppError) as exc:
        validate_port(3389)
    assert exc.value.code == "error.port_blacklisted"

    with pytest.raises(AppError) as exc:
        validate_port(8787)
    assert exc.value.code == "error.port_internal"

    # Port 8788 and dynamic ranges are now valid for tunneling local applications
    assert validate_port(8788) == 8788
    assert validate_port(8795) == 8795


def test_parse_target():
    # Pure port number
    t1 = parse_target("5000")
    assert t1.port == 5000
    assert t1.path == ""

    # localhost:port
    t2 = parse_target("localhost:3000")
    assert t2.port == 3000
    assert t2.path == ""

    # Complex target with token and fragment
    t3 = parse_target("http://127.0.0.1:58931?t=1791247438#dashboard")
    assert t3.port == 58931
    assert t3.path == "?t=1791247438#dashboard"

    # Non-local hosts must be rejected (M5)
    with pytest.raises(AppError) as exc:
        parse_target("http://192.168.1.5:5000")
    assert exc.value.code == "error.host_not_local"

    with pytest.raises(AppError) as exc:
        parse_target("http://evil-attacker.com:5000")
    assert exc.value.code == "error.host_not_local"


def test_access_code_verification():
    code = generate_access_code()
    assert len(code) == 9
    assert "-" in code

    assert verify_access_code(code, code) is True
    assert verify_access_code(code.lower(), code) is True
    assert verify_access_code(code.replace("-", ""), code) is True
    assert verify_access_code("WRONG123", code) is False
    assert verify_access_code("", code) is False


def test_session_cookie_hmac():
    secret = b"k" * 32
    cookie = sign_session(secret)
    assert verify_session(cookie, secret, max_age=86400) is True

    # Wrong secret
    assert verify_session(cookie, b"x" * 32, max_age=86400) is False

    # Tampered cookie
    assert verify_session(cookie + "bad", secret, max_age=86400) is False

    # Expired cookie
    assert verify_session(cookie, secret, max_age=-10) is False


def test_brute_force_limiter():
    limiter = BruteForceLimiter(max_attempts=3, window_seconds=60, lock_seconds=120)
    ip = "10.0.0.1"

    assert limiter.locked_for(ip) == 0

    # 1st failure: 2 attempts left
    rem1 = limiter.record_failure(ip)
    assert rem1 == 2
    assert limiter.locked_for(ip) == 0

    # 2nd failure: 1 attempt left
    rem2 = limiter.record_failure(ip)
    assert rem2 == 1
    assert limiter.locked_for(ip) == 0

    # 3rd failure: locked out (0 attempts left)
    rem3 = limiter.record_failure(ip)
    assert rem3 == 0
    assert limiter.locked_for(ip) > 0

    # Success clears lockout
    limiter.record_success(ip)
    assert limiter.locked_for(ip) == 0


def test_request_rate_limiter():
    limiter = RequestRateLimiter(max_requests=5, window_seconds=2, cooldown_seconds=5)
    ip = "192.168.1.100"

    # First 5 requests allowed
    for _ in range(5):
        allowed, retry_after = limiter.check(ip)
        assert allowed is True
        assert retry_after == 0

    # 6th request (burst/spam) blocked -> enters cooldown
    allowed, retry_after = limiter.check(ip)
    assert allowed is False
    assert retry_after > 0

    # Another IP is unaffected
    other_ip = "192.168.1.101"
    allowed_other, _ = limiter.check(other_ip)
    assert allowed_other is True

    # Reset clears cooldown
    limiter.reset(ip)
    allowed_after_reset, _ = limiter.check(ip)
    assert allowed_after_reset is True

