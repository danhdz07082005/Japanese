"""Tunnel lifecycle management. Single aggregate owner per tunnel with full rollback on error."""
import asyncio
from enum import Enum
import logging
import socket
import time
from typing import Any

from backend.core.config import TUNNEL_START_TIMEOUT
from backend.core.errors import AppError
from backend.core.parser import Target
from backend.services.auth_proxy import AuthProxyInstance
from backend.services.cloudflared import CloudflaredProcess
from backend.services.engine import engine

logger = logging.getLogger("pytunnel.manager")


class TunnelState(str, Enum):
    STARTING = "STARTING"
    ONLINE = "ONLINE"
    FAILED = "FAILED"
    STOPPED = "STOPPED"


def find_free_socket(start_port: int = 0, attempts: int = 50) -> tuple[int, socket.socket]:
    """Allocate an available socket for internal auth proxy using OS ephemeral ports."""
    if start_port == 0:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        return port, sock

    for p in range(start_port, start_port + attempts):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", p))
            return p, sock
        except OSError:
            sock.close()
            continue
    raise RuntimeError(f"Could not bind a free proxy port in range {start_port}-{start_port + attempts}")


class Tunnel:
    def __init__(self, target: Target, is_public: bool) -> None:
        self.port = target.port
        self.path = target.path
        self.is_public = is_public
        self.state = TunnelState.STARTING
        self.created_at = time.time()
        self.tunnel_url: str = ""
        self.short_url: str = ""
        self.error_reason: str = ""

        self.proxy_port: int = 0
        self._bound_sock: socket.socket | None = None
        self.proxy: AuthProxyInstance | None = None
        self._proxy_task: asyncio.Task | None = None
        self.process: CloudflaredProcess | None = None

    def to_dict(self) -> dict[str, Any]:
        full_url = (self.tunnel_url + self.path) if self.tunnel_url else ""
        uptime = int(time.time() - self.created_at) if self.state == TunnelState.ONLINE else 0

        req_count = self.proxy.total_requests if self.proxy else 0
        blocked_count = self.proxy.blocked_count if self.proxy else 0
        online_count = self.proxy.active_visitors_count() if self.proxy else 0
        code = self.proxy.access_code if self.proxy else ""
        cur_public = self.proxy.is_public if self.proxy else self.is_public

        return {
            "port": self.port,
            "path": self.path,
            "proxy_port": self.proxy_port,
            "tunnel_url": self.tunnel_url,
            "full_tunnel_url": full_url,
            "short_url": self.short_url,
            "state": self.state.value,
            "pid": self.process.pid if self.process else None,
            "created_at": self.created_at,
            "uptime_seconds": uptime,
            "is_public": cur_public,
            "access_code": code,
            "request_count": req_count,
            "blocked_count": blocked_count,
            "active_visitors_count": online_count,
            "job_object": self.process.in_job if self.process else False,
            "error_reason": self.error_reason,
        }

    async def start(self) -> None:
        try:
            # 1. Download / verify binary if needed (non-blocking for other tunnels)
            exe_path = await engine.ensure()

            # 2. Bind free proxy port beforehand
            self.proxy_port, self._bound_sock = find_free_socket()

            # 3. Create AuthProxy and launch background task
            from backend.core.security import generate_access_code
            init_code = generate_access_code()
            self.proxy = AuthProxyInstance(
                target_port=self.port,
                proxy_port=self.proxy_port,
                access_code=init_code,
                is_public=self.is_public,
            )
            sock = self._bound_sock
            self._bound_sock = None  # Uvicorn now owns this socket
            self._proxy_task = asyncio.create_task(self.proxy.serve(sock))
            await asyncio.sleep(0.05)

            # 4. Launch cloudflared process
            self.process = CloudflaredProcess(exe=exe_path, local_port=self.proxy_port)
            self.process.start()

            # 5. Await public URL from cloudflared stderr
            self.tunnel_url = await self.process.wait_for_url(timeout=TUNNEL_START_TIMEOUT)
            self.state = TunnelState.ONLINE
            logger.info("Tunnel ONLINE: port %d -> %s", self.port, self.tunnel_url)

        except Exception as exc:
            self.state = TunnelState.FAILED
            self.error_reason = str(exc)
            await self._cleanup_resources()
            raise exc

    async def _cleanup_resources(self) -> None:
        if self.process:
            await self.process.stop()
            self.process = None

        if self.proxy:
            await self.proxy.stop()
            self.proxy = None

        if self._proxy_task:
            try:
                await asyncio.wait_for(asyncio.shield(self._proxy_task), timeout=2.0)
            except (asyncio.TimeoutError, asyncio.CancelledError, Exception):
                self._proxy_task.cancel()
                try:
                    await self._proxy_task
                except (asyncio.CancelledError, Exception):
                    pass
            self._proxy_task = None

        if self._bound_sock:
            try:
                self._bound_sock.close()
            except Exception:
                pass
            self._bound_sock = None

    async def stop(self) -> None:
        self.state = TunnelState.STOPPED
        await self._cleanup_resources()


class TunnelManager:
    def __init__(self) -> None:
        self.tunnels: dict[int, Tunnel] = {}
        self._lock = asyncio.Lock()

    def get(self, port: int) -> Tunnel | None:
        return self.tunnels.get(port)

    def list_all(self) -> list[dict[str, Any]]:
        return [t.to_dict() for t in self.tunnels.values()]

    async def create_tunnel(self, target: Target, is_public: bool) -> Tunnel:
        async with self._lock:
            existing = self.tunnels.get(target.port)
            if existing and existing.state in (TunnelState.ONLINE, TunnelState.STARTING):
                raise AppError("error.tunnel_exists", port=target.port)

            tunnel = Tunnel(target=target, is_public=is_public)
            self.tunnels[target.port] = tunnel

        # Start tunnel outside the manager lock so other operations are not blocked
        try:
            await tunnel.start()
            return tunnel
        except Exception:
            # If start fails, remove from active dictionary
            async with self._lock:
                self.tunnels.pop(target.port, None)
            raise

    async def stop_tunnel(self, port: int) -> bool:
        async with self._lock:
            tunnel = self.tunnels.pop(port, None)
        if not tunnel:
            return False
        await tunnel.stop()
        return True

    async def kill_all(self) -> int:
        async with self._lock:
            active = list(self.tunnels.values())
            self.tunnels.clear()

        if not active:
            return 0

        await asyncio.gather(*(t.stop() for t in active), return_exceptions=True)
        logger.info("Master Kill-Switch executed: terminated %d tunnels", len(active))
        return len(active)


global_tunnel_manager = TunnelManager()
