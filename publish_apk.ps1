# ─────────────────────────────────────────────────────────────────────
# CHPay — Publicar nueva versión del APK
# ─────────────────────────────────────────────────────────────────────
# Uso: .\publish_apk.ps1 [-Mandatory] [-Changelog "Descripción"]
#
# Requisitos:
#   - Flutter configurado en PATH
#   - Samba share \\truenas\compartido montado (o ajustar $SambaPath)
#   - $ApiToken: token de dispositivo con rol ADMIN
# ─────────────────────────────────────────────────────────────────────

param(
    [switch]$Mandatory,
    [string]$Changelog = "",
    [string]$ApiToken = $env:CHPAY_PUBLISH_KEY,
    [string]$ApiBase  = "http://192.168.1.144:8080/api/update",
    [string]$SambaPath = "\\truenas\compartido\apk-releases"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Leer versión actual del pubspec.yaml ─────────────────────────────
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -notmatch 'version:\s*([\d.]+)\+(\d+)') {
    Write-Error "No se encontró 'version: X.Y.Z+N' en pubspec.yaml"
    exit 1
}
$VersionName = $Matches[1]
$VersionCode = [int]$Matches[2]
Write-Host "Versión: $VersionName ($VersionCode)" -ForegroundColor Cyan

# ─── Build ─────────────────────────────────────────────────────────────
Write-Host "`nBuilding APK..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Write-Error "flutter build apk falló"; exit 1 }

$ApkSource = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $ApkSource)) {
    Write-Error "APK no encontrado en $ApkSource"
    exit 1
}

$ApkSize = (Get-Item $ApkSource).Length / 1MB
Write-Host "APK generado: $([Math]::Round($ApkSize, 1)) MB" -ForegroundColor Green

# ─── Copiar al Samba share ────────────────────────────────────────────
$ApkFilename = "chpay_v${VersionName}_${VersionCode}.apk"
$DestPath = Join-Path $SambaPath $ApkFilename

Write-Host "`nCopiando a $SambaPath..." -ForegroundColor Cyan
if (-not (Test-Path $SambaPath)) {
    Write-Error "Samba share no disponible: $SambaPath"
    exit 1
}
Copy-Item $ApkSource $DestPath -Force

# Actualizar symlink/copia chpay.apk (para URL pública fija)
$LatestPath = Join-Path $SambaPath "chpay.apk"
Copy-Item $ApkSource $LatestPath -Force
Write-Host "Copiado como chpay.apk (enlace de descarga fijo)" -ForegroundColor Green

# Notificar al servidor (registrar version)
if ($ApiToken) {
    Write-Host "`nRegistrando version en el servidor..." -ForegroundColor Cyan

    try {
        Add-Type -AssemblyName System.Net.Http
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Add("Authorization", "Bearer $ApiToken")

        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent([string]$VersionCode)), "versionCode")
        $form.Add((New-Object System.Net.Http.StringContent($VersionName)), "versionName")
        $form.Add((New-Object System.Net.Http.StringContent($Mandatory.IsPresent.ToString().ToLower())), "mandatory")
        $form.Add((New-Object System.Net.Http.StringContent($Changelog)), "changelog")

        $fileStream = [System.IO.File]::OpenRead((Resolve-Path $ApkSource).Path)
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/vnd.android.package-archive")
        $form.Add($fileContent, "apk", "app-release.apk")

        $task = $client.PostAsync("$ApiBase/publish", $form)
        $task.Wait()
        $resp = $task.Result
        $bodyTask = $resp.Content.ReadAsStringAsync()
        $bodyTask.Wait()
        $fileStream.Close()

        if ($resp.IsSuccessStatusCode) {
            $json = $bodyTask.Result | ConvertFrom-Json
            Write-Host "Servidor actualizado: $($json.message)" -ForegroundColor Green
        } else {
            Write-Warning "Error del servidor ($($resp.StatusCode)): $($bodyTask.Result)"
        }
    } catch {
        Write-Warning "No se pudo notificar al servidor: $_"
        Write-Warning "El APK ya esta en el share. Actualiza manualmente si es necesario."
    }
} else {
    Write-Warning "CHPAY_PUBLISH_KEY no definido. Saltando notificacion al servidor."
    Write-Warning "Define la variable de entorno o pasa -ApiToken <token>"
}

Write-Host "`nPublicacion completada: chpay v$VersionName ($VersionCode)" -ForegroundColor Green
Write-Host "  Descarga publica: http://192.168.1.144/apk/chpay.apk" -ForegroundColor Gray
