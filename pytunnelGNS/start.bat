@echo off
title PyTunnel Studio - Localhost Bridge
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    PYTUNNEL STUDIO v5.3 - TRUNG TAM QUAN TRI DUONG HAM LOCALHOST
echo ======================================================================
echo.

REM 1. Kiem tra Python
set "PY_CMD="
where python >nul 2>nul
if %errorlevel% equ 0 (
    set "PY_CMD=python"
    goto :has_python
)
where py >nul 2>nul
if %errorlevel% equ 0 (
    set "PY_CMD=py"
    goto :has_python
)
where python3 >nul 2>nul
if %errorlevel% equ 0 (
    set "PY_CMD=python3"
    goto :has_python
)

echo.
echo ======================================================================
echo   [!] KHONG TIM THAY PYTHON HOP LE TREN MAY CUA BAN!
echo ======================================================================
echo   De chay Dai Quan Sat PyTunnel Dashboard, ban co the cai dat:
echo   - Tai Python tai: https://www.python.org/downloads/
echo   - Luu y: Nho tich chon vao o "Add Python to PATH" khi cai dat.
echo.
echo   HOAC: Neu muon chay duong ham ngay ma khong can cai Python:
echo   - Hay chay file: run_tunnel_standalone.bat (o thu muc goc)
echo ======================================================================
echo.
pause
exit /b 1

:has_python

REM 2. Kiem tra thu vien nhanh (neu da co thi vao thang, 0ms cho doi)
%PY_CMD% -c "import fastapi, uvicorn, httpx, starlette, pydantic, websockets, jinja2" >nul 2>nul
if %errorlevel% equ 0 goto :deps_ready

echo [1/2] Dang kiem tra va cai dat thu vien lan dau (FastAPI, Uvicorn, WebSockets)...
%PY_CMD% -m pip install -r requirements.txt --quiet --disable-pip-version-check
if %errorlevel% neq 0 (
    echo [CANH BAO] Co the mot so thu vien chua cai duoc. Dang thu tiep tuc...
)

:deps_ready

REM 3. Tu dong giai phong cong 8787 neu co tien trinh cu dang chiem giu
%PY_CMD% -c "import socket, subprocess, sys; s = socket.socket(); err = s.connect_ex(('127.0.0.1', 8787)); s.close(); sys.exit(0) if err != 0 else None; out = subprocess.run(['netstat', '-ano'], capture_output=True, text=True).stdout; pids = [l.strip().split()[-1] for l in out.splitlines() if ':8787' in l and 'LISTENING' in l]; [subprocess.run(['taskkill', '/F', '/PID', p], capture_output=True) for p in pids]" >nul 2>nul

REM 4. Thong bao ro rang va chay Control Plane
cls
echo ======================================================================
echo    PYTUNNEL STUDIO v5.3 - TRUNG TAM QUAN TRI DUONG HAM LOCALHOST
echo ======================================================================
echo.
echo   [OK] Trinh thuc thi:     %PY_CMD%
echo   [OK] He thong:           Dang hoat dong on dinh
echo   [OK] Dia chi Dashboard:  http://127.0.0.1:8787
echo   [OK] Tu dong diet rac:   Win32 Job Object da kich hoat
echo.
echo ----------------------------------------------------------------------
echo   HUONG DAN SU DUNG:
echo   1. Giao dien web da duoc tu dong mo tren trinh duyet cua ban.
echo   2. Ban co the THU NHO cua so CMD nay de lam viec, choi game.
echo   3. DE TAT UNG DUNG: Nhan to hop phim Ctrl + C tai cua so nay.
echo ======================================================================
echo.
echo [DANG CHAY NEN] He thong san sang tiep nhan yeu cau tu trinh duyet...
echo.

%PY_CMD% run.py

if %errorlevel% neq 0 (
    echo.
    echo ======================================================================
    echo   [!] PyTunnel bi dung voi ma loi: %errorlevel%
    echo ======================================================================
    echo.
    pause
)
