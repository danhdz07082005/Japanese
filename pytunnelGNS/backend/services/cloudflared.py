"""One cloudflared quick-tunnel process. stderr is drained for the whole lifetime (no pipe deadlock)."""
import asyncio
import collections
import logging
import re
import subprocess
import threading
from pathlib import Path

from backend.core.errors import AppError
from backend.services.win_job import job_object

logger = logging.getLogger("pytunnel.cloudflared")

# The "api." host appears in cloudflared *error* lines and must never be taken as the tunnel URL.
URL_PATTERN = re.compile(r"https://(?!api\.)[a-z0-9-]+\.trycloudflare\.com", re.IGNORECASE)
_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)


class CloudflaredProcess:
    def __init__(self, exe: Path, local_port: int, command: list[str] | None = None) -> None:
        self._command = command or [str(exe), "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{local_port}"]
        self._proc: subprocess.Popen | None = None
        self._url_ready = asyncio.Event()
        self._loop: asyncio.AbstractEventLoop | None = None
        self.tail: collections.deque[str] = collections.deque(maxlen=30)
        self.url: str | None = None
        self.in_job = False

    @property
    def pid(self) -> int | None:
        return self._proc.pid if self._proc else None

    @property
    def alive(self) -> bool:
        return bool(self._proc) and self._proc.poll() is None

    def start(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._proc = subprocess.Popen(
            self._command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=_NO_WINDOW,
        )
        self.in_job = job_object.assign(self._proc.pid)
        threading.Thread(target=self._drain, name=f"cloudflared-{self._proc.pid}", daemon=True).start()

    def _drain(self) -> None:
        assert self._proc and self._proc.stderr and self._loop
        for line in self._proc.stderr:
            line = line.rstrip()
            self.tail.append(line)
            if self.url is None and (match := URL_PATTERN.search(line)):
                self.url = match.group(0).lower()
                self._signal()
        self._signal()  # EOF: process ended, wake any waiter

    def _signal(self) -> None:
        try:
            self._loop.call_soon_threadsafe(self._url_ready.set)
        except RuntimeError:  # loop already closed during shutdown
            pass

    async def wait_for_url(self, timeout: float) -> str:
        try:
            await asyncio.wait_for(self._url_ready.wait(), timeout)
        except asyncio.TimeoutError:
            raise AppError("error.tunnel_start_timeout", status=504, seconds=int(timeout))
        if self.url:
            return self.url
        code = self._proc.wait() if self._proc else -1
        raise AppError("error.tunnel_process_exited", status=502, code=code, detail=self.last_error())

    def last_error(self) -> str:
        errors = [line for line in self.tail if " ERR " in line or "error" in line.lower()]
        return (errors or list(self.tail) or [""])[-1][-300:]

    async def stop(self) -> None:
        proc, self._proc = self._proc, None
        if not proc or proc.poll() is not None:
            return
        proc.terminate()
        try:
            await asyncio.to_thread(proc.wait, 3)
        except subprocess.TimeoutExpired:
            proc.kill()
            await asyncio.to_thread(proc.wait, 3)
