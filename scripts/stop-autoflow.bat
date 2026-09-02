@echo off
rem Stops Windmill. PostgreSQL is left running because the NEPSE database
rem shares it; use D:\PostgresLocal\scripts\stop-db.bat for that.
taskkill /IM windmill-ee.exe /F >nul 2>&1 && echo Windmill stopped. || echo Windmill was not running.
timeout /t 2 >nul
