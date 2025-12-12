# Testing del Flujo de Certificados mTLS

## Test Manual Rápido

### 1. Iniciar la App

```bash
flutter run
```

**Resultado esperado:**
- La app detecta que no hay dispositivo registrado
- Muestra `DeviceRegistrationScreen`
- Input para nombre del dispositivo visible

### 2. Registrar Dispositivo

1. Ingresar nombre: `TPV-Test-01`
2. Pulsar "Registrar Dispositivo"

**Resultado esperado:**
- Mensaje: "Dispositivo registrado. Esperando aprobación..."
- Spinner con polling cada 5 segundos
- Logs en consola: `📱 Cargando información del dispositivo...`

### 3. Aprobar en Django Admin

En el panel de Django:
```
/admin/auth_app/dispositivo/
```

1. Buscar `TPV-Test-01`
2. Cambiar estado a `APROBADO`
3. Guardar

**Resultado esperado en app:**
- Después de ~5 segundos, la pantalla cambia automáticamente
- Aparece botón "Instalar Certificado"
- Icono verde de verificado

### 4. Instalar Certificado

1. Pulsar "Instalar Certificado"

**Resultado esperado:**
- Mensaje: "Certificado instalado correctamente"
- Logs en consola Flutter:
  ```
  📦 Instalando certificado vía Method Channel...
  ✅ Certificado instalado en KeyStore
  ```
- Logs en logcat Android:
  ```
  I/CertificateManager: 📦 Iniciando importación de certificado...
  I/CertificateManager: ✅ Base64 decodificado: XXXX bytes
  I/CertificateManager: ✅ KeyStore PKCS12 validado correctamente
  I/CertificateManager: ✅ Certificado guardado en: /data/user/0/.../files/device.p12
  I/CertificateManager: 🎉 Certificado importado correctamente
  I/MainActivity: ✅ Certificado instalado y SSLContext actualizado
  ```
- La app continúa a `HomeScreen`

### 5. Verificar mTLS en Peticiones

La próxima petición a la API debe usar el certificado:

**Logs esperados en logcat:**
```
I/HttpClientManager: 🔐 Conexión HTTPS configurada con mTLS para: https://api...
```

**En servidor (Caddy logs):**
```
X-Client-Cert-CN: TPV-Test-01
X-Client-Cert-Serial: 565031919586...
X-Client-Cert-Valid: true
```

## Test con ADB Logcat

Para ver los logs detallados de Android:

```bash
# Ver solo logs de la app
adb logcat | Select-String "CertificateManager|HttpClientManager|MainActivity"

# Ver todos los logs relevantes
adb logcat *:E CertificateManager:I HttpClientManager:I MainActivity:I
```

## Verificar Certificado Instalado

Desde Flutter DevTools Console:

```dart
// Verificar si hay certificado
import 'package:chpayclient/services/device_service.dart';
print(await DeviceService.hasCertificateInstalled());

// Obtener información del certificado
print(await DeviceService.getCertificateInfo());
```

**Salida esperada:**
```json
{
  "CN": "TPV-Test-01",
  "Serial": "565031919586350846...",
  "Subject": "CN=TPV-Test-01,O=CHPay,C=ES",
  "Issuer": "CN=CHPay CA,O=CHPay,C=ES",
  "NotBefore": "Wed Dec 04 12:07:58 CET 2025",
  "NotAfter": "Thu Dec 04 13:07:58 CET 2026"
}
```

## Test de Renovación Automática

1. En Django, modificar `certificado_expira` del dispositivo a 20 días en el futuro
2. Reiniciar app

**Resultado esperado:**
- App detecta `dias_para_expiry < 30`
- Muestra `DeviceCertificateRenewalScreen`
- Renovación automática en curso
- Mensaje: "Renovando certificado de seguridad..."
- Descarga nuevo certificado
- Instala automáticamente
- Continúa a `HomeScreen`

## Test de Dispositivo Revocado

1. En Django, cambiar estado a `REVOCADO`
2. Intentar hacer una petición protegida

**Resultado esperado:**
- Servidor responde 403 Forbidden
- App muestra error: "Certificado inválido o dispositivo no autorizado"

## Comandos Útiles

```bash
# Ver archivos en filesDir
adb shell run-as com.example.chpayclient ls -la /data/data/com.example.chpayclient/files/

# Ver SharedPreferences
adb shell run-as com.example.chpayclient cat /data/data/com.example.chpayclient/shared_prefs/certificates.xml

# Limpiar datos de la app (reset completo)
adb shell pm clear com.example.chpayclient

# Ver certificado (si está en texto)
adb shell run-as com.example.chpayclient cat /data/data/com.example.chpayclient/files/device.p12 | base64
```

## Troubleshooting

### "Error al instalar certificado"

**Verificar:**
1. Logs de Android: `adb logcat | Select-String "CertificateManager"`
2. El P12 base64 no está corrupto
3. La contraseña es correcta (24 caracteres hex)

### "No se pudo conectar al servidor"

**Verificar:**
1. Servidor está ejecutándose
2. URL correcta en `APIService.baseUrl`
3. Caddy configurado para mTLS

### "Certificado no se envía en peticiones"

**Verificar:**
1. `HttpClientManager.updateSSLContext()` se llamó tras instalar certificado
2. Las peticiones usan HTTPS (no HTTP)
3. Logs: `🔐 Conexión HTTPS configurada con mTLS`

### "App crashea al registrar dispositivo"

**Verificar:**
1. Backend responde correctamente a `/api/auth/register-device`
2. Token de autorización es válido
3. Logs de Flutter: `flutter logs`

## Casos de Prueba Completos

| #  | Caso | Pasos | Resultado Esperado |
|----|------|-------|-------------------|
| 1  | Registro exitoso | 1. Abrir app<br>2. Ingresar nombre<br>3. Registrar | Polling activo, esperando aprobación |
| 2  | Aprobación manual | 1. Aprobar en Django<br>2. Esperar poll | Botón "Instalar Certificado" visible |
| 3  | Instalación certificado | 1. Pulsar instalar | Certificado en KeyStore, HomeScreen |
| 4  | Petición con mTLS | 1. Usar API protegida | Certificado enviado, respuesta 200 |
| 5  | Renovación automática | 1. Certificado <30 días<br>2. Abrir app | Renovación transparente |
| 6  | Dispositivo revocado | 1. Revocar en Django<br>2. Usar API | Error 403, mensaje claro |
| 7  | Reinstalar app | 1. Desinstalar<br>2. Reinstalar | Debe registrar nuevamente |
| 8  | Certificado expirado | 1. Esperar expiración | Renovación automática o error claro |

---

**Última actualización:** 2025-12-04  
**Versión:** 1.0
