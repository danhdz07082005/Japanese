"""
PyTunnel Studio - Resilient Launcher
Bypasses Windows WinError 10013 on loopback socketpair creation (caused by Hyper-V / winnat dynamic port reservation bug).
"""
import sys
import socket

if sys.platform == "win32":
    _orig_socketpair = socket.socketpair

    def _resilient_socketpair(family=socket.AF_INET, type=socket.SOCK_STREAM, proto=0):
        try:
            return _orig_socketpair(family, type, proto)
        except (PermissionError, OSError):
            # Scan for available loopback port outside Windows dynamic exclusion ranges
            for test_port in range(25000, 35000):
                lsock = socket.socket(family, type, proto)
                try:
                    lsock.bind(("127.0.0.1", test_port))
                    lsock.listen(1)
                    csock = socket.socket(family, type, proto)
                    csock.setblocking(False)
                    try:
                        csock.connect(("127.0.0.1", test_port))
                    except (BlockingIOError, InterruptedError):
                        pass
                    csock.setblocking(True)
                    ssock, _ = lsock.accept()
                    lsock.close()
                    return (ssock, csock)
                except Exception:
                    lsock.close()
                    continue
            raise

    socket.socketpair = _resilient_socketpair

import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "backend.main:app",
        host="127.0.0.1",
        port=8787,
        log_level="warning",
        access_log=False,
    )
