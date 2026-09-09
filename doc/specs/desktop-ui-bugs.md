# Spec: Corrección bugs UI / transiciones Desktop

**Estado:** implementado (pendiente prueba manual TPV)  
**Alcance:** `desktop/` (Go/Fyne)  
**Fecha:** 2026-09-09

## Contexto

Auditoría de la app de escritorio. Bugs confirmados de navegación, NFC, scrolls y estado de pantallas cacheadas. Dudas D1–D8 resueltas con el usuario.

## Decisiones (dudas)

| ID | Decisión |
|----|----------|
| D1 | **Bug.** Cancelar en espera NFC → vuelve a calculadora con importe intacto (no a Inicio). |
| D2 | **Bug.** Tras error NFC, Cancelar → misma calculadora (no a Inicio ni borrar importe). |
| D3 | Correcto (cinta operaciones). No tocar. |
| D4 | Resize HSplit OK. No tocar. |
| D5 | Historial con `operaciones` largas OK. No tocar. |
| D6 | Posible glitch ocasional UI desde goroutines. Sin upgrade Fyne 2.4; no se introdujo `fyne.Do`. |
| D7 | Listas: refrescar cache si TTL ≥ 5 min al entrar en Cobrar. |
| D8 | Banner update ya implementado; comentario obsoleto limpiado en `main.go`. |

## Requirements → implementación

| Req | Cambio principal |
|-----|------------------|
| R1 | `navigate` → `OnHide`; Cobrar/Recargar/Admin limpian teclado/NFC |
| R2 | `abortNFCWait` vs `leaveToHome`/`finish` según éxito |
| R3 | `leaveGen` atómico invalida auto-retorno 2.5s |
| R4 | Cabecera tarjeta refrescada en `OnShow` |
| R5 | Scroll en Config y tabs Admin; historial resetea offset |
| R6 | `nameLbl` se actualiza al guardar |
| R7 | `listasIsStale` + reload async en Cobrar |
| R8 | Comentario D8 en `main.go` |

## Archivos tocados

- `doc/specs/desktop-ui-bugs.md` (este spec)
- `desktop/mainwindow.go`, `main.go`
- `desktop/screen_pago.go`, `screen_recarga.go`, `screen_admin.go`, `screen_settings.go`
- `desktop/widget_historial.go`, `listas_cache.go`

## Out of scope

- Upgrade Fyne, Android, backend de “listas modificadas”, firma/OTA.

## Test plan (manual TPV)

- [ ] Cobrar → OK → Cancelar → sigue en Cobrar con importe.
- [ ] Cobrar → OK → tarjeta saldo insuficiente → Cancelar → calculadora con importe.
- [ ] Cobrar → éxito → Volver rápido → nuevo cobro → no aborta a los 2.5s.
- [ ] Cobrar → espera NFC → sidebar Inicio → volver a Cobrar → calculadora (no panel NFC zombie).
- [ ] Cobrar → teclear → sidebar Config → teclas no rellenan cobro oculto.
- [ ] Nueva tarjeta en Inicio → Cobrar muestra nombre/saldo nuevos.
- [ ] Config/Admin con ventana baja: scroll hasta el final.
- [ ] Historial: cambiar tarjeta → lista desde arriba.
- [ ] Guardar nombre en Config → etiqueta actualizada.
- [ ] Cobrar tras >5 min: carta refleja listas si cambiaron en servidor.
