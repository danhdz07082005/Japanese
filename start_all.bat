@echo off
title GNS301 Realtime Game Server Hub
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    GNS301 REALTIME MULTIPLAYER SERVER AND MISSION CONTROL HUB
echo ======================================================================
echo.

REM 1. Khoi dong Kuroshiro Microservice (Dich Kanji/Kana sang Romaji - Port 8081)
echo [1/3] Dang khoi dong Kuroshiro Kanji Translator (:8081)...
start "Kuroshiro Kanji Translator (:8081)" /d "%~dp0GameServer" cmd /k "start_kuroshiro.bat"

REM Cho 3 giay de Kuroshiro khoi tao tu dien Kuromoji
ping 127.0.0.1 -n 4 >nul

REM 2. Khoi dong GameServer (.NET 8 Kestrel listening on port 8080)
echo [2/3] Dang khoi dong GameServer (.NET 8 listening on port 8080)...
start "GameServer (.NET 8 - Port 8080)" /d "%~dp0GameServer" cmd /k "dotnet run"

REM Cho 2 giay cho Server khoi tao SQLite va san sang
ping 127.0.0.1 -n 3 >nul

REM 3. Khoi dong PyTunnel Dashboard va Cloudflare Tunnel (:8787)
echo [3/3] Dang khoi dong PyTunnel Mission Control Dashboard (:8787)...
start "PyTunnel Mission Control" /d "%~dp0pytunnelGNS" cmd /k "start.bat"

echo.
echo ======================================================================
echo   [OK] HE THONG 4 CUA SO DA DUOC KHOI DONG THANH CONG!
echo.
echo   * 1. Kuroshiro Translator:      http://127.0.0.1:8081 (Dich Kanji sang Romaji)
echo   * 2. Game Server API and WS:    http://127.0.0.1:8080 (REST + WebSocket Gateway)
echo   * 3. PyTunnel Mission Control:  http://127.0.0.1:8787 (Dai quan sat + Tunnel)
echo   * 4. Game Client Godot:         Mo GameClient bang Godot Engine
echo.
echo   HUONG DAN KET NOI CHOI ONLINE:
echo   1. Trinh duyet se tu dong mo PyTunnel tai http://127.0.0.1:8787
echo   2. Nhap cong: 8080 - Chon che do PUBLIC (Cong khai) - Bam Bat Dau.
echo   3. Copy link HTTPS nhan duoc (vi du: https://xxx.trycloudflare.com).
echo   4. Mo Game Godot - Bam '⚙️ Doi Server' - Dan link vao la choi Online!
echo.
echo   Luu y: Neu may ban ban CHUA CAI PYTHON, co the chay rieng Tunnel bang:
echo   --^> "run_tunnel_standalone.bat" (Tu dong mo tunnel khong can Python)
echo ======================================================================
echo.
pause
