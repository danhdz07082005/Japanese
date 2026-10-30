@echo off
title Cloudflare Quick Tunnel (Zero Python Standalone)
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    CLOUDFLARE STANDALONE TUNNEL - KHONG CAN CAI PYTHON
echo ======================================================================
echo.

if not exist "pytunnelGNS\bin" mkdir "pytunnelGNS\bin"

set "CF_EXE="
if exist "pytunnelGNS\bin\cloudflared-2026.10.0.exe" set "CF_EXE=pytunnelGNS\bin\cloudflared-2026.10.0.exe"
if exist "pytunnelGNS\bin\cloudflared.exe" set "CF_EXE=pytunnelGNS\bin\cloudflared.exe"

if not "%CF_EXE%"=="" goto :run_tunnel

echo [1/2] Dang tai dong co Cloudflare Tunnel (cloudflared)...
echo       Chi can tai 1 lan duy nhat qua Windows curl, khoang 10-15 giay...
curl.exe -L "https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe" -o "pytunnelGNS\bin\cloudflared-2026.10.0.exe"

if exist "pytunnelGNS\bin\cloudflared-2026.10.0.exe" (
    set "CF_EXE=pytunnelGNS\bin\cloudflared-2026.10.0.exe"
    echo [OK] Da tai cloudflared thanh cong!
    goto :run_tunnel
)

powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe', 'pytunnelGNS\bin\cloudflared-2026.10.0.exe')" 2>nul
if exist "pytunnelGNS\bin\cloudflared-2026.10.0.exe" (
    set "CF_EXE=pytunnelGNS\bin\cloudflared-2026.10.0.exe"
    echo [OK] Da tai cloudflared thanh cong!
    goto :run_tunnel
)

echo [LOI] Khong the tai cloudflared. Vui long kiem tra ket noi Internet!
pause
exit /b 1

:run_tunnel
echo [2/2] Dang mo duong ham cho GameServer tai cong 8080...
echo.
echo ======================================================================
echo   CHU Y QUAN TRONG:
echo   Khi tunnel khoi dong, hay tim dong chua link dang:
echo   --^> https://xxxxxxxxxxxx.trycloudflare.com
echo.
echo   Sau do copy link do, mo Game Godot -^> Bam 'Doi Server' -^> Dan vao la choi!
echo   (Nhan Ctrl + C neu muon tat duong ham)
echo ======================================================================
echo.

"%CF_EXE%" tunnel --no-autoupdate --url http://127.0.0.1:8080
pause
