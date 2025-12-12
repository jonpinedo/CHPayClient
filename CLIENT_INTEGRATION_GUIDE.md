# Guía de Integración mTLS para Cliente Android/iOS

## 1. Flujo de Autenticación

### Paso 1: Registro del Dispositivo
```
POST /api/auth/register-device
Content-Type: application/json

{
  "device_name": "TPV-Caja-01"  // Nombre único del dispositivo
}

Response (201):
{
  "dispositivo_id": 123,
  "nombre": "TPV-Caja-01",
  "estado": "REGISTRADO",
  "mensaje": "Dispositivo registrado. Espera aprobación del admin.",
  "proximos_pasos": [...]
}
```

### Paso 2: Verificar Aprobación (Poll)
```
GET /api/auth/device-status/{dispositivo_id}

Response:
{
  "dispositivo_id": 123,
  "nombre": "TPV-Caja-01",
  "estado_certificado": "APROBADO",  // Estados: REGISTRADO, APROBADO, CERTIFICADO
  "puede_descargar": true,            // True cuando admin ha aprobado
  "certificado_serial": null,         // Será generado en download
  "certificado_expira": null,
  "necesita_renovacion": false
}
```

**Polling:** Verificar cada 5-10 segundos hasta que `puede_descargar` sea `true`

### Paso 3: Descargar Certificado
```
GET /api/auth/download-certificate/{dispositivo_id}

Response (200):
{
  "p12_base64": "MIILTAIBAzCCCwYGCSqGSIb3...",  // Base64 PKCS#12
  "p12_password": "a8d9d8c796dcfe687390e11d",     // Contraseña hex (24 chars)
  "dispositivo_nombre": "TPV-Caja-01",
  "certificado_cn": "TPV-Caja-01",
  "certificado_serial": "565031919586350846...",
  "emitido_en": "2025-12-04T11:07:58.633741Z",
  "expira_en": "2026-12-04T12:07:58",
  "instrucciones": {
    "android": "Importar el archivo P12 en Android Keystore",
    "ios": "Usar el perfil de configuración para instalar el certificado"
  }
}
```

## 2. Instalación del Certificado

### Android
1. **Decodificar Base64:**
   ```java
   byte[] p12Bytes = Base64.decode(p12_base64, Base64.DEFAULT);
   ```

2. **Guardar archivo P12:**
   ```java
   FileOutputStream fos = new FileOutputStream(context.getFilesDir() + "/device.p12");
   fos.write(p12Bytes);
   fos.close();
   ```

3. **Importar en KeyStore:**
   ```java
   KeyStore keyStore = KeyStore.getInstance("PKCS12");
   FileInputStream fis = new FileInputStream(context.getFilesDir() + "/device.p12");
   keyStore.load(fis, p12_password.toCharArray());
   
   // Usar KeyStore con HttpClient
   KeyManagerFactory kmf = KeyManagerFactory.getInstance("X509");
   kmf.init(keyStore, p12_password.toCharArray());
   ```

4. **Configurar OkHttp/HttpClient para usar el certificado:**
   ```java
   SSLContext sslContext = SSLContext.getInstance("TLSv1.2");
   sslContext.init(kmf.getKeyManagers(), null, null);
   
   OkHttpClient client = new OkHttpClient.Builder()
     .sslSocketFactory(sslContext.getSocketFactory(), trustManager)
     .build();
   ```

### iOS
1. **Decodificar Base64:**
   ```swift
   let p12Data = Data(base64Encoded: p12_base64)
   ```

2. **Importar en Keychain:**
   ```swift
   var items: CFArray?
   let status = SecPKCS12Import(p12Data as CFData, 
                                [kSecImportExportPassphrase: p12_password] as CFDictionary,
                                &items)
   ```

3. **Usar con URLSession:**
   ```swift
   var request = URLRequest(url: url)
   // URLSessionDelegate con didReceiveChallenge:
   // Proporcionar identidad del cliente desde Keychain
   ```

## 3. Realizar Peticiones con Certificado

Después de instalar el certificado, todas las peticiones a la API deben incluir el certificado cliente.

### Endpoints que requieren mTLS:
```
POST   /api/pagos/realizar-pago
POST   /api/recargas/procesar-recarga
GET    /api/tarjetas/...
POST   /api/tarjetas/...
GET/POST /api/admin/...
GET    /api/auth/download-certificate/{id}
```

### Endpoints que NO requieren mTLS:
```
POST   /api/auth/register-device
GET    /api/auth/device-status/{id}
GET    /api/auth/me                    // Opcional: info extra si mTLS presente
```

**Nota:** El cliente HTTP debe estar configurado para enviar el certificado automáticamente en todas las peticiones HTTPS.

## 4. Renovación de Certificado

Verificar renovación antes de cada sesión:

```
GET /api/auth/device-status/{dispositivo_id}

if (necesita_renovacion == true) {
  // El certificado vence en <30 días
  // Descargar nuevo certificado:
  GET /api/auth/download-certificate/{dispositivo_id}
  // Instalar nuevo P12
  // Recargar en KeyStore/Keychain
}
```

## 5. Formato de Peticiones API

### Ejemplo: Realizar Pago
```
POST /api/pagos/realizar-pago
Content-Type: application/json
[certificado mTLS automático del cliente HTTP]

{
  "uid_tarjeta": "12a3b4c5d6e7f8g9",
  "monto_centavos": 5000,
  "referencia_pago": "PAGO-001"
}

Response:
{
  "id": "pago-uuid-123",
  "estado": "completado",
  "monto": 50.00,
  "timestamp": "2025-12-04T12:00:00Z"
}
```

### Ejemplo: Procesar Recarga
```
POST /api/recargas/procesar-recarga
Content-Type: application/json
[certificado mTLS automático]

{
  "uid_tarjeta": "12a3b4c5d6e7f8g9",
  "monto_centavos": 10000,
  "referencia_recarga": "REC-001"
}

Response:
{
  "id": "recarga-uuid-456",
  "estado": "completado",
  "monto": 100.00,
  "timestamp": "2025-12-04T12:00:00Z"
}
```

## 6. Manejo de Errores

### 403 Forbidden - Certificado inválido/revocado
```json
{
  "detail": "Certificado inválido o dispositivo no autorizado"
}
```
**Acción:** Forzar re-registro (volver al Paso 1)

### 401 Unauthorized - Sin certificado
```json
{
  "detail": "No autenticado"
}
```
**Acción:** El cliente HTTP no está enviando certificado. Verificar instalación.

### 409 Conflict - Dispositivo ya registrado
```json
{
  "detail": "Dispositivo ya registrado con estado: REGISTRADO"
}
```
**Acción:** Usar mismo `dispositivo_id` en siguiente polling

### 404 Not Found - Dispositivo no existe
```json
{
  "detail": "Dispositivo no encontrado"
}
```
**Acción:** Volver a registrar

## 7. Variables de Entorno / Configuración

```
BASE_URL = "https://api.chpay.local"  // Cambiar hostname según deployment
POLLING_INTERVAL = 5000                // 5 segundos entre polls
CERTIFICATE_RENEWAL_WARNING_DAYS = 30  // Alertar si expira en <30 días
```

## 8. Flujo Completo de Implementación

```
1. Usuario abre app → Mostrar pantalla de registro
2. Input: nombre del dispositivo (ej: "TPV-Caja-01")
3. Click "Registrar" → POST /api/auth/register-device
4. Guardar dispositivo_id localmente
5. Mostrar pantalla "Esperando aprobación del admin..."
6. Poll cada 5s → GET /api/auth/device-status/{id}
7. Cuando puede_descargar=true → GET /api/auth/download-certificate/{id}
8. Guardar P12 + password en almacenamiento seguro
9. Importar certificado en KeyStore/Keychain
10. Recargar cliente HTTP para usar certificado
11. ✅ App lista para usar
12. (Opcional) Verificar renovación al iniciar sesión diaria
```

## 9. Almacenamiento Seguro

### Android (EncryptedSharedPreferences)
```java
// NO guardar en SharedPreferences normal
// Usar EncryptedSharedPreferences para:
// - p12_password
// - dispositivo_id
// - certificado_serial
// - certificado_expira

// El P12 guardarlo en:
// - KeyStore (para certificado)
// - O EncryptedFile para backup
```

### iOS (Keychain)
```swift
// Guardar en Keychain:
// - Identidad del certificado
// - dispositivo_id
// - certificado_serial
// - certificado_expira

// NO guardar password en claro
// La contraseña solo se usa en importación inicial
```

## 10. Headers Importantes

**De Caddy (reverse proxy) hacia el backend:**
Estos headers son automáticos, el cliente no necesita enviarlos.

```
X-Client-Cert-CN: TPV-Caja-01           // Nombre del dispositivo
X-Client-Cert-Serial: 565031919586...   // Serial del certificado
X-Client-Cert-Valid: true                // Validez del certificado
```

**Del cliente hacia Caddy:**
Solo HTTPS con certificado cliente en TLS handshake. No hay header especial.

## Preguntas Frecuentes

**P: ¿Qué pasa si el dispositivo pierde el certificado?**  
R: Volver a registrarse (POST /register-device con mismo nombre) o descargar nuevamente si aún está aprobado.

**P: ¿Cómo revocar un certificado?**  
R: El admin lo revoca desde Django. El cliente recibirá 403 en siguiente petición y debe re-registrarse.

**P: ¿Qué pasa si expira el certificado?**  
R: El cliente debe renovarlo antes. El app debe alertar cuando `necesita_renovacion=true`.

**P: ¿Se puede usar la app sin certificado?**  
R: No. Endpoints protegidos requieren mTLS. Solo `register-device` y `device-status` funcionan sin certificado.

**P: ¿Cómo testear en desarrollo?**  
R: Usar BASE_URL=http://localhost (HTTP, no HTTPS). En HTTP, mTLS no se valida en dev.

---

**Versión:** 1.0  
**Fecha:** 2025-12-04  
**Contacto:** Backend CHPay Team
