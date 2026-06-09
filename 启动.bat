@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
cd /d "%~dp0"

:: 优先使用 PATH 中的 python，否则用本地安装路径
set PYTHON_CMD=python
%PYTHON_CMD% --version >nul 2>&1
if errorlevel 1 (
    set "PYTHON_CMD=C:\Users\whb\AppData\Local\Programs\Python\Python315\python.exe"
    if not exist "!PYTHON_CMD!" (
        echo [ERROR] Python not found. Please install Python 3.8+
        pause
        exit /b 1
    )
)

echo ============================
echo   驷马C盘清理助手 v4.2
echo   http://localhost:5050
echo ============================

!PYTHON_CMD! -c "import flask" >nul 2>&1
if errorlevel 1 (
    echo Installing Flask...
    !PYTHON_CMD! -m pip install flask >nul 2>&1
)
echo Starting server...
timeout /t 2 /nobreak >nul
start http://localhost:5050
!PYTHON_CMD! server.py
pause

