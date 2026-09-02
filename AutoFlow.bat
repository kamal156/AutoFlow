@echo off
rem AutoFlow launcher - the desktop icon points here.
rem Starts local PostgreSQL if needed, starts Windmill (server + worker in one
rem process, bound to 127.0.0.1 only), provisions the AutoFlow flows over the
rem API (idempotent) and opens the Windmill UI in the browser.
rem Everything runs on this machine; nothing is exposed to the network.
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "WM=%ROOT%\windmill"
set "PGDIR=D:\PostgresLocal"
set "WM_URL=http://127.0.0.1:8000"
set "PY=C:\Users\kamal\tools\python\python.exe"
title AutoFlow

rem ---- 1. PostgreSQL (shared with the NEPSE database) -----------------------
"%PGDIR%\pgsql\bin\pg_ctl.exe" -D "%PGDIR%\data" status >nul 2>&1
if errorlevel 1 (
  echo Starting PostgreSQL...
  "%PGDIR%\pgsql\bin\pg_ctl.exe" -D "%PGDIR%\data" -l "%PGDIR%\logs\postgres.log" -w start
  if errorlevel 1 (
    echo PostgreSQL failed to start. See %PGDIR%\logs\postgres.log
    pause
    exit /b 1
  )
)

rem ---- 2. first run: fetch Windmill, PowerShell 7 and uv ---------------------
if not exist "%WM%\windmill-ee.exe" (
  echo Windmill is not installed yet. Running one-time setup ^(about 600 MB of downloads^)...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\setup-windmill.ps1"
  if errorlevel 1 (
    echo.
    echo Setup failed. Fix the problem above and double-click AutoFlow again.
    pause
    exit /b 1
  )
)
if not exist "%ROOT%\tools\uv\uv.exe" (
  echo uv is missing. Running setup to fetch it...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\setup-windmill.ps1"
)

rem ---- 3. Windmill (skip if it is already up) --------------------------------
curl.exe -s -o nul "%WM_URL%/api/version" && goto provision

set /p PGPASSWORD=<"%PGDIR%\.pgpassword"
set "MODE=standalone"
set "DATABASE_URL=postgres://postgres:%PGPASSWORD%@localhost:5432/windmill?sslmode=disable"
set "BASE_URL=http://localhost:8000"
set "PORT=8000"
set "SERVER_BIND_ADDR=127.0.0.1"
set "NUM_WORKERS=1"
set "WORKER_GROUP=default"
set "POWERSHELL_PATH=%ROOT%\tools\pwsh\pwsh.exe"
rem Python steps (the flow\*.py scripts) run with the portable CPython; uv
rem installs their dependencies (feedparser, requests, wmill) into the cache.
set "PYTHON_PATH=%PY%"
set "UV_PATH=%ROOT%\tools\uv\uv.exe"
rem Keep job scratch space off the nearly-full C: drive.
set "TMP=%WM%\tmp"
set "TEMP=%WM%\tmp"
rem Tools the AutoFlow steps call from inside Windmill jobs.
set "PATH=%ROOT%\tools\pwsh;%ROOT%\tools\uv;%ROOT%\npm-global;C:\Users\kamal\tools\node;C:\Users\kamal\tools\ffmpeg\bin;C:\Users\kamal\tools\python;%PGDIR%\pgsql\bin;%PATH%"
if not exist "%WM%\tmp" mkdir "%WM%\tmp"
if not exist "%WM%\logs" mkdir "%WM%\logs"

echo Starting Windmill...
cd /d "%WM%"
start "AutoFlow - Windmill" /min cmd /c ""%WM%\windmill-ee.exe" >> "%WM%\logs\windmill.log" 2>&1"

rem First start runs database migrations, which can take a few minutes.
rem (ping is used as a 1 s sleep because timeout.exe refuses to run without a console stdin.)
set /a tries=0
:wait
set /a tries+=1
curl.exe -s -o nul "%WM_URL%/api/version" && goto provision
tasklist /FI "IMAGENAME eq windmill-ee.exe" 2>nul | find /I "windmill-ee.exe" >nul
if errorlevel 1 (
  echo Windmill exited before it came up. Last lines of the log:
  powershell -NoProfile -Command "Get-Content -Tail 25 '%WM%\logs\windmill.log'"
  pause
  exit /b 1
)
if %tries% geq 300 (
  echo Windmill did not answer within 5 minutes. See %WM%\logs\windmill.log
  pause
  exit /b 1
)
if %tries%==1 echo   waiting for %WM_URL% ...
ping -n 2 127.0.0.1 >nul
goto wait

rem ---- 4. flows: create/update over the API (safe to repeat) -----------------
:provision
echo Provisioning AutoFlow flows in Windmill...
set "WM_BASE=%WM_URL%"
"%PY%" "%ROOT%\provision.py"
if errorlevel 1 (
  echo.
  echo Flow provisioning did not complete - see the message above.
  echo If you changed the Windmill admin password, run scripts\provision.bat
  echo with WM_PASSWORD set. Windmill itself is still running.
  echo.
)

rem ---- 5. open the UI ---------------------------------------------------------
start "" "http://localhost:8000"
echo AutoFlow is running at http://localhost:8000
echo First login: admin@windmill.dev / changeme  (change it after signing in)
ping -n 7 127.0.0.1 >nul
exit /b 0
