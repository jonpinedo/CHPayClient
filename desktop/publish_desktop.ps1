# ─────────────────────────────────────────────────────────────────────────────
# CHPay Desktop — Publicar nueva versión
# ─────────────────────────────────────────────────────────────────────────────
# Uso: .\publish_desktop.ps1 [-Mandatory] [-Changelog "Descripción"]
#
# Requisitos:
#   - Go y GCC configurados
#   - $env:CHPAY_PUBLISH_KEY definido con el API key del servidor
# ─────────────────────────────────────────────────────────────────────────────

param(
    [switch]$Mandatory,
    [string]$Changelog = "",
    [string]$ApiKey = $env:CHPAY_PUBLISH_KEY,
    [string]$ServerUrl = "http://192.168.1.144:8080/api/update/publish"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Leer versión del build.bat ───────────────────────────────────────────────
$buildBat = Get-Content ".\build.bat" -Raw
if ($buildBat -notmatch 'set VERSION=(\d+\.\d+\.\d+)') {
    Write-Error "No se encontró 'set VERSION=X.Y.Z' en build.bat"
    exit 1
}
$Version = $Matches[1]

if ($buildBat -notmatch 'set VERSION_CODE=(\d+)') {
    Write-Error "No se encontró 'set VERSION_CODE=N' en build.bat"
    exit 1
}
$VersionCode = [int]$Matches[1]

Write-Host "Versión: $Version ($VersionCode)" -ForegroundColor Cyan

# ─── Build ────────────────────────────────────────────────────────────────────
Write-Host "`nBuilding chpay.exe..." -ForegroundColor Cyan
& .\build.bat
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build falló"
    exit 1
}

$ExePath = ".\chpay.exe"
if (-not (Test-Path $ExePath)) {
    Write-Error "EXE no encontrado: $ExePath"
    exit 1
}

$ExeSize = (Get-Item $ExePath).Length / 1MB
Write-Host "EXE generado: $([Math]::Round($ExeSize, 1)) MB" -ForegroundColor Green

# ─── Publicar al servidor ─────────────────────────────────────────────────────
if (-not $ApiKey) {
    Write-Warning "CHPAY_PUBLISH_KEY no definido. No se publicará al servidor."
    Write-Host "`nPara publicar, define la variable de entorno:"
    Write-Host '  $env:CHPAY_PUBLISH_KEY = "tu-api-key"' -ForegroundColor Yellow
    exit 0
}

Write-Host "`nPublicando al servidor..." -ForegroundColor Cyan

try {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Add("Authorization", "Bearer $ApiKey")

    $form = New-Object System.Net.Http.MultipartFormDataContent
    $form.Add((New-Object System.Net.Http.StringContent("desktop")), "platform")
    $form.Add((New-Object System.Net.Http.StringContent([string]$VersionCode)), "versionCode")
    $form.Add((New-Object System.Net.Http.StringContent($Version)), "versionName")
    $form.Add((New-Object System.Net.Http.StringContent($(if ($Mandatory) { "true" } else { "false" }))), "mandatory")
    $form.Add((New-Object System.Net.Http.StringContent($Changelog)), "changelog")

    $fileStream = [System.IO.File]::OpenRead((Resolve-Path $ExePath).Path)
    $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
    $form.Add($fileContent, "exe", "chpay.exe")

    $task = $client.PostAsync($ServerUrl, $form)
    $task.Wait()
    $resp = $task.Result
    $bodyTask = $resp.Content.ReadAsStringAsync()
    $bodyTask.Wait()
    $fileStream.Close()

    if ($resp.IsSuccessStatusCode) {
        $json = $bodyTask.Result | ConvertFrom-Json
        Write-Host $json.message -ForegroundColor Green
    } else {
        Write-Warning "Error del servidor ($($resp.StatusCode)): $($bodyTask.Result)"
    }
} catch {
    Write-Warning "Error publicando: $_"
    Write-Host "El EXE está listo localmente. Puedes subirlo manualmente." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n✅ CHPay Desktop v$Version ($VersionCode) publicado correctamente." -ForegroundColor Green
