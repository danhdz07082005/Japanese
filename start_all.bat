@echo off
title GNS301 Realtime Game Server Hub
cd /d "%~dp0"

echo ======================================================================
echo    GNS301 REALTIME MULTIPLAYER SERVER AND MISSION CONTROL HUB
echo ======================================================================
echo.

REM 1. Khoi dong GameServer (.NET 8 Kestrel listening on port 8080)
echo [1/2] Dang khoi dong GameServer (.NET 8 listening on port 8080)...
start "GameServer (.NET 8 - Port 8080)" cmd /k "cd /d "%~dp0GameServer" && dotnet run"

REM 2. Cho 2 giay cho Server khoi tao SQLite va san sang
ping 127.0.0.1 -n 3 >nul

REM 3. Khoi dong PyTunnel Dashboard va Cloudflare Tunnel
echo [2/2] Dang khoi dong PyTunnel Mission Control Dashboard (:8787)...
start "PyTunnel Mission Control" cmd /k "cd /d "%~dp0pytunnelGNS" && call start.bat"

echo.
echo ======================================================================
echo   [OK] HE THONG DA DUOC KHOI DONG THANH CONG!
echo.
echo   * Game Server API and WebSocket: http://127.0.0.1:8080
echo   * Mission Control Dashboard:    http://127.0.0.1:8787
echo.
echo   HUONG DAN KET NOI CHOI ONLINE:
echo   1. Trinh duyet se tu dong mo PyTunnel tai http://127.0.0.1:8787
echo   2. Nhap cong: 8080 - Chon che do PUBLIC (Cong khai) - Bam Bat Dau.
echo   3. Copy link HTTPS nhan duoc (vi du: https://xxx.trycloudflare.com).
echo   4. Mo Game Godot - Bam 'Doi Server' - Dan link vao la choi Online!
echo.
echo   Luu y: Neu may ban ban CHUA CAI PYTHON, hay mo file sau de bat Tunnel:
echo   --^> "run_tunnel_standalone.bat" (Tu dong chay 100%% khong can Python)
echo ======================================================================
echo.
pause
