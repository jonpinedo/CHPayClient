# API Endpoints - Sistema de Pagos NFC CHPay

## Información General

- **Base URL:** `https://localhost` (producción)
- **Base URL Android:** `https://10.0.2.2` (para emulador/dispositivo físico)
- **Autenticación:** Bearer Token en header `Authorization: Bearer {token}`
- **Content-Type:** `application/json`

---

## 🔐 Autenticación

### GET `/api/auth/me`
Obtiene información del dispositivo autenticado y sus roles.

**Headers:**
```
Authorization: Bearer {token}
```

**Respuesta 200:**
```json
{
  "dispositivo_id": 1,
  "nombre": "Terminal Cafetería",
  "tipo": "TERMINAL_COBRO",
  "roles": ["TERMINAL"],
  "roles_display": ["Terminal de Cobro"],
  "activo": true
}
```

**Uso:** Verificar token válido y determinar qué funcionalidades mostrar según roles.

---

## 📇 Tarjetas

### POST `/api/tarjetas/validar`
Valida que una tarjeta exista, esté activa y devuelve información del socio.

**Headers:**
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Body:**
```json
{
  "uid": "AB:CD:EF:12:34:56:78"
}
```

**Respuesta 200:**
```json
{
  "socio_id": 1,
  "numero_socio": 123,
  "nombre": "Juan Pérez",
  "saldo": "150.50",
  "permitido": true,
  "mensaje": "Tarjeta válida"
}
```

**Uso:** Validar tarjeta antes de realizar pago o recarga.

---

### GET `/api/tarjetas/saldo/{uid}`
Consulta el saldo de un socio por UID de tarjeta.

**Headers:**
```
Authorization: Bearer {token}
```

**Parámetros:**
- `uid` (path, required): UID de la tarjeta NFC

**Respuesta 200:**
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

## 💰 Pagos

### POST `/api/pagos/`
Realiza un cobro a un socio. Valida saldo suficiente y actualiza el saldo.

**Requiere rol:** `TERMINAL` (Terminal de Cobro)

**Headers:**
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Body:**
```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 25.50,
  "descripcion": "Compra en cafetería"
}
```

**Respuesta 200:**
```json
{
  "transaccion_id": 456,
  "socio_nombre": "Juan Pérez",
  "monto": "25.50",
  "saldo_anterior": "150.50",
  "saldo_posterior": "125.00",
  "timestamp": "2025-11-25T10:30:00",
  "exitoso": true,
  "mensaje": "Pago procesado correctamente"
}
```

---

## 🔄 Recargas

### POST `/api/recargas/`
Realiza una recarga de saldo en efectivo a un socio.

**Requiere rol:** `CAJA` (Caja de Recarga)

**Headers:**
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Body:**
```json
{
  "uid": "AB:CD:EF:12:34:56:78",
  "monto": 50.00,
  "descripcion": "Recarga en efectivo"
}
```

**Respuesta 200:**
```json
{
  "transaccion_id": 457,
  "socio_nombre": "Juan Pérez",
  "monto": "50.00",
  "saldo_anterior": "125.00",
  "saldo_posterior": "175.00",
  "timestamp": "2025-11-25T10:35:00",
  "exitoso": true,
  "mensaje": "Recarga procesada correctamente"
}
```

---

### GET `/api/recargas/historial/{uid}`
Obtiene el historial de transacciones de un socio.

**Headers:**
```
Authorization: Bearer {token}
```

**Parámetros:**
- `uid` (path, required): UID de la tarjeta NFC
- `limite` (query, optional): Número de transacciones a retornar (default: 10)

**Ejemplo:** `/api/recargas/historial/AB:CD:EF:12:34:56:78?limite=20`

**Respuesta 200:**
```json
{
  "socio_nombre": "Juan Pérez",
  "transacciones": [
    {
      "id": 457,
      "tipo": "RECARGA",
      "monto": "50.00",
      "saldo_posterior": "175.00",
      "timestamp": "2025-11-25T10:35:00",
      "descripcion": "Recarga en efectivo"
    },
    {
      "id": 456,
      "tipo": "PAGO",
      "monto": "-25.50",
      "saldo_posterior": "125.00",
      "timestamp": "2025-11-25T10:30:00",
      "descripcion": "Compra en cafetería"
    }
  ],
  "total_transacciones": 2
}
```

---

## 👨‍💼 Administración

### POST `/api/admin/socios`
Crea un nuevo socio en el sistema.

**Requiere rol:** `ADMIN` (Terminal Administrativo)

**Headers:**
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Body:**
```json
{
  "numero_socio": 123,
  "nombre": "Juan Pérez",
  "email": "juan@example.com",
  "telefono": "612345678",
  "saldo_inicial": "0.00"
}
```

**Respuesta 200:**
```json
{
  "id": 1,
  "numero_socio": 123,
  "nombre": "Juan Pérez",
  "saldo": "0.00",
  "activo": true,
  "mensaje": "Socio creado correctamente"
}
```

---

### POST `/api/admin/tarjetas`
Asocia una tarjeta NFC a un socio existente.

**Requiere rol:** `ADMIN` (Terminal Administrativo)

**Headers:**
```
Authorization: Bearer {token}
Content-Type: application/json
```

**Body:**
```json
{
  "numero_socio": 123,
  "uid": "AB:CD:EF:12:34:56:78",
  "descripcion": "Tarjeta principal"
}
```

**Respuesta 200:**
```json
{
  "tarjeta_id": 1,
  "socio_nombre": "Juan Pérez",
  "uid": "AB:CD:EF:12:34:56:78",
  "uid_encriptado": "encrypted_hash_here",
  "activa": true,
  "fecha_emision": "2025-11-25",
  "mensaje": "Tarjeta asociada correctamente"
}
```

---

## 🏥 Salud del Sistema

### GET `/health`
Verifica que el API esté funcionando.

**No requiere autenticación**

**Respuesta 200:**
```json
{
  "status": "ok"
}
```

---

### GET `/`
Endpoint raíz del API.

**No requiere autenticación**

---

## 📝 Notas Importantes

### Formato del UID
El UID de las tarjetas NFC debe seguir el formato generado por el lector:
- Ejemplo: `AB:CD:EF:12:34:56:78`
- Formato: Bytes hexadecimales separados por dos puntos, en mayúsculas

### Roles del Sistema
- **TERMINAL**: Terminal de cobro (puede realizar pagos)
- **CAJA**: Caja de recarga (puede realizar recargas)
- **ADMIN**: Terminal administrativo (puede crear socios y asociar tarjetas)

### URLs por Entorno
- **Desarrollo local (web):** `https://localhost`
- **Android Emulador:** `https://10.0.2.2`
- **Android Dispositivo físico:** `https://{IP_DEL_SERVIDOR}`

### Códigos de Estado HTTP
- `200`: Operación exitosa
- `401`: Token inválido o expirado
- `403`: Sin permisos (rol insuficiente)
- `404`: Recurso no encontrado (tarjeta/socio inexistente)
- `422`: Error de validación (datos inválidos)
- `500`: Error interno del servidor

### Manejo de Errores
Todos los endpoints pueden retornar errores en formato:
```json
{
  "detail": "Descripción del error"
}
```

O para errores de validación (422):
```json
{
  "detail": [
    {
      "loc": ["body", "uid"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

---

## 🔧 Configuración en Flutter

### api_service.dart
```dart
static const String baseUrl = 'https://10.0.2.2'; // Android
static const String token = 'tu_token_bearer_aqui';
```

### Ejemplo de uso
```dart
// Validar tarjeta
final resultado = await APIService.validarTarjeta('AB:CD:EF:12:34:56:78');

// Realizar pago
final pago = await APIService.hacerPago('AB:CD:EF:12:34:56:78', 25.50, 'Compra');

// Realizar recarga
final recarga = await APIService.hacerRecarga('AB:CD:EF:12:34:56:78', 50.00, 'Recarga');
```

---

**Última actualización:** 25 de noviembre de 2025
