@echo off
rem Creates or updates the AutoFlow flows in the local Windmill over its API.
rem Idempotent - run it again after editing flow\*.py or provision.py.
rem If you changed the admin password:  set WM_PASSWORD=yourpassword  first.
setlocal
set "ROOT=%~dp0.."
if not defined WM_BASE set "WM_BASE=http://127.0.0.1:8000"
"C:\Users\kamal\tools\python\python.exe" "%ROOT%\provision.py"
echo.
pause
