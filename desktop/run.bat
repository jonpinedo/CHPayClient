@echo off
echo [CHPay] Construyendo...
call "%~dp0build.bat"
if errorlevel 1 exit /b 1

echo [CHPay] Iniciando CHPay Desktop...
cd /d "%~dp0"
start "" chpay.exe
