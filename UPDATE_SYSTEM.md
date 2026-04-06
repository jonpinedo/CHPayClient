# CHPay — Sistema de Actualización OTA

Guía técnica completa para implementar la detección y descarga de actualizaciones
en el cliente Flutter.

---

## Arquitectura

```
App arranca (_determineInitialScreen)
  │
  ├─ Ziti OK + sesión OK
  │       ↓
  │  checkForUpdate()          ← NUEVO paso antes de HomeScreen
  │       │
  │  GET /api/update/version   ← sin auth (responde aunque el bearer expire)
  │       │
  │  ¿serverVersionCode > localVersionCode?
  │       │
  │  NO → HomeScreen (normal)
  │       │
  │  SÍ, opcional → Banner en HomeScreen + descarga background
  │       │
  │  SÍ, mandatory → Dialog bloqueante hasta instalar
  │
  └─ Descarga APK
          GET /api/update/apk   ← autenticada con bearer
          guarda en caché local
          abre instalador sistema Android (1 tap)
```

El APK se descarga **directamente desde Kotlin** a través del cliente OkHttp Ziti
para soportar ficheros grandes (50-100 MB) sin cargar toda la memoria.
La capa Dart solo coordina y muestra progreso.

---

## 1. Dependencias Flutter (`pubspec.yaml`)

Añadir al bloque `dependencies`:

```yaml
package_info_plus: ^6.0.0    # leer versionCode local
open_filex: ^4.4.0           # abrir el instalador APK del sistema
path_provider: ^2.1.0        # rutas de directorio temporal
permission_handler: ^11.3.0  # REQUEST_INSTALL_PACKAGES
```

Ejecutar tras añadir:
```
flutter pub get
```

---

## 2. Android — Permisos y FileProvider

### `android/app/src/main/AndroidManifest.xml`

Añadir el permiso **antes** de `<application>`:

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
```

Añadir el **FileProvider** dentro de `<application>`, junto a los otros `<meta-data>`:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="com.example.chpayclient.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths"/>
</provider>
```

### `android/app/src/main/res/xml/file_paths.xml` ← fichero nuevo

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="apk_downloads" path="apk_downloads/"/>
</paths>
```

---

## 3. Kotlin — Descarga a fichero en `ZitiManager.kt`

El OkHttpClient ya existente con el socket factory de Ziti gestiona la descarga.
Hay que añadir un método nuevo **al final de la clase** (antes del `}`):

```kotlin
/**
 * Descarga el APK más reciente desde el servidor vía Ziti al directorio de caché.
 * Llama al callback [onProgress] con el porcentaje (0-100) a medida que avanza.
 * Devuelve la ruta absoluta del fichero descargado, o lanza una excepción.
 */
suspend fun downloadApk(
    url: String,
    bearer: String,
    destDir: java.io.File,
    onProgress: (Int) -> Unit
): String = withContext(Dispatchers.IO) {
    val client = httpClient
        ?: throw IllegalStateException("Ziti no inicializado")

    val request = Request.Builder()
        .url(url)
        .addHeader("Authorization", "Bearer $bearer")
        .get()
        .build()

    val response = client.newCall(request).execute()
    if (!response.isSuccessful) {
        throw IOException("Error descargando APK: HTTP ${response.code}")
    }

    val body = response.body ?: throw IOException("Respuesta vacía del servidor")
    val totalBytes = body.contentLength()   // -1 si el servidor no env\u00eda Content-Length

    destDir.mkdirs()
    val destFile = java.io.File(destDir, "chpay_update.apk")
    if (destFile.exists()) destFile.delete()

    var downloadedBytes = 0L
    body.byteStream().use { input ->
        destFile.outputStream().use { output ->
            val buffer = ByteArray(8 * 1024)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                output.write(buffer, 0, read)
                downloadedBytes += read
                if (totalBytes > 0) {
                    onProgress((downloadedBytes * 100 / totalBytes).toInt())
                }
            }
        }
    }

    Log.i(TAG, "APK descargado: ${destFile.absolutePath} (${downloadedBytes / 1024} KB)")
    destFile.absolutePath
}
```

---

## 4. Kotlin — MethodChannel en `MainActivity.kt`

Añadir la constante dentro del `companion object`:

```kotlin
private const val UPDATE_CHANNEL = "com.chpayclient/update"
```

Añadir el handler dentro de `configureFlutterEngine`, junto a los otros channels:

```kotlin
// --- Update MethodChannel ---
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "downloadApk" -> {
                val url    = call.argument<String>("url")
                val bearer = call.argument<String>("bearer")
                if (url == null || bearer == null) {
                    result.error("INVALID_ARG", "url y bearer son requeridos", null)
                    return@setMethodCallHandler
                }
                val cacheDir = java.io.File(applicationContext.cacheDir, "apk_downloads")
                scope.launch {
                    try {
                        // Progreso: enviamos eventos al canal de eventos Dart
                        // (simplificado: informamos solo el path final)
                        val path = zitiManager.downloadApk(url, bearer) { progress ->
                            // En un impl. avanzado: usar EventChannel para enviar progreso
                            Log.d("Update", "Descarga: $progress%")
                        }
                        result.success(mapOf("path" to path))
                    } catch (e: Exception) {
                        result.error("DOWNLOAD_FAILED", e.message, null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
```

> **Nota sobre progreso:** para una barra de progreso en Dart necesitarías un
> `EventChannel`. Para la primera implementación funcional es suficiente con el
> resultado final. Se puede añadir despues.

---

## 5. Dart — `lib/services/update_service.dart` ← fichero nuevo

```dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'ziti_service.dart';

const String _kBaseUrl = 'http://chpay-api.private';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final bool mandatory;
  final String changelog;
  final bool available;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.mandatory,
    required this.changelog,
    required this.available,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionCode: json['versionCode'] as int,
        versionName: json['versionName'] as String,
        mandatory:   json['mandatory']   as bool,
        changelog:   json['changelog']   as String,
        available:   json['available']   as bool,
      );
}

class UpdateService {
  static const _channel = MethodChannel('com.chpayclient/update');

  /// Consulta el servidor y devuelve [UpdateInfo] si hay una versión más nueva,
  /// o null si la app está al día o si la consulta falla (no bloqueante).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await ZitiService.get('$_kBaseUrl/api/update/version');
      if (response.statusCode != 200) return null;

      final info = UpdateInfo.fromJson(response.body);
      if (!info.available) return null;

      final pkg = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(pkg.buildNumber) ?? 0;

      if (info.versionCode <= localCode) return null; // ya al día
      return info;
    } catch (_) {
      // El check de versión nunca debe bloquear el arranque
      return null;
    }
  }

  /// Descarga el APK e invoca el instalador del sistema Android.
  /// El [bearer] es el token de sesión activo del dispositivo.
  /// Devuelve true si el instalador se abrió correctamente.
  static Future<bool> downloadAndInstall(String bearer) async {
    // Solicitar permiso de instalación si no está concedido
    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) {
      throw Exception('Permiso REQUEST_INSTALL_PACKAGES denegado');
    }

    final result = await _channel.invokeMethod<Map>('downloadApk', {
      'url':    '$_kBaseUrl/api/update/apk',
      'bearer': bearer,
    });

    final path = result?['path'] as String?;
    if (path == null || !File(path).existsSync()) {
      throw Exception('APK no encontrado tras la descarga');
    }

    final openResult = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return openResult.type == ResultType.done;
  }
}
```

---

## 6. Integración en `lib/main.dart`

El check de actualización se inserta en `_determineInitialScreen()`, justo antes
de devolver `_buildHomeScreen()`:

```dart
// Añadir import al inicio del fichero:
import 'services/update_service.dart';

// Añadir campo de estado en _ChPayAppState:
UpdateInfo? _pendingUpdate;

// Dentro de _determineInitialScreen(), sustituir la última línea:
//   return _buildHomeScreen();
// por:

      // ─── Check de actualización (no bloqueante en arranque) ─────────
      final update = await UpdateService.checkForUpdate();
      if (update != null) {
        setState(() => _pendingUpdate = update);
      }

      print('✅ Dispositivo autorizado. Mostrando HomeScreen.');
      return _buildHomeScreen();
```

Y modificar `_buildHomeScreen()` para que pase the update info:

```dart
Widget _buildHomeScreen() {
  return HomeScreen(pendingUpdate: _pendingUpdate);
}
```

---

## 7. UI en `lib/screens/home_screen.dart`

### Constructor — añadir el parámetro optional:

```dart
class HomeScreen extends StatefulWidget {
  final UpdateInfo? pendingUpdate;   // ← añadir
  const HomeScreen({Key? key, this.pendingUpdate}) : super(key: key);
  ...
}
```

### Banner de actualización opcional

En el `build()` de `_HomeScreenState`, envolver el body en una `Column` e insertar
el banner arriba:

```dart
// Añadir import al inicio:
import '../services/update_service.dart';
import '../services/auth_service.dart'; // para obtener el bearer

// Método a añadir en _HomeScreenState:
Widget _buildUpdateBanner(UpdateInfo update) {
  if (update.mandatory) {
    // Dialog bloqueante — se muestra en initState via WidgetsBinding
    return const SizedBox.shrink();
  }
  return MaterialBanner(
    padding: const EdgeInsets.all(12),
    content: Text(
      'Nueva versión ${update.versionName} disponible',
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    leading: const Icon(Icons.system_update, color: Colors.blue),
    backgroundColor: Colors.blue.shade50,
    actions: [
      TextButton(
        onPressed: () async {
          final bearer = await AuthService.getCurrentBearer();
          if (bearer != null) {
            await UpdateService.downloadAndInstall(bearer);
          }
        },
        child: const Text('INSTALAR'),
      ),
      TextButton(
        onPressed: () => setState(() => _dismissedUpdate = true),
        child: const Text('AHORA NO'),
      ),
    ],
  );
}

// En initState — mostrar dialog bloqueante si mandatory:
@override
void initState() {
  super.initState();
  if (widget.pendingUpdate?.mandatory == true) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMandatoryUpdateDialog(widget.pendingUpdate!);
    });
  }
}

void _showMandatoryUpdateDialog(UpdateInfo update) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Actualización requerida'),
      content: Text(
        'La versión ${update.versionName} es obligatoria.\n\n${update.changelog}',
      ),
      actions: [
        ElevatedButton(
          onPressed: () async {
            final bearer = await AuthService.getCurrentBearer();
            if (bearer != null) {
              await UpdateService.downloadAndInstall(bearer);
            }
          },
          child: const Text('Instalar ahora'),
        ),
      ],
    ),
  );
}
```

Añadir `_dismissedUpdate` como variable de estado en `_HomeScreenState`:

```dart
bool _dismissedUpdate = false;
```

---

## 8. Flujo de trabajo (publicar nueva versión)

### Requisitos previos (una sola vez)

1. Definir la variable de entorno en Windows:
   ```powershell
   [System.Environment]::SetEnvironmentVariable("CHPAY_ADMIN_TOKEN", "<token-admin>", "User")
   ```

2. Asegurarse de que el share Samba está montado como `\\truenas\compartido`.

### Ciclo de release normal

```powershell
# 1. Incrementar versión en pubspec.yaml:
#    version: 1.0.1+2   ← versionName+versionCode (ambos deben subir)

# 2. Publicar (build + copia + notificación al servidor):
.\publish_apk.ps1 -Changelog "Descripción de los cambios"

# 3. Las apps existentes detectarán la actualización en el próximo arranque.
#    Los dispositivos mostrarán el banner "Nueva versión disponible".
```

### Para una actualización obligatoria (urgente):

```powershell
.\publish_apk.ps1 -Mandatory -Changelog "Corrección de seguridad crítica"
# Las apps mostrarán un dialog bloqueante hasta que el usuario instale.
```

---

## 9. Obtener el `CHPAY_ADMIN_TOKEN`

El token es el `token_autenticacion` permanente de un dispositivo con rol ADMIN.
Se puede obtener desde el shell del servidor:

```bash
sudo docker compose -f docker-compose.ziti.yml exec django \
  python manage.py shell -c "
from core.models import DispositivoNFC
d = DispositivoNFC.objects.filter(roles__contains='ADMIN').first()
print(d.token_autenticacion)
"
```

O directamente desde Django admin → Dispositivos NFC → columna "Token de Autenticación".

---

## 10. Resumen de ficheros a crear/modificar

| Fichero | Acción |
|---------|--------|
| `pubspec.yaml` | Añadir 4 dependencias |
| `android/app/src/main/AndroidManifest.xml` | Permiso + FileProvider |
| `android/app/src/main/res/xml/file_paths.xml` | Nuevo — rutas FileProvider |
| `android/app/src/main/kotlin/.../ZitiManager.kt` | Añadir `downloadApk()` |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Añadir UPDATE_CHANNEL |
| `lib/services/update_service.dart` | Nuevo |
| `lib/main.dart` | Integrar `checkForUpdate()` |
| `lib/screens/home_screen.dart` | Banner + dialog mandatory |
