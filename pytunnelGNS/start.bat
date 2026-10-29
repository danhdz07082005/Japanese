@echo off
title PyTunnel Studio - Localhost Bridge
chcp 65001 >nul
cd /d "%~dp0"

echo ======================================================================
echo    PYTUNNEL STUDIO v5.3 - TRUNG TAM QUAN TRI DUONG HAM LOCALHOST
echo ======================================================================
echo.

REM 1. Kiem tra Python
where python >nul 2>nul
if %errorlevel% equ 0 goto :has_python
echo [!] LOI: Khong tim thay Python tren may cua ban!
echo     Vui long cai dat Python tu https://python.org
echo     Luu y: Nho tich chon vao muc Add Python to PATH khi cai dat.
echo.
pause
exit /b 1
:has_python

REM 2. Kiem tra thu vien nhanh (Senior Luoi: neu da co thi vao thang, 0ms cho doi)
python -c "import fastapi, uvicorn, httpx, starlette, pydantic, websockets, jinja2" >nul 2>nul
if %errorlevel% equ 0 goto :deps_ready

echo [1/2] Dang kiem tra va cai dat thu vien lan dau...
python -m pip install -r requirements.txt --quiet --disable-pip-version-check
if %errorlevel% neq 0 (
    echo [CANH BAO] Co the mot so thu vien chua cai duoc. Dang thu tiep tuc...
)
:deps_ready

REM 3. Tu dong giai phong cong 8787 neu co tien trinh cu dang chiem giu
python -c "import socket, subprocess, sys; s = socket.socket(); err = s.connect_ex(('127.0.0.1', 8787)); s.close(); sys.exit(0) if err != 0 else None; out = subprocess.run(['netstat', '-ano'], capture_output=True, text=True).stdout; pids = [l.strip().split()[-1] for l in out.splitlines() if ':8787' in l and 'LISTENING' in l]; [subprocess.run(['taskkill', '/F', '/PID', p], capture_output=True) for p in pids]" >nul 2>nul

REM 4. Thong bao ro rang va chay Control Plane
cls
echo ======================================================================
echo    PYTUNNEL STUDIO v5.3 - TRUNG TAM QUAN TRI DUONG HAM LOCALHOST
echo ======================================================================
echo.
echo   [OK] He thong:          Dang hoat dong on dinh
echo   [OK] Dia chi Dashboard:  http://127.0.0.1:8787
echo   [OK] Tu dong diet rac:   Win32 Job Object da kich hoat
echo.
echo ----------------------------------------------------------------------
echo   HUONG DAN SU DUNG:
echo   1. Giao dien web da duoc tu dong mo tren trinh duyet cua ban.
echo   2. Ban co the THU NHO cua so CMD nay de lam viec, choi game, xem video.
echo   3. DE TAT UNG DUNG:
echo      - Bam nut [Thoat] mau do tren web (cua so nay se tu dong dong)
echo      - Hoac nhan to hop phim Ctrl + C tai cua so nay.
echo ======================================================================
echo.
echo [DANG CHAY NEN] He thong san sang tiep nhan yeu cau tu trinh duyet...
echo.

python -m uvicorn backend.main:app --host 127.0.0.1 --port 8787 --log-level warning --no-access-log

echo.
echo [THONG BAO] He thong da tat an toan. Dang dong cua so CMD...
timeout /t 1 /nobreak >nul 2>nul
exit
