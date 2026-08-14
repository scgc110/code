@echo off
rem start-dsh-web.cmd - launch dsh web, redirect output to dsh-web.boot.log
"%APPDATA%\npm\dsh.cmd" web >> "%~dp0dsh-web.boot.log" 2>&1