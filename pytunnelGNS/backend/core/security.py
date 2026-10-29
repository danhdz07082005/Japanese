import collections
import hashlib
import hmac
import secrets
import time

# No look-alike characters (0/O, 1/I).
_CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"


def generate_access_code() -> str:
    raw = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
    return f"{raw[:4]}-{raw[4:]}"


def _normalize_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


def verify_access_code(given: str, expected: str) -> bool:
    if not given or not expected:
        return False
    return hmac.compare_digest(_normalize_code(given).encode(), _normalize_code(expected).encode())


def sign_session(secret: bytes) -> str:
    payload = f"{secrets.token_hex(12)}.{int(time.time())}"
    sig = hmac.new(secret, payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}.{sig}"


def verify_session(value: str | None, secret: bytes, max_age: int) -> bool:
    if not value or value.count(".") != 2:
        return False
    sid, issued, sig = value.split(".")
    if not issued.isdigit() or time.time() - int(issued) > max_age:
        return False
    expected = hmac.new(secret, f"{sid}.{issued}".encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(sig, expected)


class BruteForceLimiter:
    """Per-IP failed-attempt counter with temporary lockout (memory-bounded)."""

    def __init__(self, max_attempts: int, window_seconds: int, lock_seconds: int, max_tracked: int = 10_000):
        self.max_attempts = max_attempts
        self.window = window_seconds
        self.lock = lock_seconds
        self.max_tracked = max_tracked
        self._failures: dict[str, list[float]] = {}
        self._locked_until: dict[str, float] = {}

    def locked_for(self, ip: str) -> int:
        """Seconds remaining on the lock (0 = not locked)."""
        return max(0, int(self._locked_until.get(ip, 0) - time.time()))

    def record_failure(self, ip: str) -> int:
        """Register a failure; returns remaining attempts (0 means now locked)."""
        now = time.time()
        if len(self._failures) >= self.max_tracked:
            self._prune(now)
        recent = [ts for ts in self._failures.get(ip, []) if now - ts < self.window] + [now]
        if len(recent) >= self.max_attempts:
            self._failures.pop(ip, None)
            self._locked_until[ip] = now + self.lock
            return 0
        self._failures[ip] = recent
        return self.max_attempts - len(recent)

    def record_success(self, ip: str) -> None:
        self._failures.pop(ip, None)
        self._locked_until.pop(ip, None)

    def _prune(self, now: float) -> None:
        self._failures = {ip: ts for ip, ts in self._failures.items() if ts and now - ts[-1] < self.window}
        self._locked_until = {ip: until for ip, until in self._locked_until.items() if until > now}


class RequestRateLimiter:
    """Memory-bounded sliding-window request rate limiter per IP with automatic cooldown.

    Prevents aggressive F5 spamming or DoS flooding while allowing burst traffic for
    normal web asset loading.
    """

    def __init__(
        self,
        max_requests: int = 80,
        window_seconds: int = 10,
        cooldown_seconds: int = 20,
        max_tracked: int = 10_000,
    ) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.cooldown_seconds = cooldown_seconds
        self.max_tracked = max_tracked
        self._requests: dict[str, collections.deque[float]] = {}
        self._blocked_until: dict[str, float] = {}

    def check(self, ip: str) -> tuple[bool, int]:
        """Check if request from IP is allowed.

        Returns:
            (True, 0) if allowed.
            (False, retry_after_seconds) if rate limit is exceeded.
        """
        now = time.time()

        # 1. Check if currently in cooldown
        blocked_until = self._blocked_until.get(ip, 0.0)
        if blocked_until > now:
            return False, max(1, int(blocked_until - now))
        elif blocked_until != 0.0:
            self._blocked_until.pop(ip, None)
            self._requests.pop(ip, None)

        # 2. Memory bound check
        if len(self._requests) >= self.max_tracked:
            self._prune(now)

        # 3. Sliding window check
        q = self._requests.get(ip)
        if q is None:
            q = collections.deque()
            self._requests[ip] = q

        cutoff = now - self.window_seconds
        while q and q[0] <= cutoff:
            q.popleft()

        if len(q) >= self.max_requests:
            # Limit exceeded -> put in cooldown
            self._blocked_until[ip] = now + self.cooldown_seconds
            self._requests.pop(ip, None)
            return False, self.cooldown_seconds

        q.append(now)
        return True, 0

    def reset(self, ip: str) -> None:
        """Reset rate limiter for a specific IP (e.g. for testing)."""
        self._requests.pop(ip, None)
        self._blocked_until.pop(ip, None)

    def _prune(self, now: float) -> None:
        """Purge stale entries to strictly cap memory usage."""
        cutoff = now - self.window_seconds
        self._requests = {
            ip: q for ip, q in self._requests.items()
            if q and q[-1] > cutoff
        }
        self._blocked_until = {
            ip: until for ip, until in self._blocked_until.items()
            if until > now
        }

