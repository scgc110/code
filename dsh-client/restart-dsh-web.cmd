@echo off
rem restart-dsh-web.cmd - wrapper for restart-dsh-web.ps1 (keeps window open)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-dsh-web.ps1"
echo.
pause