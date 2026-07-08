# ─────────────────────────────────────────────────────────────────────────────
# CHPay Desktop — Firmar chpay.exe con Authenticode
# ─────────────────────────────────────────────────────────────────────────────
# Uso: .\sign-exe.ps1 [-ExePath .\chpay.exe]
# Requiere CHPAY_SIGN_PFX y CHPAY_SIGN_PFX_PASS (secrets.local.ps1 o entorno)
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$ExePath = ".\chpay.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Cargar secretos si faltan
if (-not $env:CHPAY_SIGN_PFX) {
    $secretsFile = Join-Path (Split-Path $PSScriptRoot -Parent) "..\secrets.local.ps1"
    if (Test-Path $secretsFile) { . $secretsFile }
}

if (-not $env:CHPAY_SIGN_PFX -or -not (Test-Path $env:CHPAY_SIGN_PFX)) {
    Write-Error "CHPAY_SIGN_PFX no definido o no encontrado. Ejecuta create-signing-cert.ps1 y configura secrets.local.ps1"
}
if (-not $env:CHPAY_SIGN_PFX_PASS) {
    Write-Error "CHPAY_SIGN_PFX_PASS no definido en secrets.local.ps1"
}
if (-not (Test-Path $ExePath)) {
    Write-Error "EXE no encontrado: $ExePath"
}

function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $kitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $kitsRoot) {
        $candidates = Get-ChildItem -Path $kitsRoot -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
            Sort-Object FullName -Descending
        if ($candidates) { return $candidates[0].FullName }
    }

    $vsKits = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($vsKits) { return $vsKits.FullName }

    throw @"
signtool.exe no encontrado. Instala Windows SDK (Signing Tools for Desktop Apps):
  winget install --id Microsoft.WindowsSDK.10.0.22621 -e
  o desde Visual Studio Installer: Windows SDK + Windows SDK Signing Tools
"@
}

$signtool = Find-SignTool
Write-Host "Firmando $ExePath..." -ForegroundColor Cyan
Write-Host "  signtool: $signtool" -ForegroundColor Gray

& $signtool sign /fd SHA256 /f $env:CHPAY_SIGN_PFX /p $env:CHPAY_SIGN_PFX_PASS `
    /tr http://timestamp.digicert.com /td SHA256 `
    /d "CHPay Desktop" $ExePath
if ($LASTEXITCODE -ne 0) { throw "signtool sign fallo (exit $LASTEXITCODE)" }

# Con certificado autofirmado, verify /pa falla hasta que el .cer este en Root del TPV.
# Comprobamos que la firma existe e integridad OK (Status Valid o UnknownError = firmado).
$auth = Get-AuthenticodeSignature $ExePath
if ($auth.Status -eq 'NotSigned') {
    throw "El exe no tiene firma Authenticode tras sign"
}
if ($auth.SignerCertificate.Subject -notlike '*CHPay Desktop*') {
    throw "Firmante inesperado: $($auth.SignerCertificate.Subject)"
}

Write-Host "Verificacion: $($auth.Status) - $($auth.SignerCertificate.Subject)" -ForegroundColor Green
Write-Host "  (En TPV sin cert en Root, signtool verify /pa fallara hasta la 1ª ejecucion con UAC)" -ForegroundColor Gray

Write-Host "EXE firmado correctamente." -ForegroundColor Green
