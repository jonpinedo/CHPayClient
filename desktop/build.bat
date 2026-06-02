@echo off
setlocal

:: ── Versión de la aplicación ──────────────────────────────────────────────────
set VERSION=1.0.3
set VERSION_CODE=4

echo [CHPay] Building CHPay Desktop v%VERSION% (code: %VERSION_CODE%)
echo.

:: ── Configurar TDM-GCC-64 ─────────────────────────────────────────────────────
set PATH=C:\TDM-GCC-64\bin;%PATH%
set CC=C:\TDM-GCC-64\bin\gcc.exe
set CGO_ENABLED=1

:: ── Build ─────────────────────────────────────────────────────────────────────
cd /d "%~dp0"
echo [CHPay] Compilando chpay.exe...
set LDFLAGS=-H=windowsgui -X main.AppVersion=%VERSION% -X main.AppVersionCode=%VERSION_CODE%
go build -ldflags "%LDFLAGS%" -o chpay.exe .
if errorlevel 1 (
    echo [ERROR] La compilacion fallo.
    exit /b 1
)

echo.
echo [CHPay] chpay.exe v%VERSION% generado correctamente.
