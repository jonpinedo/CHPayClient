# Sistema de Actualizaciones OTA

Ambas plataformas soportan actualizaciones automáticas desde el servidor.

## Flujo General

```
App arranca
  │
  ├─ Sesión OK
  │     ↓
  │  GET /api/update/version?platform={android|desktop}
  │     │
  │  ¿versionCode servidor > versionCode local?
  │     │
  │  NO → operación normal
  │     │
  │  SÍ, mandatory=false → banner informativo + descarga en background
  │     │
  │  SÍ, mandatory=true  → bloqueo hasta instalar
  │
  └─ Descarga binario → instala → reinicia
```

## Desktop (Windows)

### Auto-reemplazo del EXE

1. `checkForUpdate()` consulta la versión disponible.
2. `downloadUpdate()` descarga el nuevo exe a `%TEMP%\chpay-update.exe`.
3. `applyUpdate()` lanza el nuevo exe con flags:
   ```
   chpay-update.exe --upgrade --target="C:\ruta\chpay.exe" --oldpid=1234
   ```
4. El exe descargado (`handleUpgradeMode()`) espera que el proceso original termine, se copia sobre el target, se relanza desde la ruta final y elimina el temporal.

### Compilación

```bat
cd desktop
build.bat
```

La versión se define en `desktop/build.bat`:
```
set VERSION=1.0.4
set VERSION_CODE=5
```

Se inyecta via ldflags: `-X main.AppVersion=1.0.4 -X main.AppVersionCode=5`

### Publicación

```powershell
cd desktop
.\publish_desktop.ps1 [-Mandatory] [-Changelog "Descripción"]
```

Requisitos:
- API key admin, vía variable de entorno `CHPAY_PUBLISH_KEY`, parámetro
  `-ApiKey`, o el fichero `secrets.local.ps1` en la raíz del workspace (no
  versionado, compartido con `publish_apk.ps1`, se carga automáticamente).
  Ejemplo de ese fichero:
  ```powershell
  $env:CHPAY_PUBLISH_KEY = "tu-api-key"
  $env:CHPAY_SIGN_PFX = "T:\...\desktop\certs\chpay-signing.pfx"
  $env:CHPAY_SIGN_PFX_PASS = "contraseña-del-pfx"
  ```
- Go + TDM-GCC-64 configurados
- Windows SDK (`signtool.exe`) para firmar el exe — instalar si falta:
  ```powershell
  winget install --id Microsoft.WindowsSDK.10.0.22621 -e
  ```
  Componente: **Windows SDK Signing Tools for Desktop Apps**
- Certificado de firma: generar con `desktop/scripts/create-signing-cert.ps1`
  (ver `desktop/certs/README.md`)

El script:
1. Lee la versión de `build.bat`
2. Compila con `build.bat`
3. Firma con `desktop/scripts/sign-exe.ps1` (Authenticode + timestamp)
4. Sube el exe a `POST /api/update/publish` con metadata

### Prueba local antes de publicar

`build.bat` no firma el exe. Para validar build + firma + certificado embebido sin subir al servidor:

```powershell
cd desktop
.\scripts\test-sign-local.ps1
.\chpay.exe
```

Checklist: firma `Valid` → 1ª ejecución pide UAC (certificado de confianza) → 2ª ejecución sin UAC.
Detalle en `desktop/certs/README.md` y `doc/pendientes.md`.

## Android (Flutter)

### Firma del APK (crítica para OTA)

Release usa siempre `android/debug.keystore` (configurado en
`android/app/build.gradle.kts`). **No** se usa `~/.android/debug.keystore`.

- El keystore **no está en git**. Ver `android/keystore.README.md`.
- SHA-256 esperado:
  `3C:0F:23:68:25:BF:E3:DE:71:AD:B3:BB:78:6E:B6:D4:2C:BF:5E:6B:16:97:40:C6:0B:76:16:8C:DF:9F:C8:F4`
- Si falta el fichero, el build falla. Si se publica con otra firma, en el TPV
  aparece «La aplicación no está instalada» al actualizar.

### Descarga del APK

El APK se descarga desde Kotlin a través del OkHttp con Ziti para soportar ficheros grandes sin cargar la memoria completa.

La capa Dart coordina y muestra progreso. Una vez descargado, abre el instalador del sistema Android.

### Compilación

```
flutter build apk --release
```

Requisito: `android/debug.keystore` presente. Compilar desde **copia local** si
el repo está en un share de red (symlinks); ver skill de release.

La versión se define en `pubspec.yaml`:
```yaml
version: 1.2.2+9   # versionName+versionCode
```

### Publicación

```powershell
.\publish_apk.ps1 [-Mandatory] [-Changelog "Descripción"]
```

(En share de red: build en `C:\build\CHPayClient` y luego Samba + API; el script
en el share falla por symlinks.)

Requisitos:
- Flutter en PATH
- `android/debug.keystore` (firma OTA)
- Samba share `\\truenas\compartido\apk-releases` montado
- `CHPAY_PUBLISH_KEY` (opcional, para notificar al servidor): variable de
  entorno, parámetro `-ApiToken`, o `secrets.local.ps1` en la raíz del workspace

El script:
1. Lee la versión de `pubspec.yaml`
2. Ejecuta `flutter build apk --release`
3. Copia el APK al share Samba como `chpay_vX.Y.Z_N.apk` y `chpay.apk` (enlace fijo)
4. Notifica al servidor con `POST /api/update/publish` (multipart con APK incluido)

URL de descarga pública fija: `http://192.168.1.144/apk/chpay.apk`
