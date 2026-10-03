@echo off
rem Creates or updates the AutoFlow flows in the local Windmill over its API.
rem Idempotent - run it again after editing flow\*.py or provision.py.
rem Auth: set WM_TOKEN=<token from Account settings -> Tokens>  first
rem (or set WM_PASSWORD=yourpassword if you changed the admin password).
setlocal
set "ROOT=%~dp0.."
if not defined WM_BASE set "WM_BASE=http://127.0.0.1:8000"
"C:\Users\kamal\tools\python\python.exe" "%ROOT%\provision.py"
echo.
pause
