"""Lifecycle and idle shutdown monitor for PyTunnel Control Plane."""
import asyncio
import logging
import os
import time
from typing import Callable

logger = logging.getLogger("pytunnel.lifecycle")


class IdleShutdownMonitor:
    """Monitors browser dashboard heartbeats and cleanly shuts down CMD if idle with 0 tunnels."""

    def __init__(self, idle_timeout_seconds: int = 90):
        self.idle_timeout_seconds = idle_timeout_seconds
        self.last_heartbeat: float = time.time()
        self.has_received_heartbeat: bool = False
        self._task: asyncio.Task | None = None
        self.enabled: bool = True

    def record_heartbeat(self) -> None:
        self.last_heartbeat = time.time()
        self.has_received_heartbeat = True

    async def start(self, get_active_tunnel_count: Callable[[], int]) -> None:
        if not self.enabled:
            return
        self._task = asyncio.create_task(self._monitor_loop(get_active_tunnel_count))

    async def stop(self) -> None:
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _monitor_loop(self, get_active_tunnel_count: Callable[[], int]) -> None:
        while True:
            await asyncio.sleep(5)
            if not self.has_received_heartbeat or not self.enabled:
                continue

            idle_duration = time.time() - self.last_heartbeat
            active_tunnels = get_active_tunnel_count()

            # Rule 1: Never auto-close if there are active tunnels running!
            if active_tunnels > 0:
                continue

            # Rule 2: If no active tunnels and no browser heartbeat for >= timeout:
            if idle_duration >= self.idle_timeout_seconds:
                logger.info(
                    "No dashboard tab activity and zero tunnels for %ds. Automatically closing PyTunnel...",
                    int(idle_duration),
                )
                os._exit(0)


global_idle_monitor = IdleShutdownMonitor(idle_timeout_seconds=90)
