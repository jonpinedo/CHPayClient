# Implementación mTLS - Cliente Flutter

## Resumen Rápido

La aplicación Flutter ahora implementa un flujo completo de registro y certificación de dispositivos:

### Flujo de Usuario

```
App Inicia
    ↓
¿Dispositivo registrado?
    ├─ NO → DeviceRegistrationScreen (registro + polling)
    ├─ SÍ, sin certificado → DeviceRegistrationScreen (descarga + instalación)
    ├─ SÍ, certificado <30 días → DeviceCertificateRenewalScreen (renovación automática)
    └─ OK → HomeScreen (app normal)
```

## Archivos Nuevos Creados

### 1. Servicios

**`lib/services/device_service.dart`**
- Gestión completa del ciclo de vida del dispositivo
- Métodos principales:
  - `registerDevice(name)` - Registrar nuevo dispositivo
  - `checkDeviceStatus()` - Verificar estado actual
  - `downloadCertificate()` - Descargar P12
  - `installCertificate(p12, password)` - Instalar en KeyStore
  - `autoRenewCertificate()` - Renovación automática

### 2. Pantallas

**`lib/screens/device_registration_screen.dart`**
- Estados: not_registered, registrado, aprobado, certificado
- Polling automático cada 5 segundos cuando está pendiente
- Botones contextuales según estado

**`lib/screens/device_certificate_renewal_screen.dart`**
- Renovación transparente cuando faltan <30 días
- Mostrará spinner + mensaje durante renovación
- Recarga automática de app cuando se completa

### 3. Integración Principal

**`lib/main.dart`** modificado:
- App ahora es `StatefulWidget` en lugar de `StatelessWidget`
- `_determineInitialScreen()` ejecuta verificación de dispositivo
- Muestra pantalla adecuada según estado
- `FutureBuilder` gestiona async loading

## Variables de Almacenamiento

`SharedPreferences` (las contraseñas se mejoran en Android con EncryptedSharedPreferences):

```
device_id              → ID del dispositivo en servidor
device_name            → Nombre humano del dispositivo (ej: "TPV-Caja-01")
certificate_status     → REGISTRADO, APROBADO, CERTIFICADO
certificate_expires    → Fecha ISO de expiración
device_certificate.p12 → Archivo binario en filesDir (Android)
device_p12_password    → Contraseña del P12 (encriptada en Android)
```

## Integración con Backend

### Endpoints Utilizados

**POST /api/auth/register-device**
```json
{
  "device_name": "TPV-Caja-01"
}
→ {
  "dispositivo_id": 123,
  "estado": "REGISTRADO",
  "mensaje": "Dispositivo registrado. Espera aprobación del admin."
}
```

**GET /api/auth/device-status/{device_id}**
```json
→ {
  "dispositivo_id": 123,
  "estado_certificado": "REGISTRADO|APROBADO|CERTIFICADO",
  "puede_descargar": false/true,
  "certificado_expira": "2026-12-04T12:07:58",
  "necesita_renovacion": false/true
}
```

**GET /api/auth/download-certificate/{device_id}**
```json
→ {
  "p12_base64": "MIILTAIBAzCC...",
  "p12_password": "a8d9d8c796dcfe687390e11d",
  "certificado_cn": "TPV-Caja-01",
  "certificado_serial": "565031919586350846",
  "emitido_en": "2025-12-04T11:07:58.633741Z",
  "expira_en": "2026-12-04T12:07:58"
}
```

## Implementación Android (Kotlin)

Los archivos siguientes DEBEN crearse para que mTLS funcione:

### 1. CertificateManager.kt
- Importa P12 en Android Keystore
- Crea SSLContext con certificado cliente
- Gestiona ciclo de vida de credenciales

### 2. HttpClientManager.kt
- Envuelve HttpsURLConnection
- Aplica SSLContext automáticamente
- Expone métodos para verificar estado del certificado

### 3. MainActivity.kt (modificaciones)
- Añade Method Channel `com.chpayclient/certificate`
- Expone métodos Kotlin a Flutter:
  - `installCertificate(p12_base64, password)`
  - `hasCertificate()`
  - `getCertificateInfo()`
  - `deleteCertificate()`

Ver archivo **`MTLS_ANDROID_IMPLEMENTATION.md`** para código completo.

## Flujo de Instalación del Certificado

```
1. Backend envía P12 base64 + password
   ↓
2. Flutter: DeviceService.installCertificate(p12Base64, password)
   ↓
3. Dart invoca Platform Method Channel
   ↓
4. Kotlin: CertificateManager.importCertificate(p12Base64, password)
   - Decodificar base64
   - Guardar en filesDir/device.p12 (encriptado en Android)
   - Guardar password en EncryptedSharedPreferences
   ↓
5. Kotlin: HttpClientManager.updateSSLContext()
   - Carga certificado del archivo P12
   - Configura KeyManager con el certificado
   - Crea SSLContext con mTLS
   ↓
6. Siguiente petición HTTPS usa mTLS automáticamente
   - Certificado se envía en TLS handshake
   - Backend verifica certificado del cliente
   - Si válido → respuesta 200
   - Si inválido → respuesta 403
```

## Renovación Automática

Cuando certificado vence en <30 días:

```
1. App inicia → DeviceService.checkDeviceStatus()
   ↓
2. Calcula: days_to_expiry = expira_en - ahora
   ↓
3. Si days_to_expiry < 30:
   - Mostrar DeviceCertificateRenewalScreen
   - Ejecutar DeviceService.autoRenewCertificate()
     • Descargar nuevo certificado
     • Instalar (sobrescribe el anterior)
   - Mostrar mensaje de éxito
   - Continuar a HomeScreen
   ↓
4. Si renovación falla:
   - Mostrar error
   - Ofrecer reintentar
   - Opción "Continuar de todas formas" (no ideal pero permitido)
```

## Seguridad Implementada

✅ **Identificación de Dispositivo Única**
- Cada dispositivo tiene `device_id` único en servidor
- Debe ser aprobado por administrador manualmente

✅ **Certificado mTLS**
- Cliente envía certificado X.509 en TLS handshake
- Servidor valida certificado y revoca si es necesario
- Imposible de falsificar sin clave privada

✅ **Almacenamiento Seguro**
- P12: Guardado en app filesDir (encriptado automáticamente en Android 5.0+)
- Contraseña: EncryptedSharedPreferences (encriptado a nivel del sistema)
- Claves privadas: Nunca salen del KeyStore en Android 6.0+

✅ **Renovación Automática**
- Detecta certificados próximos a caducidad
- Renueva transparentemente sin intervención del usuario
- Alertas informativas si algo falla

## Testing en Desarrollo

Para testing sin certificados reales:

```dart
// En DeviceService, hacer que installCertificate() en dev siempre retorne true
if (kDebugMode) {
  // Simular instalación exitosa sin certificado real
  return true;
}
```

O saltarse el flujo completo:

```dart
// En main.dart, comentar la verificación de dispositivo en dev
if (kDebugMode) {
  return _buildHomeScreen();
}
```

## Próximos Pasos

1. **Crear archivos Kotlin**:
   - `android/app/src/main/kotlin/com/chpayclient/CertificateManager.kt`
   - `android/app/src/main/kotlin/com/chpayclient/HttpClientManager.kt`

2. **Modificar MainActivity.kt**:
   - Añadir Method Channel para `com.chpayclient/certificate`

3. **Actualizar Gradle**:
   - Añadir dependencias de Kotlin si no están

4. **Test en dispositivo real**:
   ```bash
   flutter run
   # 1. Pantalla de registro aparecerá
   # 2. Ingresar nombre del dispositivo
   # 3. Pulsar "Registrar Dispositivo"
   # 4. En Django admin: aprobar dispositivo
   # 5. App mostrará "Instalar Certificado"
   # 6. Descargar e instalar
   # 7. App iniciará normalmente
   ```

## FAQ

**P: ¿Qué pasa si pierdo el certificado?**
- Debes solicitar uno nuevo registrando el dispositivo nuevamente con el mismo nombre

**P: ¿Cómo revocar un dispositivo comprometido?**
- Admin revoca en Django → siguiente petición falla con 403 → app muestra error → usuario debe re-registrarse

**P: ¿Se puede usar la app sin certificado?**
- NO. Endpoints sensibles requieren mTLS. Solo endpoints de registro/estado funcionan sin certificado.

**P: ¿En HTTP (desarrollo local) se requiere mTLS?**
- NO. En `http://localhost`, mTLS se omite. Solo en HTTPS se valida.

**P: ¿La contraseña del P12 se guarda?**
- Sí, en EncryptedSharedPreferences. Se usa solo para importación. Puede eliminarse manualmente tras importación (más seguro).

---

**Versión**: 1.0  
**Fecha**: 2025-12-04  
**Estado**: Listo para Kotlin implementation
