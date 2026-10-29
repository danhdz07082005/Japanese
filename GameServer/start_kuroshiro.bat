@echo off
echo Starting Kuroshiro Microservice on http://localhost:8081...
cd /d "%~dp0kuroshiro-service"
node server.js
pause
