"""Downloads and verifies the pinned cloudflared binary (SHA-256 is always enforced)."""
import asyncio
import hashlib
import logging
from pathlib import Path

import httpx

from backend.core.config import CLOUDFLARED_EXE, CLOUDFLARED_VERSION, cloudflared_asset
from backend.core.errors import AppError

logger = logging.getLogger("pytunnel.engine")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Engine:
    def __init__(self, exe: Path = CLOUDFLARED_EXE) -> None:
        self.exe = exe
        self.percent = 0
        self.downloading = False
        self.error: str | None = None
        self._verified = False
        self._lock = asyncio.Lock()

    def status(self) -> dict:
        return {
            "version": CLOUDFLARED_VERSION,
            "ready": self._verified or self.exe.exists(),
            "downloading": self.downloading,
            "percent": self.percent,
            "error": self.error,
        }

    async def ensure(self) -> Path:
        async with self._lock:
            if not self._verified:
                await asyncio.to_thread(self._ensure_sync)
                self._verified = True
            return self.exe

    def _ensure_sync(self) -> None:
        try:
            asset, expected = cloudflared_asset()
        except RuntimeError as exc:
            raise AppError("error.engine_unsupported", status=500, machine=str(exc))

        if self.exe.exists() and _sha256(self.exe) == expected:
            return
        self.exe.unlink(missing_ok=True)
        self.exe.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.exe.with_suffix(".tmp")
        url = f"https://github.com/cloudflare/cloudflared/releases/download/{CLOUDFLARED_VERSION}/{asset}"
        self.downloading, self.percent, self.error = True, 0, None
        try:
            logger.info("Downloading %s", url)
            with httpx.stream("GET", url, follow_redirects=True, timeout=httpx.Timeout(30.0, read=60.0)) as resp:
                resp.raise_for_status()
                total = int(resp.headers.get("content-length") or 0)
                done = 0
                with tmp.open("wb") as fh:
                    for chunk in resp.iter_bytes(1 << 16):
                        fh.write(chunk)
                        done += len(chunk)
                        if total:
                            self.percent = min(99, done * 100 // total)
            if _sha256(tmp) != expected:
                self.error = "sha256"
                raise AppError("error.engine_hash_mismatch", status=502)
            tmp.replace(self.exe)
            self.percent = 100
        except httpx.HTTPError as exc:
            self.error = type(exc).__name__
            raise AppError("error.engine_download_failed", status=502, reason=str(exc) or type(exc).__name__)
        finally:
            self.downloading = False
            tmp.unlink(missing_ok=True)


engine = Engine()
