# Lectores NFC (Desktop)

El cliente Desktop soporta dos tipos de lector NFC a la vez. La lógica vive en
`desktop/nfc.go` (fachada + bucle de polling) y en los backends por tipo.

| Backend | Archivo | Transporte | Ejemplo |
|---------|---------|------------|---------|
| PC/SC | `desktop/nfc_pcsc.go` | `winscard.dll` vía `github.com/ebfe/scard` | ACR122U y lectores CCID estándar |
| HID NFC-X | `desktop/nfc_hid_windows.go` | HID crudo vía `hid.dll` / `setupapi.dll` (sin CGO) | Lector "NFC-X" / `Cyb_Nfctool` (VID `0483` / PID `4343`) |

En sistemas no Windows el backend HID queda como stub vacío
(`desktop/nfc_hid_stub.go`), por lo que el resto del código compila igual.

## Modelo de lector

Cada lector detectado se representa con `nfcReaderInfo` (`desktop/nfc_reader.go`):

- `ID` — identificador estable que se persiste en configuración:
  - PC/SC: `pcsc:<nombre del lector>`
  - HID: `hid:nfcx:<vid>:<pid>:<serial>` (p. ej. `hid:nfcx:0483:4343:BEGIN-2025`)
- `Label` — texto legible que se muestra en Configuración.
- `Kind` — `pcsc` o `hid`.

`nfcEnumerateAllReaders()` combina los lectores PC/SC e HID presentes en cada
vuelta del polling. La enumeración es dinámica: un lector solo aparece mientras
está conectado y desaparece al desconectarlo.

## Selección en Configuración

La sección "Lector NFC" de `desktop/screen_settings.go` muestra:

- Nada seleccionable si hay 0 lectores.
- Un único lector activo (sin desplegable) si hay 1.
- Un desplegable si hay 2 o más.

La preferencia se guarda como `nfc_reader` en `config.json` usando el `ID`
estable (`desktop/config.go`). Los valores antiguos (nombre de lector PC/SC en
crudo, antes de los IDs con prefijo) se migran automáticamente al detectarse el
lector correspondiente.

## Semántica de polling

El bucle (`nfcPollingLoop`) imita el comportamiento de un ACR122U y es común a
ambos backends:

- Sondea cada `300 ms`.
- `OnCardDetected(uid)` se dispara **una sola vez** por tarjeta nueva o cuando
  cambia el UID.
- Mientras se siga leyendo el mismo UID no se emiten más eventos.
- `OnCardRemoved()` se dispara al dejar de leer tarjeta.

Diferencia por robustez: en HID se exige que fallen varias lecturas seguidas
(`nfcHIDMissingThreshold`) antes de considerar la tarjeta retirada, para evitar
falsos negativos entre sondeos. En PC/SC la retirada es inmediata.

Las pantallas (Inicio, Cobrar, Recargar, Admin) no saben qué backend está
activo: solo consumen `NFCCallbacks`, así que la integración es transparente.

## Protocolo HID del NFC-X (ingeniería inversa)

El lector NFC-X no es PC/SC: se presenta como dispositivo compuesto USB con dos
interfaces:

- `MI_00` — almacenamiento masivo (un "U-disk" con un enlace a la web del
  fabricante y su `.exe`). Se ignora.
- `MI_01` — HID con *usage page* de fabricante (`0xFF00`), que es la vía real de
  comunicación.

Características HID:

- Reports de **65 bytes**: 1 byte de Report ID (`0x00`) + 64 bytes de datos.
- Fabricante `CYBDZKJ-BSJ`, producto `TCC-TSY-TBY`.

Las tramas siguen el formato `55 00 <cmd> 00 <len> <payload...> <crc16>`.
Comandos usados (capturados con USBPcap del software oficial `Cyb_Nfctool`):

```
OUT  55 00 51 00 01 01 FE 01      # ping de estado (previo a la lectura)
OUT  55 00 69 00 00 FF 00         # leer tarjeta
IN   55 00 69 00 13 01 01 <UID de 7 bytes> 00 00 00 <uidLen> <ATQA lo> <ATQA hi> <SAK> <tipo> 00 00 <crc16>
```

Ejemplo real de respuesta para una tarjeta NTAG/Ultralight:

```
UID=04038413460289  uidLen=7  ATQA=0044  SAK=00  tipo=0x02
```

`nfcHIDParseUID` (`desktop/nfc_hid_windows.go`) valida la cabecera `55 .. 69` y
extrae el UID como hex en mayúsculas, igual que el backend PC/SC, para que el
resto de la app reciba el mismo formato.

> El CRC16 final del dispositivo no se recalcula: los comandos que enviamos son
> constantes capturadas, por lo que no necesitamos generarlo.

## Herramienta de diagnóstico

`desktop/tools/hidprobe` es una utilidad independiente (Go puro, sin CGO) que
enumera el lector HID, imprime sus capacidades y permite escuchar/enviar tramas.
Sirvió para reconstruir el protocolo y es útil para depurar, pero **no forma
parte del runtime** de CHPay.

```powershell
cd desktop
go run ./tools/hidprobe -listen=false        # inspección de capacidades
go run ./tools/hidprobe -active               # enviar comandos y ver respuestas
```

## Resolución de problemas

- **El NFC-X no lee en CHPay**: cierra `Cyb_Nfctool`. Solo un proceso puede usar
  la interfaz HID a la vez.
- **Desaparece un lector PC/SC tras usar herramientas de captura USB**: reiniciar
  todos los dispositivos USB (p. ej. con USBPcap) puede dejar un lector CCID sin
  re-registrar en el subsistema de tarjetas, aunque siga en el Administrador de
  dispositivos. Se recupera desconectando y reconectando el lector, reiniciando
  el servicio `SCardSvr` (como administrador) o reiniciando Windows.
- **Solo aparece un lector**: es el comportamiento normal cuando solo hay uno
  presente; el desplegable únicamente se muestra con 2 o más.
