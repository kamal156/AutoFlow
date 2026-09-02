<#
.SYNOPSIS
  One-time setup for the local Windmill host that runs AutoFlow.

.DESCRIPTION
  Downloads the native Windows Windmill binary and a portable PowerShell 7 (the
  Windmill Windows worker needs pwsh.exe to run PowerShell steps) and a portable
  uv (Windmill installs Python step dependencies with it), then makes sure the
  `windmill` database exists on the local PostgreSQL server.

  No admin rights are needed: everything lands inside the AutoFlow folder on D:.
  Idempotent - re-running skips anything already in place.

  Sources (official release pages):
    https://github.com/windmill-labs/windmill/releases   (windmill-ee.exe, ~1.9 GB)
    https://github.com/PowerShell/PowerShell/releases    (PowerShell-*-win-x64.zip, ~106 MB)
    https://github.com/astral-sh/uv/releases             (uv-x86_64-pc-windows-msvc.zip, ~20 MB)
#>
[CmdletBinding()]
param(
    # Windmill release tag to fetch.
    [string]$WindmillVersion = 'v1.801.0',
    # PowerShell release to fetch.
    [string]$PwshVersion = '7.6.5',
    # uv release to fetch (Python package installer used by the Windmill worker).
    [string]$UvVersion = '0.12.9'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root    = Split-Path -Parent $PSScriptRoot
$wmDir   = Join-Path $root 'windmill'
$pwshDir = Join-Path $root 'tools\pwsh'
$pgDir   = 'D:\PostgresLocal'
$curl    = Join-Path $env:SystemRoot 'System32\curl.exe'

New-Item -ItemType Directory -Force -Path $wmDir, (Join-Path $wmDir 'logs'), (Join-Path $wmDir 'tmp'), (Join-Path $root 'tools') | Out-Null

function Get-File([string]$Url, [string]$Dest) {
    Write-Host "Downloading $Url" -ForegroundColor Cyan
    Write-Host "        to $Dest"
    $tmp = "$Dest.part"
    # curl.exe handles multi-GB downloads with a progress bar and resumes on retry.
    & $curl -L --fail --retry 5 --retry-delay 5 -C - -o $tmp $Url
    if ($LASTEXITCODE -ne 0) { throw "download failed (curl exit $LASTEXITCODE): $Url" }
    Move-Item -Force $tmp $Dest
}

# --- Windmill binary --------------------------------------------------------
$wmExe = Join-Path $wmDir 'windmill-ee.exe'
if (Test-Path $wmExe) {
    Write-Host "Windmill already present: $wmExe" -ForegroundColor Green
} else {
    $free = (Get-PSDrive -Name D).Free
    if ($free -lt 4GB) { throw "D: has less than 4 GB free; Windmill needs ~2 GB plus scratch space." }
    Get-File "https://github.com/windmill-labs/windmill/releases/download/$WindmillVersion/windmill-ee.exe" $wmExe
}
$ver = & $wmExe version 2>&1 | Select-Object -First 1
Write-Host "Windmill: $ver" -ForegroundColor Green

# --- Portable PowerShell 7 --------------------------------------------------
$pwshExe = Join-Path $pwshDir 'pwsh.exe'
if (Test-Path $pwshExe) {
    Write-Host "PowerShell 7 already present: $pwshExe" -ForegroundColor Green
} else {
    $zip = Join-Path $root "tools\PowerShell-$PwshVersion-win-x64.zip"
    Get-File "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-x64.zip" $zip
    Write-Host "Extracting to $pwshDir"
    Expand-Archive -Path $zip -DestinationPath $pwshDir -Force
    Remove-Item $zip
}
$pwshVer = & $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
Write-Host "PowerShell: $pwshVer" -ForegroundColor Green

# --- uv (installs Python step dependencies for the Windmill worker) ---------
$uvDir = Join-Path $root 'tools\uv'
$uvExe = Join-Path $uvDir 'uv.exe'
if (Test-Path $uvExe) {
    Write-Host "uv already present: $uvExe" -ForegroundColor Green
} else {
    $zip = Join-Path $root "tools\uv-$UvVersion-win-x64.zip"
    Get-File "https://github.com/astral-sh/uv/releases/download/$UvVersion/uv-x86_64-pc-windows-msvc.zip" $zip
    Write-Host "Extracting to $uvDir"
    Expand-Archive -Path $zip -DestinationPath $uvDir -Force
    Remove-Item $zip
}
$uvVer = & $uvExe --version 2>&1 | Select-Object -First 1
Write-Host "uv: $uvVer" -ForegroundColor Green

# --- Database ---------------------------------------------------------------
$pgCtl = Join-Path $pgDir 'pgsql\bin\pg_ctl.exe'
$psql  = Join-Path $pgDir 'pgsql\bin\psql.exe'
if (-not (Test-Path $psql)) { throw "Local PostgreSQL not found at $pgDir" }
& $pgCtl -D (Join-Path $pgDir 'data') status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Starting PostgreSQL..."
    & $pgCtl -D (Join-Path $pgDir 'data') -l (Join-Path $pgDir 'logs\postgres.log') -w start | Out-Null
}
$env:PGPASSWORD = (Get-Content (Join-Path $pgDir '.pgpassword') -Raw).Trim()
$exists = & $psql -h localhost -U postgres -d postgres -tAc "select 1 from pg_database where datname='windmill'"
if ("$exists".Trim() -ne '1') {
    & $psql -h localhost -U postgres -d postgres -c 'CREATE DATABASE windmill' | Out-Null
    Write-Host "Created database 'windmill'." -ForegroundColor Green
} else {
    Write-Host "Database 'windmill' already exists." -ForegroundColor Green
}
Remove-Item Env:\PGPASSWORD

Write-Host ""
Write-Host "Setup complete. Double-click the AutoFlow desktop icon (or AutoFlow.bat) to start." -ForegroundColor Green
exit 0
