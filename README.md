# CHPay Client

Terminal de punto de venta (TPV) NFC para el sistema de pagos CHPay.

## Plataformas

| | Android | Windows Desktop |
|---|---------|----------------|
| Tecnología | Flutter/Dart | Go + Fyne v2 |
| NFC | Hardware del dispositivo | Lector PC/SC (ACR122U) |
| Red | OpenZiti SDK | Ziti Desktop Edge |
| Build | `flutter build apk --release` | `desktop\build.bat` |
| Publicar | `.\publish_apk.ps1` | `desktop\publish_desktop.ps1` |

## Inicio rápido

### Android

```powershell
flutter pub get
flutter run           # con dispositivo USB conectado
```

### Desktop

```powershell
cd desktop
.\build.bat           # genera chpay.exe
.\chpay.exe
```

## Documentación

- [Arquitectura](doc/arquitectura.md) — Estructura del proyecto, flujo de auth, multitenancy
- [API](doc/api.md) — Referencia completa de endpoints
- [Desarrollo](doc/desarrollo.md) — Build, versiones, requisitos
- [Actualizaciones](doc/actualizaciones.md) — Sistema OTA y scripts de publicación
- Activar NFC en Ajustes > Conexiones > NFC
- Revisar permisos en AndroidManifest.xml
---

## Desktop (Windows)

Cliente Go/Fyne portable para Windows. Requiere Ziti Desktop Edge instalado y enrolado.

### Compilar
```bat
cd desktop
build.bat
```

### Publicar actualizaci�n
```powershell
$env:CHPAY_PUBLISH_KEY = "tu-api-key"
.\publish_desktop.ps1 -Mandatory -Changelog "Descripci�n"
```