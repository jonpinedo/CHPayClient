# CHPay Client - TPV NFC para Android

Aplicación Flutter para punto de venta (TPV) con lectura NFC, integrada con backend FastAPI.

## 🎯 Características

- ✅ Lectura de tarjetas NFC (UID)
- ✅ Validación de tarjetas con backend
- ✅ Consulta de saldo en tiempo real
- ✅ Realizar pagos/cobros
- ✅ Realizar recargas
- ✅ Interfaz Material Design 3
- ✅ Gestión de estado con BLoC

## 📦 Dependencias

```yaml
dependencies:
  flutter_sdk: flutter
  nfc_manager: ^4.1.1      # Lectura NFC compatible con Android/iOS
  http: ^1.1.0             # Peticiones HTTP
  flutter_bloc: ^8.1.3     # Gestión de estado
  cupertino_icons: ^1.0.8
```

## 🏗️ Estructura del Proyecto

```
lib/
├── main.dart                    # Punto de entrada
├── config/
│   └── theme.dart              # Tema de la aplicación
├── services/
│   ├── api_service.dart        # Cliente HTTP para backend
│   └── nfc_service.dart        # Servicio de lectura NFC
├── bloc/
│   └── tarjeta_bloc.dart       # BLoC para gestión de tarjetas
└── screens/
    ├── home_screen.dart        # Pantalla principal (leer NFC)
    ├── pago_screen.dart        # Pantalla de cobros
    └── recarga_screen.dart     # Pantalla de recargas
```

## 🔧 Configuración del Backend

Edita `lib/services/api_service.dart` y ajusta la URL base:

```dart
static const String baseUrl = 'http://10.0.2.2:8000'; // Emulador Android
// static const String baseUrl = 'http://TU_IP:8000';  // Dispositivo físico
static const String token = 'TU_TOKEN_AQUI';
```

### Cambiar IP para dispositivo físico:
- Encuentra la IP de tu PC: `ipconfig` (Windows) o `ifconfig` (Linux/Mac)
- Reemplaza `10.0.2.2` con tu IP local (ej: `192.168.1.100`)
- Asegúrate de que el firewall permita conexiones al puerto 8000

## 🚀 Endpoints Esperados del Backend

### POST `/api/tarjetas/validar`
Valida una tarjeta y retorna información del socio.

**Request:**
```json
{
  "uid": "04:A3:B2:C1:D4:E5:F6"
}
```

**Response:**
```json
{
  "nombre": "Juan Pérez",
  "saldo": 45.50,
  "activo": true
}
```

### POST `/api/pagos/`
Registra un pago/cobro.

**Request:**
```json
{
  "uid": "04:A3:B2:C1:D4:E5:F6",
  "monto": 12.50,
  "descripcion": "Consumición"
}
```

**Response:**
```json
{
  "id": 123,
  "nuevo_saldo": 33.00,
  "mensaje": "Pago realizado correctamente"
}
```

### POST `/api/recargas/`
Registra una recarga de saldo.

**Request:**
```json
{
  "uid": "04:A3:B2:C1:D4:E5:F6",
  "monto": 20.00,
  "descripcion": "Recarga efectivo"
}
```

**Response:**
```json
{
  "id": 124,
  "nuevo_saldo": 53.00,
  "mensaje": "Recarga realizada correctamente"
}
```

### GET `/api/recargas/historial/{uid}`
Obtiene el historial de transacciones.

**Response:**
```json
{
  "transacciones": [
    {
      "id": 123,
      "tipo": "pago",
      "monto": -12.50,
      "descripcion": "Consumición",
      "fecha": "2025-11-25T10:30:00"
    }
  ]
}
```

## 📱 Uso de la Aplicación

1. **Conectar dispositivo Android** con NFC activado y modo desarrollador
2. **Ejecutar:**
   ```bash
   cd C:\dev\chpayclient
   flutter run
   ```

3. **En la app:**
   - Presionar "Leer Tarjeta NFC"
   - Acercar tarjeta al teléfono
   - Esperar validación del servidor
   - Seleccionar "COBRO" o "RECARGA"
   - Ingresar monto y confirmar

## 🔐 Permisos Android

Ya configurados en `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.NFC"/>
<uses-feature android:name="android.hardware.nfc" android:required="true"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

## 🧪 Testing

### Probar sin backend (mock):
Comenta las llamadas a `APIService` y usa datos mock:

```dart
// En home_screen.dart línea ~40
final resultado = {
  'nombre': 'Usuario Test',
  'saldo': 50.0,
};
```

### Probar lectura NFC:
1. La app debe detectar automáticamente hardware NFC
2. Si aparece ícono gris: NFC no disponible
3. Si aparece ícono verde después de leer: éxito

## 🛠️ Troubleshooting

### Error: "NFC no disponible"
- Verificar que el dispositivo tenga NFC
- Activar NFC en Ajustes > Conexiones > NFC
- Reiniciar la app

### Error de conexión al backend
- Verificar que el backend esté corriendo: `curl http://localhost:8000/docs`
- En emulador: usar `10.0.2.2` en lugar de `localhost`
- En dispositivo físico: usar IP local de tu PC
- Verificar firewall de Windows

### UID se lee como null
- Asegurarse de usar tarjetas NFC compatibles (ISO14443-A/B, ISO15693)
- Mantener tarjeta pegada hasta que vibre el teléfono
- Revisar logs con `flutter logs`

## 📋 Comandos Útiles

```bash
# Ver dispositivos
adb devices

# Ejecutar en dispositivo específico
flutter run -d RFCW322MBRA

# Ver logs en tiempo real
flutter logs

# Compilar APK release
flutter build apk --release

# Limpiar y rebuildar
flutter clean
flutter pub get
flutter run
```

## 🎨 Personalización

### Cambiar colores:
Edita `lib/config/theme.dart`:

```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: Colors.blue, // Cambiar a tu color
),
```

### Agregar más montos rápidos:
En `lib/screens/recarga_screen.dart`:

```dart
final List<double> montosRapidos = [5.0, 10.0, 20.0, 50.0, 100.0];
```

## 📄 Licencia

MIT License - Proyecto CHPay 2025
