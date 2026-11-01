@echo off
title COM7 UART monitor - 115200 8N1
cd /d "%~dp0"
echo Reading COM7 for 120 seconds.
echo Press Ctrl+C to stop. Logs are saved in hardware_results.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0read_status.ps1" -PortName COM7 -Seconds 120 -WarmupSeconds 0
echo.
echo Reading finished or the port could not be opened.
pause
