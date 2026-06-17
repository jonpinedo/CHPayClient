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
- Variable de entorno `CHPAY_PUBLISH_KEY` con API key admin
- Go + TDM-GCC-64 configurados

El script:
1. Lee la versión de `build.bat`
2. Compila con `build.bat`
3. Sube el exe a `POST /api/update/publish` con metadata

## Android (Flutter)

### Descarga del APK

El APK se descarga desde Kotlin a través del OkHttp con Ziti para soportar ficheros grandes sin cargar la memoria completa.

La capa Dart coordina y muestra progreso. Una vez descargado, abre el instalador del sistema Android.

### Compilación

```
flutter build apk --release
```

La versión se define en `pubspec.yaml`:
```yaml
version: 1.1.4+6   # versionName+versionCode
```

### Publicación

```powershell
.\publish_apk.ps1 [-Mandatory] [-Changelog "Descripción"]
```

Requisitos:
- Flutter en PATH
- Samba share `\\truenas\compartido\apk-releases` montado
- Variable `CHPAY_PUBLISH_KEY` (opcional, para notificar al servidor)

El script:
1. Lee la versión de `pubspec.yaml`
2. Ejecuta `flutter build apk --release`
3. Copia el APK al share Samba como `chpay_vX.Y.Z_N.apk` y `chpay.apk` (enlace fijo)
4. Notifica al servidor con `POST /api/update/publish` (multipart con APK incluido)

URL de descarga pública fija: `http://192.168.1.144/apk/chpay.apk`
