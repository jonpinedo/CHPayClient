# Cambios pendientes

## Firma de código del Desktop (Windows)

**Estado:** implementado — certificado generado; pendiente prueba manual UAC/OTA en TPV piloto.

### Requisitos

1. Firmar cada `chpay.exe` antes de publicar (Authenticode + sellado de tiempo).
2. **No hay dominio** — no se usará GPO ni AD.
3. **En cada actualización OTA** (y en el primer arranque) comprobar si el certificado de firma está instalado en el TPV.
4. Si falta, **solicitar elevación automática** (UAC); el usuario no debe tener que “Ejecutar como administrador” manualmente.
5. Tras instalar el certificado, **continuar** con el arranque normal o con el proceso OTA.

### Solución elegida

**Certificado embebido + auto-elevación con el propio `chpay.exe`**

Un único flujo cubre instalación inicial, arranques sueltos y OTA, sin dominio ni scripts manuales de admin.

```
                    ┌─────────────────────────────────────┐
                    │  Arranque normal  o  antes de OTA   │
                    └─────────────────┬───────────────────┘
                                      ▼
                    ┌─────────────────────────────────────┐
                    │  ¿Certificado de firma en           │
                    │  LocalMachine\Root? (por thumbprint)│
                    └─────────┬───────────────┬───────────┘
                              │ Sí            │ No
                              ▼               ▼
                    ┌──────────────┐   ┌──────────────────────┐
                    │  Continuar   │   │ Diálogo: "CHPay      │
                    │  (UI / OTA)  │   │ necesita confiar en  │
                    └──────────────┘   │ su editor…" [Aceptar]│
                                       └──────────┬───────────┘
                                                  ▼
                                       ┌──────────────────────┐
                                       │ Relanzar chpay.exe   │
                                       │ con --install-trust- │
                                       │ cert  (verb runas →  │
                                       │ UAC automático)      │
                                       └──────────┬───────────┘
                                                  ▼
                                       ┌──────────────────────┐
                                       │ Proceso elevado:     │
                                       │ extrae chpay-signing │
                                       │ .cer embebido →      │
                                       │ Import-Certificate   │
                                       │ LocalMachine\Root    │
                                       └──────────┬───────────┘
                                                  ▼
                                       ┌──────────────────────┐
                                       │ Proceso padre espera │
                                       │ éxito → continúa     │
                                       └──────────────────────┘
```

**Por qué esta solución y no otras**

| Opción | ¿Cumple requisitos? |
|--------|---------------------|
| GPO / script manual de admin | No — requiere dominio o intervención manual |
| Instalar cert solo en `CurrentUser\Root` sin UAC | Parcial — no pide admin, pero SAC puede seguir bloqueando |
| Instalar cert en cada OTA sin comprobar | No — no cumple 2.2 |
| **Embebido + comprobar + UAC automático** | **Sí** — cumple 2.1–2.4 |

No hace falta un instalador MSI ni un `.exe` auxiliar: el flag `--install-trust-cert` en el mismo binario evita desplegar más ficheros.

---

## Fase 1 — Certificado y firma en build/publicación

### 1.1 Crear certificado (una vez)

Script `desktop/scripts/create-signing-cert.ps1`:

- `New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=CHPay Desktop, O=CHPay" …`
- Exportar **público** → `desktop/certs/chpay-signing.cer` (versionado en repo).
- Exportar **privado** → `.pfx` fuera del repo; ruta y contraseña en `secrets.local.ps1`.

### 1.2 Firmar en cada release

En `publish_desktop.ps1`, **después** de `build.bat` y **antes** de subir al servidor:

```powershell
signtool sign /fd SHA256 /f $env:CHPAY_SIGN_PFX /p $env:CHPAY_SIGN_PFX_PASS `
  /tr http://timestamp.digicert.com /td SHA256 `
  /d "CHPay Desktop" chpay.exe
signtool verify /pa /v chpay.exe
```

Variables en `secrets.local.ps1` (no versionadas):

```powershell
$env:CHPAY_SIGN_PFX      = "ruta\chpay-signing.pfx"
$env:CHPAY_SIGN_PFX_PASS = "..."
```

Requisito en máquina de build: Windows SDK (`signtool.exe`).

### 1.3 Entregables Fase 1

- [x] `desktop/scripts/create-signing-cert.ps1`
- [x] `desktop/scripts/sign-exe.ps1`
- [x] Paso de firma + verificación en `publish_desktop.ps1`
- [x] Documentar variables en `doc/actualizaciones.md`
- [x] **Generar certificado real** (`create-signing-cert.ps1`) y commitear `chpay-signing.cer`
- [x] Configurar `CHPAY_SIGN_PFX` / `CHPAY_SIGN_PFX_PASS` en `secrets.local.ps1`
- [ ] Prueba local: `scripts/test-sign-local.ps1` + ejecutar `chpay.exe`
- [ ] Primera publicación firmada + prueba OTA en TPV piloto

---

## Fase 2 — Confianza del certificado en el TPV (sin dominio)

### 2.1 Embeber el certificado público

- `//go:embed certs/chpay-signing.cer` en `desktop/trust_windows.go`.
- En build, el `.cer` embebido debe coincidir con la clave que firma el exe (mismo thumbprint).

### 2.2 Comprobar si está instalado

Función `trustCertInstalled() bool`:

- Abrir almacén `Cert:\LocalMachine\Root` (solo lectura, no requiere admin).
- Buscar por **thumbprint** del `.cer` embebido (no solo por CN, más robusto).

### 2.3 Instalar con elevación automática

Función `trustEnsureInstalled(parentWindow) error`:

1. Si `trustCertInstalled()` → return nil.
2. Mostrar diálogo Fyne: *“Para que Windows permita CHPay y sus actualizaciones, hay que instalar un certificado de confianza. Aparecerá el aviso de administrador (UAC).”*
3. Relanzar el **mismo exe** con:
   ```
   chpay.exe --install-trust-cert
   ```
   usando `ShellExecute` con verbo `runas` (dispara UAC; el usuario acepta o cancela).
4. Modo `--install-trust-cert` (solo en proceso elevado):
   - Escribir `.cer` embebido a temp.
   - `Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root` (o `certutil -addstore Root`).
   - Salir con código 0/1.
5. Proceso padre espera al hijo elevado; si éxito → continuar; si usuario cancela UAC → error claro (*“No se puede continuar sin instalar el certificado”*).

**Importante:** la app nunca exige “ejecutar como administrador” desde el icono; solo pide UAC en el momento necesario.

### 2.4 Puntos de integración

| Momento | Acción |
|---------|--------|
| **Arranque** (`main.go`, tras `configLoad`, antes de UI) | `trustEnsureInstalled()` — cubre primera copia manual del exe |
| **Antes de OTA** (`applyUpdate` en `update.go`, tras descargar, antes de lanzar `--upgrade`) | `trustEnsureInstalled()` — cumple requisito 2.2 explícitamente |
| **Actualización obligatoria** (`showMandatoryUpdate`) | Misma comprobación antes de descargar/aplicar |

Flujo OTA completo:

```
Descarga chpay-update.exe (firmado)
        ↓
trustEnsureInstalled()  ← comprobar / UAC si falta
        ↓
applyUpdate() → --upgrade → copiar → relanzar
```

Si el usuario rechaza UAC, no se aplica la actualización (y se muestra el motivo).

### 2.5 Entregables Fase 2

- [x] `desktop/trust_windows.go` (`//go:build windows`)
- [x] `desktop/trust_stub.go` (`//go:build !windows`)
- [x] Flag `--install-trust-cert` en `main.go`
- [x] Hook en arranque (`trustEnsureInstalled`) y en `applyUpdate`
- [x] Diálogo de explicación antes del UAC
- [ ] Regenerar `chpay-signing.cer` real (recompilar para embeber thumbprint correcto)

---

## Fase 3 — Rotación del certificado (cada ~5 años)

1. Generar nuevo par `.cer`/`.pfx`.
2. Sustituir `desktop/certs/chpay-signing.cer` embebido.
3. Publicar release firmada con la **nueva** clave.
4. En el primer arranque/OTA, `trustCertInstalled()` detectará el thumbprint nuevo → UAC → instala el `.cer` nuevo (el antiguo puede quedar en Root sin problema).

No hace falta lógica especial en OTA más allá de la comprobación por thumbprint ya prevista.

---

## Fase 4 — Pruebas (piloto obligatorio)

En un TPV **sin dominio**, con SAC activo:

```
[ ] Primera ejecución de chpay.exe firmado → UAC → cert en Root → app arranca
[ ] Segunda ejecución → sin UAC
[ ] OTA a nueva versión → comprueba cert (no UAC si ya instalado) → update OK
[ ] TPV sin cert (simular: borrar de Root) → OTA → UAC → update OK
[ ] Usuario cancela UAC → mensaje claro, no se aplica OTA
[ ] Usuario estándar (no admin permanente) puede usar la app tras aceptar UAC una vez
```

---

## Resumen

| Requisito | Cómo se cumple |
|-----------|----------------|
| 1. Firmar exe | Fase 1 — `signtool` en `publish_desktop.ps1` |
| 2.1 Sin dominio | Cert embebido + UAC local, sin GPO |
| 2.2 Comprobar en actualización | `trustEnsureInstalled()` antes de `applyUpdate` |
| 2.3 UAC automático | `ShellExecute` `runas` + `--install-trust-cert` |
| 2.4 Continuar instalación | Tras éxito del hijo elevado, seguir flujo OTA/arranque |

**Esfuerzo estimado restante:** generar cert + configurar secrets + piloto SAC (~0,5–1 día).

### Puesta en marcha (manual)

```powershell
# 1. Generar certificado (una vez) — YA HECHO si tienes .cer y .pfx
cd desktop\scripts
.\create-signing-cert.ps1

# 2. secrets.local.ps1 — YA HECHO si tienes CHPAY_SIGN_PFX

# 3. Prueba local (ANTES de publish)
cd desktop
.\scripts\test-sign-local.ps1
.\chpay.exe

# 4. Publicar cuando la prueba manual OK
.\publish_desktop.ps1 -Changelog "..."
```

**Alternativa comercial** (fuera de alcance mínimo): certificado EV de CA de pago elimina la necesidad de instalar cert en TPV, pero tiene coste anual.
