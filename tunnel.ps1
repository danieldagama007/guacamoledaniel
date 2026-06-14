<#
.SYNOPSIS
Cloudflare Tunnel - Open API Uploader (Windows Version)

.DESCRIPTION
Script ini digunakan untuk mengotomatisasi instalasi dan konfigurasi Cloudflared Tunnel di Windows.

.EXAMPLE
.\tunnel.ps1 -Domain api.danquere.cloud -Port 7860
#>

param (
    [string]$Domain = "",
    [string]$Port = ""
)

# -------------------------------------------------------
# CEK ADMINISTRATOR
# -------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Script ini harus dijalankan sebagai Administrator (Run as Administrator)!" -ForegroundColor Red
    Exit
}

# -------------------------------------------------------
# BACA KONFIGURASI
# -------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$EnvFile = Join-Path $ScriptDir ".env"

if ($Domain -eq "" -or $Port -eq "") {
    if (Test-Path $EnvFile) {
        $EnvContent = Get-Content $EnvFile
        foreach ($line in $EnvContent) {
            if ($line -match "^TUNNEL_DOMAIN\s*=\s*(.*)") {
                $Domain = $matches[1] -replace "['`"]", "" -replace "\s", ""
            }
            if ($line -match "^PORT\s*=\s*(.*)") {
                $Port = $matches[1] -replace "['`"]", "" -replace "\s", ""
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Domain) -or [string]::IsNullOrWhiteSpace($Port)) {
    Write-Host "[ERROR] Domain dan Port belum ditentukan!" -ForegroundColor Red
    Write-Host "Gunakan: .\tunnel.ps1 -Domain subdomain.domain.com -Port 7860" -ForegroundColor Yellow
    Write-Host "Atau buat file .env dengan TUNNEL_DOMAIN dan PORT di direktori yang sama." -ForegroundColor Yellow
    Exit
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Cloudflared Tunnel - Windows Version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Domain : $Domain" -ForegroundColor Green
Write-Host "  Port   : $Port" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Start-Sleep -Seconds 1

# -------------------------------------------------------
# 1. INSTALL CLOUDFLARED
# -------------------------------------------------------
$CloudflaredPath = "$env:ProgramFiles\Cloudflared\cloudflared.exe"

if (Get-Command "cloudflared" -ErrorAction SilentlyContinue) {
    $Version = cloudflared --version
    Write-Host "[OK] Cloudflared sudah terinstall ($Version)" -ForegroundColor Green
} else {
    Write-Host "[INFO] Menginstall Cloudflared..." -ForegroundColor Cyan
    $DownloadUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    
    New-Item -ItemType Directory -Force -Path "$env:ProgramFiles\Cloudflared" | Out-Null
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $CloudflaredPath
    
    # Add to PATH temporarily and permanently
    $env:Path += ";$env:ProgramFiles\Cloudflared"
    [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::Machine)

    Write-Host "[OK] Cloudflared berhasil diinstall!" -ForegroundColor Green
}

$ConfigDir = "$env:USERPROFILE\.cloudflared"
$ConfigFile = Join-Path $ConfigDir "config.yml"
$CertFile = Join-Path $ConfigDir "cert.pem"

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
}

# -------------------------------------------------------
# 2. LOGIN KE CLOUDFLARE
# -------------------------------------------------------
if (Test-Path $CertFile) {
    Write-Host "[OK] Sudah login ke Cloudflare (cert.pem ditemukan)" -ForegroundColor Green
} else {
    Write-Host "[WARN] Pertama kali login - browser akan terbuka..." -ForegroundColor Yellow
    cloudflared login
    
    if (Test-Path $CertFile) {
        Write-Host "[OK] Login berhasil!" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Login gagal! cert.pem tidak ditemukan." -ForegroundColor Red
        Exit
    }
}

# -------------------------------------------------------
# 3. HENTIKAN SERVICE LAMA (JIKA ADA)
# -------------------------------------------------------
$Service = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
if ($Service) {
    Write-Host "[INFO] Menghentikan service cloudflared lama..." -ForegroundColor Cyan
    Stop-Service -Name "Cloudflared" -Force
    cloudflared service uninstall
    Write-Host "[OK] Service lama dihapus." -ForegroundColor Green
}

# -------------------------------------------------------
# 4. BUAT TUNNEL BARU
# -------------------------------------------------------
$TunnelTimestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$TunnelLabel = "auto-$TunnelTimestamp"

Write-Host "[INFO] Membuat tunnel baru: $TunnelLabel" -ForegroundColor Cyan

$TunnelOutput = cloudflared tunnel create $TunnelLabel 2>&1
$TunnelOutputString = $TunnelOutput | Out-String

$TunnelId = ""
if ($TunnelOutputString -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
    $TunnelId = $matches[1]
}

if ([string]::IsNullOrWhiteSpace($TunnelId)) {
    Write-Host "[ERROR] Gagal mendapatkan Tunnel ID!" -ForegroundColor Red
    Write-Host "Output: $TunnelOutputString" -ForegroundColor Yellow
    Exit
}

Write-Host "[OK] Tunnel berhasil dibuat:" -ForegroundColor Green
Write-Host "    Name : $TunnelLabel" -ForegroundColor Green
Write-Host "    ID   : $TunnelId" -ForegroundColor Green

# -------------------------------------------------------
# 5. BUAT CONFIG FILE
# -------------------------------------------------------
$CredFile = Join-Path $ConfigDir "$TunnelId.json"

Write-Host "[INFO] Membuat config.yml..." -ForegroundColor Cyan

$ConfigContent = @"
tunnel: $TunnelId
credentials-file: $CredFile

ingress:
  - hostname: $Domain
    service: http://127.0.0.1:$Port
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  - service: http_status:404
"@

$ConfigContent | Out-File -FilePath $ConfigFile -Encoding UTF8
Write-Host "[OK] Config tersimpan di $ConfigFile" -ForegroundColor Green

# -------------------------------------------------------
# 6. BUAT DNS CNAME
# -------------------------------------------------------
Write-Host "[INFO] Membuat DNS CNAME record..." -ForegroundColor Cyan
cloudflared tunnel route dns delete $Domain 2>$null
cloudflared tunnel route dns $TunnelId $Domain

Write-Host "[OK] DNS CNAME berhasil dibuat: $Domain -> $TunnelId.cfargotunnel.com" -ForegroundColor Green

# -------------------------------------------------------
# 7. INSTALL & START SYSTEM SERVICE
# -------------------------------------------------------
Write-Host "[INFO] Menginstall cloudflared sebagai Windows Service..." -ForegroundColor Cyan
cloudflared service install

Start-Service -Name "Cloudflared"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   ✅  Tunnel Berhasil Dibuat!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Domain  : https://$Domain" -ForegroundColor Cyan
Write-Host "  Port    : $Port" -ForegroundColor Cyan
Write-Host "  Tunnel  : $TunnelLabel" -ForegroundColor Cyan
Write-Host "  ID      : $TunnelId" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Gunakan 'Get-Service Cloudflared' untuk cek status service." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
