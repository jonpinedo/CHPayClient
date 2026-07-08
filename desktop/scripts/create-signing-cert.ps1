# ─────────────────────────────────────────────────────────────────────────────
# CHPay Desktop — Crear certificado de firma de código (autofirmado)
# ─────────────────────────────────────────────────────────────────────────────
# Uso: .\create-signing-cert.ps1 [-PfxPassword "contraseña"]
#
# Genera:
#   desktop/certs/chpay-signing.cer  (público, versionar en git)
#   desktop/certs/chpay-signing.pfx  (privado, NO versionar)
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$PfxPassword = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$certDir = Join-Path $PSScriptRoot "..\certs"
New-Item -ItemType Directory -Force -Path $certDir | Out-Null

$cerPath = Join-Path $certDir "chpay-signing.cer"
$pfxPath = Join-Path $certDir "chpay-signing.pfx"

Write-Host "Creando certificado de firma de codigo..." -ForegroundColor Cyan

$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=CHPay Desktop, O=CHPay" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(5) `
    -KeyExportPolicy Exportable

Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
Write-Host "  .cer -> $cerPath" -ForegroundColor Green

if (-not $PfxPassword) {
    $secure = Read-Host "Contrasena para el .pfx" -AsSecureString
} else {
    $secure = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
}
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secure -Force | Out-Null
Write-Host "  .pfx -> $pfxPath (NO versionar)" -ForegroundColor Green

Write-Host ""
Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Anade a secrets.local.ps1 (raiz del repo):" -ForegroundColor Cyan
Write-Host "  `$env:CHPAY_SIGN_PFX = '$pfxPath'"
Write-Host "  `$env:CHPAY_SIGN_PFX_PASS = 'tu-contrasena'"
