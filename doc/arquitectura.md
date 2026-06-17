# Arquitectura del Sistema

CHPay Client es un terminal de punto de venta (TPV) NFC con dos plataformas:

| Plataforma | Tecnología | NFC | Red |
|------------|-----------|-----|-----|
| Android | Flutter/Dart | Hardware NFC del móvil | OpenZiti SDK (overlay) |
| Windows Desktop | Go + Fyne v2 | Lectores PC/SC (ACR122U, etc.) | Ziti Desktop Edge (tunnel) |

## Comunicación con el Backend

Ambos clientes se comunican con `http://chpay-api.private` a través de la red overlay OpenZiti. No se usa HTTPS directo ni IPs públicas.

- **Android**: El SDK de Ziti intercepta las peticiones HTTP y las enruta por la overlay.
- **Desktop**: El servicio Ziti Desktop Edge crea un túnel local que resuelve `chpay-api.private`.

## Flujo de Autenticación

Esquema de 3 pasos:

```
1. register-request  →  Solicitar registro del dispositivo (requiere aprobación admin)
2. authorize         →  Obtener token permanente (se persiste localmente)
3. session           →  Crear bearer de sesión (en memoria, por cada arranque)
```

### Registro

1. La app envía `POST /api/auth/register-request` con `device_id` (UUID), `nombre` y opcionalmente `capitulo_id`.
2. Un administrador aprueba el dispositivo desde el panel backend.
3. La app hace polling de `POST /api/auth/authorize` hasta que el backend devuelve un `token` permanente.
4. En cada arranque, `POST /api/auth/session` genera un bearer temporal que se usa para todas las llamadas autenticadas.

## Multi-tenancy (Capítulos)

Los dispositivos pertenecen a un **capítulo** (sede/local). El capítulo se asigna opcionalmente durante el registro y determina:

- El logo mostrado en la interfaz
- El monedero donde se cargan saldos iniciales de nuevos socios
- El filtrado de operaciones

Si un dispositivo no tiene `capitulo_id` asignado (null en `GET /api/auth/me`), se bloquean las operaciones hasta que un admin lo asigne.

## Estructura del Proyecto

```
/                         Proyecto Flutter (Android)
├── lib/
│   ├── main.dart         Entrada, routing según estado auth
│   ├── services/         API, Auth, NFC, Ziti, Update
│   ├── screens/          Pantallas (home, pago, recarga, registro, admin)
│   ├── bloc/             BLoC para gestión de estado de tarjetas
│   └── config/           Tema visual
├── android/              Configuración nativa Android
├── desktop/              Proyecto Go/Fyne independiente
│   ├── main.go           Entrada y controller
│   ├── api.go            Cliente HTTP y structs
│   ├── auth.go           Flujo de autenticación
│   ├── config.go         Persistencia de configuración
│   ├── nfc.go            Lectura NFC via PC/SC
│   ├── update.go         Sistema OTA de actualización
│   ├── screen_*.go       Pantallas
│   ├── build.bat         Script de compilación
│   └── publish_desktop.ps1  Publicación de versión
└── doc/                  Documentación
```
