@echo off
echo ========================================================
echo Starting Japanese Mastery .NET Backend + Kuroshiro Microservice
echo ========================================================

start "Kuroshiro Microservice (Port 8081)" cmd /k "cd /d %~dp0kuroshiro-service && node server.js"

echo Waiting for Kuroshiro to initialize...
timeout /t 3 /nobreak >nul

echo Starting ASP.NET Core Backend on http://localhost:8080...
cd /d "%~dp0"
dotnet run
pause