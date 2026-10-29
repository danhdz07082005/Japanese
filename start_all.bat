@echo off
title GNS301 Realtime Game Server Hub
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    🎮 GNS301 REALTIME MULTIPLAYER SERVER & MISSION CONTROL HUB
echo ======================================================================
echo.

REM 1. Khởi động GameServer (.NET 8 WebSockets & REST API)
echo [1/2] Đang khởi động GameServer (.NET 8 Kestrel listening on :8080)...
start "GameServer (.NET 8 - Port 8080)" /min dotnet run --project "%~dp0GameServer\JapaneseMasteryBackendDotNet.csproj"

REM 2. Đợi 2 giây cho Server khởi tạo DB SQLite
timeout /t 2 /nobreak >nul

REM 3. Khởi động PyTunnel Dashboard & Cloudflare Tunnel
echo [2/2] Đang khởi động PyTunnel Studio & Đài Quan Sát Mission Control (:8787)...
cd /d "%~dp0pytunnelGNS"
start "PyTunnel Mission Control" cmd /c start.bat

echo.
echo ======================================================================
echo   ✅ HỆ THỐNG ĐÃ SẴN SÀNG!
echo.
echo   📡 Game Server API & WebSocket: http://127.0.0.1:8080
echo   📊 Mission Control Dashboard:   http://127.0.0.1:8787
echo.
echo   HƯỚNG DẪN KẾT NỐI ONLINE:
echo   1. Mở PyTunnel trên trình duyệt (đã tự động mở tại :8787).
echo   2. Nhập cổng: 8080 ^> Chọn chế độ CÔNG KHAI (Public) ^> Bấm Bắt Đầu.
echo   3. Bạn sẽ nhận được link HTTPS (ví dụ: https://xyz.trycloudflare.com).
echo   4. Mở Game Godot ^> Bấm '⚙️ Đổi Server' ^> Dán link vào là chơi Online!
echo ======================================================================
echo.
pause
