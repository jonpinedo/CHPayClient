---
name: chpay-desktop-release
description: Publica una nueva versión de CHPay Desktop (bump de versión, build, firma Authenticode, commit, push, publish OTA). Usar cuando el usuario pida subir versión, publicar desktop, hacer release, bump, publish_desktop, firmar exe, o commitear y publicar cambios de desktop.
---

# CHPay Desktop Release

## Resumen del sistema

| Qué | Dónde |
|-----|-------|
| Versión (`VERSION`, `VERSION_CODE`) | `desktop/build.bat` |
| Build | `desktop/build.bat` → `desktop/chpay.exe` (embebe `certs/chpay-signing.cer`) |
| Firma Authenticode | `desktop/scripts/sign-exe.ps1` (solo en publish o prueba local) |
| Prueba local build+firma | `desktop/scripts/test-sign-local.ps1` |
| Publicación OTA | `desktop/publish_desktop.ps1` (build + firma + upload) |
| Certificado | `desktop/certs/chpay-signing.cer` (público) + `.pfx` (secrets) |
| Secretos | `secrets.local.ps1` en la **raíz** (`CHPAY_PUBLISH_KEY`, `CHPAY_SIGN_PFX`, `CHPAY_SIGN_PFX_PASS`) |
| Confianza en TPV | `trust_windows.go` — UAC automático al arrancar / antes de OTA |
| Docs | `doc/actualizaciones.md`, `doc/pendientes.md`, `desktop/certs/README.md` |

`build.bat` **no firma** el exe. `publish_desktop.ps1` compila, firma y sube.

## Workflow estándar

```
Release Progress:
- [ ] 1. Cambios de código listos
- [ ] 2. Subir VERSION y VERSION_CODE en build.bat
- [ ] 3. Prueba local: test-sign-local.ps1 + ejecutar chpay.exe (UAC 1ª vez)
- [ ] 4. Commit (solo si el usuario lo pide)
- [ ] 5. Push (solo si el usuario lo pide)
- [ ] 6. publish_desktop.ps1 -Changelog "..."
```

### Certificado (setup inicial, una vez)

```powershell
cd desktop\scripts
.\create-signing-cert.ps1
```

En `secrets.local.ps1` (raíz):

```powershell
$env:CHPAY_PUBLISH_KEY = "..."
$env:CHPAY_SIGN_PFX = "...\desktop\certs\chpay-signing.pfx"
$env:CHPAY_SIGN_PFX_PASS = "..."
```

Commitear `desktop/certs/chpay-signing.cer` (público). **Nunca** el `.pfx`.

### Prueba local (obligatoria antes de publicar)

```powershell
cd desktop
.\scripts\test-sign-local.ps1
.\chpay.exe   # 1ª vez: diálogo confianza + UAC; 2ª vez: sin UAC
```

### Subir versión

Editar `desktop/build.bat`: `VERSION` y `VERSION_CODE` (+1 code siempre).

### Publicar

```powershell
cd desktop
.\publish_desktop.ps1 -Changelog "Descripción para el usuario."
```

Por defecto **no mandatory**. Firma falla si falta PFX en secrets.

### Commit / push

Solo si el usuario lo pide explícitamente. PowerShell: múltiples `-m`, no heredoc.

**No commitear:** `secrets.local.ps1`, `.pfx`, `*.exe`, `tools/`, `usbpcap/`.

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Build CGO falla | TDM-GCC-64 + `GOTOOLCHAIN=go1.22.12` |
| `signtool` no encontrado | Instalar Windows SDK (`winget install Microsoft.WindowsSDK.10.0.22621`) |
| Firma falla | `CHPAY_SIGN_PFX` / `CHPAY_SIGN_PFX_PASS` en secrets |
| SAC bloquea exe | Falta cert en Root → aceptar UAC al arrancar |
| `NotSigned` tras build.bat | Normal; ejecutar `test-sign-local.ps1` o publish |
| Thumbprint no coincide | Regenerar `.cer` y recompilar |
