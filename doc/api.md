# Referencia de API

Base URL: `http://chpay-api.private` (vía Ziti overlay)

Todos los endpoints autenticados requieren header `Authorization: Bearer {session_token}`.

---

## Autenticación

### POST `/api/auth/register-request`
Solicita el registro de un nuevo dispositivo.

```json
{
  "device_id": "uuid-v4",
  "nombre": "Terminal Cafetería",
  "capitulo_id": 1          // opcional
}
```

Respuesta 200:
```json
{
  "mensaje": "Solicitud de registro recibida. Esperando aprobación."
}
```

### POST `/api/auth/authorize`
Obtiene token permanente tras aprobación del admin.

```json
{
  "device_id": "uuid-v4",
  "nombre": "Terminal Cafetería"
}
```

Respuesta 200:
```json
{
  "token": "permanent-token-string"
}
```

Respuesta 403 (aún no aprobado):
```json
{
  "detail": "Dispositivo no aprobado"
}
```

### POST `/api/auth/session`
Crea un bearer de sesión temporal.

```json
{
  "device_id": "uuid-v4",
  "token": "permanent-token-string"
}
```

Respuesta 200:
```json
{
  "bearer": "session-bearer-token"
}
```

### GET `/api/auth/me`
Información del dispositivo autenticado.

Respuesta 200:
```json
{
  "dispositivo_id": 1,
  "nombre": "Terminal Cafetería",
  "tipo": "TERMINAL_COBRO",
  "roles": ["TERMINAL", "CAJA"],
  "roles_display": ["Terminal de Cobro", "Caja de Recarga"],
  "activo": true,
  "capitulo_id": 1,
  "capitulo_nombre": "Sede Central"
}
```

---

## Capítulos

### GET `/api/capitulos/` (público, sin auth)
Lista todos los capítulos disponibles.

Respuesta 200:
```json
[
  {
    "id": 1,
    "nombre": "Sede Central",
    "tipo": "BAR",
    "direccion": "Calle Mayor 1",
    "tiene_logo": true
  }
]
```

### GET `/api/capitulos/{id}/logo` (público, sin auth)
Descarga el logo del capítulo como imagen binaria (PNG/JPEG).

Respuesta 200: `Content-Type: image/png` — body binario  
Respuesta 404: el capítulo no tiene logo

---

## Tarjetas

### POST `/api/tarjetas/validar`
Valida una tarjeta NFC y devuelve info del socio.

```json
{
  "uid": "AB:CD:EF:12:34:56:78"
}
```

Respuesta 200:
```json
{
  "socio_id": 1,
  "numero_socio": 123,
  "nombre": "Juan Pérez",
  "saldo": "150.50",
  "permitido": true,
  "mensaje": "Tarjeta válida",
  "monedero_creado": false
}
```

`monedero_creado: true` indica que se acaba de crear un monedero para el socio en este capítulo. El cliente debe mostrar un aviso al operador.

### GET `/api/tarjetas/saldo/{uid}`
Consulta el saldo actual.

Respuesta 200:
```json
{
  "socio_id": 1,
  "numero_socio": 123,
  "nombre": "Juan Pérez",
  "saldo": "150.50",
  "activo": true,
  "tarjeta_activa": true
}
```

---

## Pagos

### POST `/api/pagos/`
Realiza un cobro. Requiere rol `TERMINAL`.

```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 25.50,
  "descripcion": "Consumición"
}
```

Respuesta 200:
```json
{
  "transaccion_id": 456,
  "socio_nombre": "Juan Pérez",
  "monto": "25.50",
  "saldo_anterior": "150.50",
  "saldo_posterior": "125.00",
  "timestamp": "2026-06-17T10:30:00",
  "exitoso": true,
  "mensaje": "Pago procesado correctamente"
}
```

---

## Recargas

### POST `/api/recargas/`
Realiza una recarga. Requiere rol `CAJA`.

```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 50.00,
  "descripcion": "Recarga en efectivo"
}
```

Respuesta 200:
```json
{
  "transaccion_id": 457,
  "socio_nombre": "Juan Pérez",
  "monto": "50.00",
  "saldo_anterior": "125.00",
  "saldo_posterior": "175.00",
  "timestamp": "2026-06-17T10:35:00",
  "exitoso": true,
  "mensaje": "Recarga procesada correctamente"
}
```

### GET `/api/recargas/historial/{uid}?limite=10`
Historial de transacciones de un socio.

Respuesta 200:
```json
{
  "socio_nombre": "Juan Pérez",
  "transacciones": [
    {
      "id": 457,
      "tipo": "RECARGA",
      "monto": "50.00",
      "saldo_posterior": "175.00",
      "timestamp": "2026-06-17T10:35:00",
      "descripcion": "Recarga en efectivo"
    }
  ]
}
```

---

## Actualizaciones OTA

### GET `/api/update/version?platform={android|desktop}` (sin auth)
Consulta si hay una versión más reciente.

Respuesta 200:
```json
{
  "versionCode": 6,
  "versionName": "1.1.5",
  "mandatory": false,
  "changelog": "Correcciones menores",
  "available": true
}
```

### GET `/api/update/apk` (con auth)
Descarga el APK de Android.

### GET `/api/update/exe` (con auth)
Descarga el EXE de Desktop.

### POST `/api/update/publish` (admin)
Publica una nueva versión. Usado por los scripts de publicación.

Parámetros multipart/form-data:
- `platform`: `android` | `desktop`
- `versionCode`: integer
- `versionName`: string
- `mandatory`: `true` | `false`
- `changelog`: string
- `apk` o `exe`: archivo binario
