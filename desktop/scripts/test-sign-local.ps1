# CHPay Desktop - Prueba local de build + firma (sin publicar al servidor)
# Uso: cd desktop ; .\scripts\test-sign-local.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$desktopDir = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $desktopDir -Parent
Set-Location $desktopDir

$secretsFile = Join-Path $repoRoot "secrets.local.ps1"
if (Test-Path $secretsFile) { . $secretsFile }

Write-Host "=== CHPay - prueba local build + firma ===" -ForegroundColor Cyan
Write-Host ""

$cerPath = Join-Path $desktopDir "certs\chpay-signing.cer"
if (-not (Test-Path $cerPath) -or (Get-Item $cerPath).Length -lt 10) {
    Write-Error "Falta certs\chpay-signing.cer. Ejecuta scripts\create-signing-cert.ps1"
}
$cerSize = (Get-Item $cerPath).Length
Write-Host "[OK] chpay-signing.cer presente - $cerSize bytes" -ForegroundColor Green

if (-not $env:CHPAY_SIGN_PFX -or -not (Test-Path $env:CHPAY_SIGN_PFX)) {
    Write-Error "CHPAY_SIGN_PFX no configurado. Anade la ruta del .pfx en secrets.local.ps1"
}
if (-not $env:CHPAY_SIGN_PFX_PASS) {
    Write-Error "CHPAY_SIGN_PFX_PASS no configurado en secrets.local.ps1"
}
Write-Host "[OK] PFX configurado en secrets.local.ps1" -ForegroundColor Green

Write-Host ""
Write-Host "Compilando..." -ForegroundColor Cyan
& .\build.bat
if ($LASTEXITCODE -ne 0) { throw "build.bat fallo" }
Write-Host "[OK] build.bat" -ForegroundColor Green

Write-Host ""
& "$PSScriptRoot\sign-exe.ps1" -ExePath ".\chpay.exe"
Write-Host "[OK] Firma Authenticode" -ForegroundColor Green

$sig = Get-AuthenticodeSignature ".\chpay.exe"
Write-Host ""
Write-Host "Estado firma: $($sig.Status)" -ForegroundColor $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Yellow' })
Write-Host "  Firmante:   $($sig.SignerCertificate.Subject)"
Write-Host "  Thumbprint: $($sig.SignerCertificate.Thumbprint)"

$cerObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cerPath)
if ($sig.SignerCertificate.Thumbprint -ne $cerObj.Thumbprint) {
    Write-Warning "El thumbprint del exe firmado no coincide con chpay-signing.cer. Recompila tras regenerar el certificado."
} else {
    Write-Host "[OK] Thumbprint exe = .cer embebido" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Prueba manual en este PC ===" -ForegroundColor Cyan
Write-Host "  1. Ejecuta .\chpay.exe"
Write-Host "  2. Dialogo Certificado de confianza + UAC (primera vez)"
Write-Host "  3. Tras aceptar, la app arranca"
Write-Host "  4. Cierra y vuelve a abrir: no debe pedir UAC otra vez"
Write-Host ""
Write-Host "Comprobar cert en Root:" -ForegroundColor Gray
Write-Host "  Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*CHPay*'"
Write-Host ""
Write-Host "Si todo OK: .\publish_desktop.ps1 -Changelog 'texto'" -ForegroundColor Green
