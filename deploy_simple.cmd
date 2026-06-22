@echo off
cd /d "%~dp0"
echo.
echo Running simple Quick Quote deploy (Function + APIM)...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0deploy_simple.ps1" %*
pause
