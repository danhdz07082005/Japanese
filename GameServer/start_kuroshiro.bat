@echo off
title Kuroshiro Kanji-Romaji Translator (:8081)
chcp 65001 >nul
cd /d "%~dp0kuroshiro-service"

echo ======================================================================
echo    KUROSHIRO MICROSERVICE - DICH KANJI/KANA SANG ROMAJI (PORT 8081)
echo ======================================================================
echo.

where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] LOI: Khong tim thay Node.js tren may cua ban!
    echo     Vui long cai dat Node.js tu: https://nodejs.org
    echo.
    pause
    exit /b 1
)

if not exist "node_modules\kuroshiro" (
    echo [1/2] Dang cai dat thu vien Kuroshiro lan dau...
    npm install --no-audit --no-fund
)

echo [2/2] Dang khoi dong Kuroshiro dich thuat tren http://127.0.0.1:8081...
echo.
node server.js
if %errorlevel% neq 0 (
    echo.
    echo [!] Kuroshiro service bi dung dot ngot voi ma loi: %errorlevel%
    pause
)
