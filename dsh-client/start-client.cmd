@echo off
rem dsh-client 启动器：静默启动（无 PowerShell 窗口闪现）
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0client.ps1"
