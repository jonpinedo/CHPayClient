---
name: chpay-release
description: Publica versiones de CHPay (Desktop y/o Android): bump, build, firma, commit, push y publish OTA. Usar cuando el usuario pida publicar, release, bump, publish_desktop, publish_apk, subir versión, o publicar desktop/android.
---

# CHPay Release (Desktop + Android)

## Alcance según la petición

| Petición del usuario | Qué publicar |
|----------------------|--------------|
| "publicar" / "release" **sin** especificar plataforma | Las plataformas **donde haya cambios** en el working tree / commits pendientes (`desktop/` → Desktop; `lib/`, `android/`, `pubspec.yaml` → Android; ambos si hay en los dos) |
| "publicar desktop" / `publish_desktop` | Solo Desktop |
| "publicar android" / `publish_apk` | Solo Android |
| "compilar" / "build" **sin** pedir publicar | Solo build local. **No** commit, **no** push, **no** publish |

Si al pedir publicar no hay cambios en ninguna plataforma, preguntar qué quiere publicar.

## Regla commit / push

- **Publicar** implica producción → **siempre** commit + push **antes** del publish OTA (incluido el bump de versión).
- **Solo compilar** → no commit, no push, no publish.
- PowerShell: mensajes de commit con múltiples `-m`, no heredoc bash.

**No commitear:** `secrets.local.ps1`, `.pfx`, `*.keystore`, `*.jks`, `*.exe`, `*.apk`, `tools/`, `usbpcap/`, `build/`.

---

## Resumen del sistema

| Qué | Desktop | Android |
|-----|---------|---------|
| Versión | `desktop/build.bat` (`VERSION`, `VERSION_CODE`) | `pubspec.yaml` (`version: X.Y.Z+N`) |
| Build | `desktop/build.bat` → `chpay.exe` | `flutter build apk --release` **siempre desde copia local** (ver abajo) |
| Firma | Authenticode (`sign-exe.ps1`) | **`android/debug.keystore`** (no `~/.android/…`) |
| Prueba local | `desktop/scripts/test-sign-local.ps1` | build APK en disco local + verificar SHA-256 |
| Publish OTA | `desktop/publish_desktop.ps1` | Samba + `POST /api/update/publish` (tras build local) |
| Secretos | `secrets.local.ps1` en la raíz (`CHPAY_PUBLISH_KEY`, `CHPAY_SIGN_PFX`, `CHPAY_SIGN_PFX_PASS`) | misma `CHPAY_PUBLISH_KEY` + keystore local (no git) |
| Docs | `doc/actualizaciones.md`, `desktop/certs/README.md` | `doc/actualizaciones.md`, `android/keystore.README.md` |
| Toolchain | Go + TDM-GCC | Flutter en `C:\src\flutter`, JDK 17, Android SDK en `C:\Android\sdk` |

`build.bat` **no firma** el exe. `publish_desktop.ps1` compila, firma y sube.

---

## Workflow al publicar

```
Release Progress:
- [ ] 1. Detectar plataformas a publicar (petición o archivos tocados)
- [ ] 2. Bump de versión en cada plataforma afectada
- [ ] 3. Prueba/build (Desktop: test-sign-local; Android: sync a `C:\build\CHPayClient` + `flutter build apk`)
- [ ] 4. Commit (siempre, porque se va a publicar)
- [ ] 5. Push (siempre, porque se va a publicar)
- [ ] 6. publish_desktop.ps1 y/o publicar APK (Samba + API; no `publish_apk.ps1` desde el share)
```

### Detectar plataformas por cambios

Considerar Desktop si hay cambios bajo `desktop/` (código o `build.bat`).  
Considerar Android si hay cambios bajo `lib/`, `android/`, o en `pubspec.yaml`.  
Ignorar solo-docs / solo-skill salvo que el usuario pida publicar igual.

### Bump de versión

**Desktop** — editar `desktop/build.bat`:
```bat
set VERSION=X.Y.Z
set VERSION_CODE=N
```
(+1 a `VERSION_CODE` siempre; subir patch de `VERSION` salvo indicación contraria).

**Android** — editar `pubspec.yaml`:
```yaml
version: X.Y.Z+N   # versionName+versionCode
```
(+1 a `N` siempre).

### Prueba local Desktop (antes de publish)

```powershell
cd desktop
.\scripts\test-sign-local.ps1
.\chpay.exe   # 1ª vez: diálogo confianza + UAC; 2ª vez: sin UAC
```

### Commit + push (obligatorio antes de publish)

```powershell
git add <archivos relevantes>
git commit -m "tipo: resumen" -m "Detalle opcional."
git push -u origin HEAD
```

### Publicar Desktop

```powershell
cd desktop
.\publish_desktop.ps1 -Changelog "Descripción para el usuario."
```

Por defecto **no mandatory**. Firma falla si falta PFX en secrets.

### Publicar Android

#### Firma OTA (obligatorio)

Release firma con `android/debug.keystore` (Gradle `signingConfigs.chpay`).  
**No** se usa `~/.android/debug.keystore`.

- Fichero: `android/debug.keystore` (gitignored; backup fuera del repo).
- Doc: `android/keystore.README.md`, `doc/actualizaciones.md`.
- SHA-256 esperado del signer:
  `3c0f236825bfe3de71adb3bb786eb6d42cbf5e6b169740c60b76168cdf9fc8f4`
- Si falta → el build falla. Si se publica otra firma → OTA «aplicación no instalada».

Antes de publicar, tras el build:

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
# SHA-256 digest debe empezar por 3c0f236825bfe3de...
```

#### Importante: no compilar en el share de red

El repo vive en un share (`T:\CHPay\...` / UNC). **`flutter build` falla ahí** con:

```text
ERROR_ACCESS_DENIED ... trying to create a symlink ... windows\flutter\ephemeral\.plugin_symlinks\
```

Los shares no permiten symlinks que Flutter necesita. **Siempre** sincronizar a disco local, compilar ahí, y luego copiar/publicar el APK.

Asegurar que `android/debug.keystore` existe en el share **antes** del robocopy
(así la copia local también lo tiene).

#### Workflow Android (obligatorio)

```powershell
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot'  # ajustar si cambia
$env:ANDROID_HOME = 'C:\Android\sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:Path = "C:\src\flutter\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

$src = 'T:\CHPay\CHPayClient'   # raíz del repo (share)
$local = 'C:\build\CHPayClient' # copia de trabajo en disco local

# Precheck firma
if (-not (Test-Path "$src\android\debug.keystore")) {
  throw "Falta android/debug.keystore — ver android/keystore.README.md"
}

# 1) Sync a local (excluir artefactos pesados; NO excluir debug.keystore)
if (Test-Path $local) { Remove-Item $local -Recurse -Force }
robocopy $src $local /MIR /NFL /NDL /NJH /NJS /nc /ns /np `
  /XD .git build .dart_tool windows\flutter\ephemeral android\.gradle android\app\build `
  /XF *.exe *.apk
# robocopy: códigos 0–7 = OK

# 2) Build en local
Set-Location $local
flutter pub get
flutter build apk --release
# APK: $local\build\app\outputs\flutter-apk\app-release.apk
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk

# 3) Publicar (Samba + API). Cargar secrets desde el repo en el share:
. "$src\secrets.local.ps1"
$VersionName = 'X.Y.Z'   # de pubspec
$VersionCode = N
$apk = "$local\build\app\outputs\flutter-apk\app-release.apk"
$SambaPath = '\\truenas\compartido\apk-releases'
$ApkFilename = "chpay_v${VersionName}_${VersionCode}.apk"
Copy-Item $apk (Join-Path $SambaPath $ApkFilename) -Force
Copy-Item $apk (Join-Path $SambaPath 'chpay.apk') -Force
# Luego POST multipart a http://192.168.1.144:8080/api/update/publish
# (platform=android, versionCode, versionName, mandatory, changelog, apk)
# con Authorization: Bearer $env:CHPAY_PUBLISH_KEY
```

`.\publish_apk.ps1` en la raíz del share **no sirve tal cual** mientras el cwd sea el share: el `flutter build` interno fallará por symlinks. Usar el flujo de copia local anterior (o adaptar el script para aceptar `-BuildDir` / APK ya generado).

Requisitos: Flutter (`C:\src\flutter`), JDK 17, Android SDK (`C:\Android\sdk`), `android/debug.keystore`, Samba `\\truenas\compartido\apk-releases`, `CHPAY_PUBLISH_KEY`.

---

## Certificado Desktop (setup inicial, una vez)

```powershell
cd desktop\scripts
.\create-signing-cert.ps1
```

En `secrets.local.ps1` (raíz):

```powershell
$env:CHPAY_PUBLISH_KEY = "..."
$env:CHPAY_SIGN_PFX = "...\desktop\certs\chpay-signing.pfx"
$env:CHPAY_SIGN_PFX_PASS = "..."
```

Commitear `desktop/certs/chpay-signing.cer` (público). **Nunca** el `.pfx`.

---

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Build CGO falla | TDM-GCC-64 + `GOTOOLCHAIN=go1.22.12` |
| `signtool` no encontrado | Instalar Windows SDK (`winget install Microsoft.WindowsSDK.10.0.22621`) |
| Firma falla | `CHPAY_SIGN_PFX` / `CHPAY_SIGN_PFX_PASS` en secrets |
| SAC bloquea exe | Falta cert en Root → aceptar UAC al arrancar |
| `NotSigned` tras build.bat | Normal; ejecutar `test-sign-local.ps1` o publish |
| Thumbprint no coincide | Regenerar `.cer` y recompilar |
| Samba APK no disponible | Montar `\\truenas\compartido\apk-releases` |
| `ERROR_ACCESS_DENIED` symlink al build Flutter | Compilar en copia local (`C:\build\CHPayClient`), no en `T:\` / UNC |
| `flutter` no reconocido | PATH: `C:\src\flutter\bin` (nueva terminal si hace falta) |
| Android toolchain incompleto | SDK en `C:\Android\sdk`; `JAVA_HOME` → Temurin 17; `flutter doctor` |
| OTA «aplicación no instalada» | Firma distinta: falta/incorrecto `android/debug.keystore` (SHA `3c0f23…`) |
| Build: falta debug.keystore | Copiar keystore a `android/debug.keystore` (ver `android/keystore.README.md`) |
