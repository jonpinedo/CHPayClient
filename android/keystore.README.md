# Firma Android (OTA)

Los APK de release se firman con **`android/debug.keystore`** (ruta fija en el
proyecto), no con `~/.android/debug.keystore` del usuario. Así todas las
máquinas de build usan la misma firma y el OTA no rompe con
«La aplicación no está instalada».

El fichero **no se versiona** (`android/.gitignore` → `**/*.keystore`).

## Dónde ponerlo

```
android/debug.keystore
```

En un PC nuevo: copiar desde backup / otro PC de build a esa ruta (junto a
`android/app/`, no dentro de `app/`).

Ruta habitual en el PC de origen (keystore Android Studio por defecto):

```
%USERPROFILE%\.android\debug.keystore
```

## Verificar que es el correcto

```powershell
keytool -list -v `
  -keystore android\debug.keystore `
  -storepass android `
  -alias androiddebugkey
```

SHA-256 esperado (el de las APK en producción / Samba `chpay_v1.1.x` y posteriores
firmadas correctamente):

```
3C:0F:23:68:25:BF:E3:DE:71:AD:B3:BB:78:6E:B6:D4:2C:BF:5E:6B:16:97:40:C6:0B:76:16:8C:DF:9F:C8:F4
```

Tras `flutter build apk --release`:

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

El digest SHA-256 del signer debe coincidir con el de arriba.

## Si falta el fichero

Gradle **falla el build** a propósito. Sin este keystore, un `debug.keystore`
nuevo en el perfil de usuario firmaría con otra clave y el OTA dejaría de
funcionar en los TPV ya instalados.

## Alias / contraseña

Es un keystore en formato debug de Android:

| Campo | Valor |
|-------|--------|
| alias | `androiddebugkey` |
| storePassword / keyPassword | `android` |

## Backup

Guardar una copia segura fuera del repo (mismo criterio que el `.pfx` de
Desktop). Perder este fichero obliga a desinstalar/reinstalar en todos los TPV.
