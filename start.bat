@echo off
set CLEAN_HOST=127.0.0.1
set CLEAN_PORT=8000
set CLEAN_TOKEN=2308788
set CLEAN_OPEN_FOLDER=0
echo ========================================
echo   Cleaner Server - http://127.0.0.1:8000
echo   Token: 2308788
echo ========================================
cd /d %TEMP%\cleanup-assistant
"C:\Users\whb\AppData\Local\Programs\Python\Python313\python.exe" server.py
pause
