---
name: chpay-release
description: Publica versiones de CHPay (Desktop y/o Android): bump, build, firma, commit, push y publish OTA. Usar cuando el usuario pida publicar, release, bump, publish_desktop, publish_apk, subir versión, o publicar desktop/android.
---

# CHPay Release (Desktop + Android)

## Alcance según la petición

| Petición del usuario | Qué publicar |
|----------------------|--------------|
| "publicar" / "release" **sin** especificar plataforma | Las plataformas **donde haya cambios** en el working tree / commits pendientes (`desktop/` → Desktop; `lib/`, `android/`, `pubspec.yaml` → Android; ambos si hay en los dos) |
| "publicar desktop" / `publish_desktop` | Solo Desktop |
| "publicar android" / `publish_apk` | Solo Android |
| "compilar" / "build" **sin** pedir publicar | Solo build local. **No** commit, **no** push, **no** publish |

Si al pedir publicar no hay cambios en ninguna plataforma, preguntar qué quiere publicar.

## Regla commit / push

- **Publicar** implica producción → **siempre** commit + push **antes** del publish OTA (incluido el bump de versión).
- **Solo compilar** → no commit, no push, no publish.
- PowerShell: mensajes de commit con múltiples `-m`, no heredoc bash.

**No commitear:** `secrets.local.ps1`, `.pfx`, `*.exe`, `*.apk`, `tools/`, `usbpcap/`, `build/`.

---

## Resumen del sistema

| Qué | Desktop | Android |
|-----|---------|---------|
| Versión | `desktop/build.bat` (`VERSION`, `VERSION_CODE`) | `pubspec.yaml` (`version: X.Y.Z+N`) |
| Build | `desktop/build.bat` → `chpay.exe` | `flutter build apk --release` |
| Firma | Authenticode (`sign-exe.ps1`) | N/A |
| Prueba local | `desktop/scripts/test-sign-local.ps1` | `flutter build apk --release` |
| Publish OTA | `desktop/publish_desktop.ps1` | `.\publish_apk.ps1` (raíz) |
| Secretos | `secrets.local.ps1` en la raíz (`CHPAY_PUBLISH_KEY`, `CHPAY_SIGN_PFX`, `CHPAY_SIGN_PFX_PASS`) | misma `CHPAY_PUBLISH_KEY` |
| Docs | `doc/actualizaciones.md`, `desktop/certs/README.md` | `doc/actualizaciones.md` |

`build.bat` **no firma** el exe. `publish_desktop.ps1` compila, firma y sube.

---

## Workflow al publicar

```
Release Progress:
- [ ] 1. Detectar plataformas a publicar (petición o archivos tocados)
- [ ] 2. Bump de versión en cada plataforma afectada
- [ ] 3. Prueba local (Desktop: test-sign-local; Android: build apk ok)
- [ ] 4. Commit (siempre, porque se va a publicar)
- [ ] 5. Push (siempre, porque se va a publicar)
- [ ] 6. publish_desktop.ps1 y/o publish_apk.ps1 con -Changelog
```

### Detectar plataformas por cambios

Considerar Desktop si hay cambios bajo `desktop/` (código o `build.bat`).  
Considerar Android si hay cambios bajo `lib/`, `android/`, o en `pubspec.yaml`.  
Ignorar solo-docs / solo-skill salvo que el usuario pida publicar igual.

### Bump de versión

**Desktop** — editar `desktop/build.bat`:
```bat
set VERSION=X.Y.Z
set VERSION_CODE=N
```
(+1 a `VERSION_CODE` siempre; subir patch de `VERSION` salvo indicación contraria).

**Android** — editar `pubspec.yaml`:
```yaml
version: X.Y.Z+N   # versionName+versionCode
```
(+1 a `N` siempre).

### Prueba local Desktop (antes de publish)

```powershell
cd desktop
.\scripts\test-sign-local.ps1
.\chpay.exe   # 1ª vez: diálogo confianza + UAC; 2ª vez: sin UAC
```

### Commit + push (obligatorio antes de publish)

```powershell
git add <archivos relevantes>
git commit -m "tipo: resumen" -m "Detalle opcional."
git push -u origin HEAD
```

### Publicar Desktop

```powershell
cd desktop
.\publish_desktop.ps1 -Changelog "Descripción para el usuario."
```

Por defecto **no mandatory**. Firma falla si falta PFX en secrets.

### Publicar Android

```powershell
# desde la raíz del repo
.\publish_apk.ps1 -Changelog "Descripción para el usuario."
```

Requisitos: Flutter en PATH, Samba `\\truenas\compartido\apk-releases`, `CHPAY_PUBLISH_KEY`.

---

## Certificado Desktop (setup inicial, una vez)

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

---

## Troubleshooting

| Problema | Solución |
|----------|----------|
| Build CGO falla | TDM-GCC-64 + `GOTOOLCHAIN=go1.22.12` |
| `signtool` no encontrado | Instalar Windows SDK (`winget install Microsoft.WindowsSDK.10.0.22621`) |
| Firma falla | `CHPAY_SIGN_PFX` / `CHPAY_SIGN_PFX_PASS` en secrets |
| SAC bloquea exe | Falta cert en Root → aceptar UAC al arrancar |
| `NotSigned` tras build.bat | Normal; ejecutar `test-sign-local.ps1` o publish |
| Thumbprint no coincide | Regenerar `.cer` y recompilar |
| Samba APK no disponible | Montar `\\truenas\compartido\apk-releases` |
