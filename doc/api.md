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
  "capitulo_nombre": "Sede Central",
  "seguridad_recarga": "desactivada",
  "exigir_identificacion_recarga": false
}
```

| Campo | Tipo | Notas |
|-------|------|-------|
| `seguridad_recarga` | string | `desactivada` \| `pin` \| `tarjeta` — modo de identificación del capítulo |
| `exigir_identificacion_recarga` | bool | Si el cliente debe pedir PIN/tarjeta en recarga. El servidor ya exceptúa ADMIN. Si el campo no viene (API vieja), tratar como `false` |

La UI de recarga solo mira `exigir_identificacion_recarga` para decidir si pedir identificación; `seguridad_recarga` indica el modo. No recalcular con roles en el cliente.
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
  "descripcion": "Consumición",
  "operaciones": "2×3.00 + 1×1.50"
}
```

| Campo | Tipo | Obligatorio | Notas |
|-------|------|-------------|-------|
| `uid` | string | Sí | UID tarjeta NFC |
| `monto` | decimal | Sí | Importe del cobro |
| `descripcion` | string | No | Máx. 255 caracteres |
| `operaciones` | string | No | Cadena informativa del detalle del cobro (máx. 1000 chars). Solo usado por Desktop; si no se envía queda `null` |

La respuesta no incluye `operaciones`.

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

Body sin identificación (legacy / seguridad desactivada):

```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 50.00,
  "descripcion": "Recarga en efectivo"
}
```

Modo PIN (`seguridad_recarga = pin` y `exigir_identificacion_recarga = true`):

```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 50.00,
  "descripcion": "Recarga en efectivo",
  "pin": "1234"
}
```

Modo tarjeta operador (`seguridad_recarga = tarjeta`):

```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 50.00,
  "descripcion": "Recarga en efectivo",
  "uid_operador": "12:34:56:78:9A:BC:DE"
}
```

| Campo | Tipo | Obligatorio | Notas |
|-------|------|-------------|-------|
| `uid` | string | Sí | UID tarjeta NFC del **cliente** |
| `monto` | decimal | Sí | Importe de la recarga |
| `descripcion` | string | No | Máx. 255 caracteres |
| `pin` | string | Condicional | Exactamente 4 dígitos. Solo en modo PIN; no enviar junto con `uid_operador` |
| `uid_operador` | string | Condicional | UID NFC del **operador**. Solo en modo tarjeta; puede coincidir con `uid` del cliente |

Flujo cliente recomendado: importe → NFC cliente → si `exigir_identificacion_recarga`, pedir PIN o segunda lectura NFC → POST. Cancelar en PIN/tarjeta aborta la recarga. No guardar el PIN en el dispositivo.

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

Errores HTTP 400 — `detail` puede ser string (legacy) u objeto:

```json
{ "detail": { "codigo": "PIN_INVALIDO", "mensaje": "PIN inválido" } }
```

| `codigo` | Acción UI |
|----------|-----------|
| `IDENTIFICACION_REQUERIDA` | Pedir de nuevo PIN/tarjeta y reintentar el POST |
| `PIN_INVALIDO` | Mostrar mensaje, limpiar PIN y reintentar (sin bloqueo por intentos) |
| `TARJETA_OPERADOR_INVALIDA` | Mostrar mensaje y volver a pedir lectura de operador |
| `IDENTIFICACION_MODO_INCORRECTO` | Bug de cliente: campo enviado no coincide con `seguridad_recarga` |

Parseo tolerante: si `detail` es string, usarlo como mensaje; si es objeto, usar `mensaje` y `codigo` para ramificar.
### GET `/api/recargas/historial/{uid}?limite=10`
Historial de transacciones de un socio.

Respuesta 200:
```json
{
  "socio_nombre": "Juan Pérez",
  "transacciones": [
    {
      "id": 79,
      "tipo": "COBRO",
      "monto": "7.50",
      "saldo_posterior": "59.50",
      "timestamp": "2026-06-26T15:39:59.294454Z",
      "descripcion": "Bar",
      "operaciones": "2×3.00 + 1×1.50"
    },
    {
      "id": 78,
      "tipo": "COBRO",
      "monto": "3.00",
      "saldo_posterior": "62.50",
      "timestamp": "2026-06-26T14:00:00",
      "descripcion": "Pago",
      "operaciones": null
    },
    {
      "id": 77,
      "tipo": "RECARGA",
      "monto": "20.00",
      "saldo_posterior": "175.00",
      "timestamp": "2026-06-17T10:35:00",
      "descripcion": "Recarga en efectivo",
      "operaciones": null
    }
  ],
  "total_transacciones": 3
}
```

`operaciones` es `null` en recargas, ajustes y cobros antiguos (p. ej. Android no lo envía).

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
