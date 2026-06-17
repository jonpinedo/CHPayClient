# Desarrollo y Build

## Android (Flutter)

### Requisitos

- Flutter SDK ≥ 3.10
- Android SDK 36+
- Dispositivo Android con NFC (emulador no soporta NFC)

### Desarrollo

```powershell
flutter pub get
flutter run             # dispositivo conectado por USB
flutter logs            # ver logs en tiempo real
```

### Build de release

```powershell
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Permisos Android

Configurados en `android/app/src/main/AndroidManifest.xml`:
- `android.permission.NFC` — lectura de tarjetas
- `android.permission.INTERNET` — comunicación API
- `android.permission.REQUEST_INSTALL_PACKAGES` — auto-actualización

### Versión

Editar `pubspec.yaml`:
```yaml
version: 1.1.4+6   # versionName+versionCode
```

---

## Desktop Windows (Go/Fyne)

### Requisitos

- Go ≥ 1.21
- TDM-GCC-64 en `C:\TDM-GCC-64\bin` (CGO requerido por Fyne y PC/SC)
- Ziti Desktop Edge instalado (resuelve `chpay-api.private`)

### Compilación

```powershell
cd desktop
.\build.bat
# Output: desktop/chpay.exe
```

`build.bat` configura automáticamente:
- `PATH` → `C:\TDM-GCC-64\bin`
- `CC` → gcc.exe de TDM
- `CGO_ENABLED=1`
- `-ldflags "-H=windowsgui"` → sin ventana de consola

### Versión

Editar `desktop/build.bat`:
```bat
set VERSION=1.0.4
set VERSION_CODE=5
```

### Icono de la aplicación

El icono se embebe de dos formas:
1. **Fyne (runtime)**: `desktop/icon.go` usa `//go:embed icon.png` → se aplica con `SetIcon()` en ventana y taskbar.
2. **Windows Explorer**: `desktop/app_windows.syso` compilado desde `app.rc` + `icon.ico` con `windres` → el .exe muestra el icono en el explorador.

Para cambiar el icono:
1. Reemplazar `desktop/icon.png`
2. Regenerar `icon.ico` y `app_windows.syso`:
   ```powershell
   cd desktop
   C:\TDM-GCC-64\bin\windres.exe -o app_windows.syso app.rc
   .\build.bat
   ```

### Dependencias Go principales

- `fyne.io/fyne/v2` — UI toolkit
- `github.com/ebfe/scard` — lectores NFC PC/SC
- Standard library para HTTP, JSON, crypto
