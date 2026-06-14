@echo off
:: =======================================================
:: LAUNCHER TUNNEL CLOUDFLARE (RUN AS ADMINISTRATOR)
:: =======================================================

echo Memeriksa hak akses Administrator...
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Dijalankan sebagai Administrator.
) else (
    echo [INFO] Meminta hak akses Administrator...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo.
echo =======================================================
echo   MEMULAI SETUP CLOUDFLARE TUNNEL
echo =======================================================
echo.

:: Menjalankan skrip PowerShell
powershell -ExecutionPolicy Bypass -File "%~dp0tunnel.ps1"

echo.
echo Jika ada error, pastikan file .env sudah dikonfigurasi dengan benar.
pause
