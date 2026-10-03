@echo off
rem Opens the Windmill UI (http://localhost:8000) - target of the "Windmill" desktop icon.
rem Windmill runs in Docker inside WSL Ubuntu. If it is not answering, this wakes WSL,
rem waits for the Docker daemon, starts the compose stack and waits for the API
rem before opening the browser. If it is already up, it just opens the browser.
rem Either way it first makes sure the hidden keep-alive session is running: without
rem it WSL stops Ubuntu ~20 s after this window closes and Windmill goes down again.
setlocal
set "URL=http://localhost:8000"
title Windmill

wscript.exe //nologo "%~dp0keep-wsl-alive.vbs"

curl.exe -s -m 3 -o nul "%URL%/api/version" && goto open

echo Starting Windmill in WSL Ubuntu (the first start after a reboot can take a minute)...
wsl.exe -d Ubuntu -u root -e sh -c "for i in $(seq 60); do docker info >/dev/null 2>&1 && break; sleep 1; done; cd /mnt/d/AutoFlow && docker compose up -d"
if errorlevel 1 (
  echo.
  echo Could not start the Docker stack in WSL Ubuntu - see the message above.
  pause
  exit /b 1
)

set /a TRIES=0
:wait
curl.exe -s -m 3 -o nul "%URL%/api/version" && goto open
set /a TRIES+=1
if %TRIES% geq 60 (
  echo.
  echo Windmill did not answer within 3 minutes. Server logs:
  echo   wsl -d Ubuntu -u root -e sh -c "cd /mnt/d/AutoFlow && docker compose logs --tail 50 windmill_server"
  pause
  exit /b 1
)
timeout /t 3 /nobreak >nul
goto wait

:open
start "" "%URL%"
