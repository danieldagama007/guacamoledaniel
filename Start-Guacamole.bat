@echo off
:: =======================================================
:: LAUNCHER GUACAMOLE (DOCKER)
:: =======================================================

echo Memeriksa apakah Docker terpasang...
docker -v >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Docker tidak ditemukan di sistem ini.
    echo Anda harus menginstall Docker Desktop terlebih dahulu untuk menjalankan Guacamole di Windows.
    echo Silakan unduh di: https://www.docker.com/products/docker-desktop
    pause
    exit /b
)

cd /d "%~dp0"

echo.
echo =======================================================
echo   MEMBANGUN DAN MENJALANKAN GUACAMOLE SERVER
echo =======================================================
echo.
echo Proses ini mungkin memakan waktu beberapa menit saat pertama kali dijalankan
echo karena sistem akan meng-compile kode UI Antrean yang baru kita buat.
echo.

docker-compose up -d --build

echo.
echo =======================================================
echo [OK] Guacamole Server berhasil dijalankan di background!
echo =======================================================
echo Anda sekarang bisa mengeksekusi Start-Tunnel.bat 
echo untuk membuka aksesnya ke publik via Cloudflare.
pause
