@echo off
setlocal

:: ── Versión de la aplicación ──────────────────────────────────────────────────
set VERSION=1.2.6
set VERSION_CODE=13

echo [CHPay] Building CHPay Desktop v%VERSION% (code: %VERSION_CODE%)
echo.

:: ── Configurar TDM-GCC-64 y Go ────────────────────────────────────────────────
set PATH=C:\TDM-GCC-64\bin;C:\Program Files\Go\bin;%PATH%
set CC=C:\TDM-GCC-64\bin\gcc.exe
set CGO_ENABLED=1
:: Go 1.26 + TDM-GCC genera .exe inválidos; usar toolchain 1.22.x compatible con CGO.
set GOTOOLCHAIN=go1.22.12

:: ── Build ─────────────────────────────────────────────────────────────────────
cd /d "%~dp0"
echo [CHPay] Compilando chpay.exe...
set LDFLAGS=-H=windowsgui -X main.AppVersion=%VERSION% -X main.AppVersionCode=%VERSION_CODE%
go build -buildvcs=false -ldflags "%LDFLAGS%" -o chpay.exe .
if errorlevel 1 (
    echo [ERROR] La compilacion fallo.
    exit /b 1
)

echo.
echo [CHPay] chpay.exe v%VERSION% generado correctamente.
