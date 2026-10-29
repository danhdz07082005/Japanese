@echo off
title PyTunnel Studio - Localhost Bridge
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    PYTUNNEL STUDIO v5.3 - TRUNG TAM QUAN TRI DUONG HAM LOCALHOST
echo ======================================================================
echo.

REM 1. Kiem tra Python that su (chong fake Microsoft Store shortcut)
set "PY_CMD="
python -c "import sys; sys.exit(0)" >nul 2>nul
if %errorlevel% equ 0 (
    set "PY_CMD=python"
) else (
    py -c "import sys; sys.exit(0)" >nul 2>nul
    if %errorlevel% equ 0 (
        set "PY_CMD=py"
    ) else (
        python3 -c "import sys; sys.exit(0)" >nul 2>nul
        if %errorlevel% equ 0 (
            set "PY_CMD=python3"
        )
    )
)

if "%PY_CMD%"=="" (
    echo.
    echo ======================================================================
    echo   [!] KHONG TIM THAY PYTHON HOP LE TREN MAY CUA BAN!
    echo ======================================================================
    echo   De chay Dai Quan Sat PyTunnel Dashboard, ban co 2 lua chon:
    echo.
    echo   [LUA CHON 1 - NEU MUON DUNG WEB DASHBOARD]:
    echo   - Tai Python tai: https://www.python.org/downloads/
    echo   - QUAN TRONG: Khi cai dat, nho TICH CHON vao o "Add Python to PATH"
    echo.
    echo   [LUA CHON 2 - CHAY TUNNEL NGAY KHONG CAN PYTHON]:
    echo   - Nhap dup vao file "run_tunnel_standalone.bat" o thu muc goc (E:\8\Sever)
    echo   - File do se tu dong mo duong ham ra Internet ma khong can cai Python!
    echo ======================================================================
    echo.
    pause
    exit /b 1
)

REM 2. Kiem tra dong co cloudflared trong thu muc bin
if not exist "bin" mkdir "bin"
if not exist "bin\cloudflared-2026.10.0.exe" (
    echo [1/3] Dang kiem tra va tai dong co Cloudflare Tunnel (50MB)...
    echo       (Chi can tai 1 lan duy nhat, vui long doi vai giay)...
    curl.exe -L "https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe" -o "bin\cloudflared-2026.10.0.exe"
    if not exist "bin\cloudflared-2026.10.0.exe" (
        powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-windows-amd64.exe', 'bin\cloudflared-2026.10.0.exe')" 2>nul
    )
)

REM 3. Kiem tra thu vien nhanh (neu da co thi vao thang, 0ms cho doi)
%PY_CMD% -c "import fastapi, uvicorn, httpx, starlette, pydantic, websockets, jinja2" >nul 2>nul
if %errorlevel% equ 0 goto :deps_ready

echo [2/3] Dang kiem tra va cai dat thu vien lan dau (FastAPI, Uvicorn, WebSockets)...
%PY_CMD% -m pip install -r requirements.txt --disable-pip-version-check
if %errorlevel% neq 0 (
    echo [CANH BAO] Co the mot so thu vien chua cai duoc. Dang thu tiep tuc...
)
:deps_ready

REM 4. Tu dong giai phong cong 8787 neu co tien trinh cu dang chiem giu
%PY_CMD% -c "import socket, subprocess, sys; s = socket.socket(); err = s.connect_ex(('127.0.0.1', 8787)); s.close(); sys.exit(0) if err != 0 else None; out = subprocess.run(['netstat', '-ano'], capture_output=True, text=True).stdout; pids = [l.strip().split()[-1] for l in out.splitlines() if ':8787' in l and 'LISTENING' in l]; [subprocess.run(['taskkill', '/F', '/PID', p], capture_output=True) for p in pids]" >nul 2>nul

REM 5. Thong bao ro rang va chay Control Plane
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

%PY_CMD% -m uvicorn backend.main:app --host 127.0.0.1 --port 8787 --log-level warning --no-access-log
if %errorlevel% neq 0 (
    echo.
    echo ======================================================================
    echo   [!] PyTunnel bi dung dot ngot voi ma loi: %errorlevel%
    echo   Neu gap loi thieu thu vien, hay chay lenh:
    echo   %PY_CMD% -m pip install -r requirements.txt
    echo ======================================================================
    echo.
    pause
)
