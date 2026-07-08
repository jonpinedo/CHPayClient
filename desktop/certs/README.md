# Certificado de firma CHPay Desktop

| Fichero | Versionar | Uso |
|---------|-----------|-----|
| `chpay-signing.cer` | Sí | Público; embebido en el exe para instalación de confianza en TPVs |
| `chpay-signing.pfx` | **No** | Clave privada; solo máquina de build (`secrets.local.ps1`) |

Generar ambos:

```powershell
cd desktop\scripts
.\create-signing-cert.ps1
```

Añadir en `secrets.local.ps1` (raíz del repo):

```powershell
$env:CHPAY_SIGN_PFX = "T:\...\desktop\certs\chpay-signing.pfx"
$env:CHPAY_SIGN_PFX_PASS = "..."
```

### Prueba local (antes de publicar)

```powershell
cd desktop
.\scripts\test-sign-local.ps1
```

Compila, firma y verifica el exe **sin subir al servidor**. Luego ejecutar `.\chpay.exe` y validar el flujo UAC del certificado de confianza (ver checklist abajo).

Tras regenerar el `.cer`, recompilar obligatorio para que el thumbprint embebido coincida con la clave de firma.

### Checklist prueba manual

```
[ ] test-sign-local.ps1 → firma Valid
[ ] Primera ejecución chpay.exe → diálogo + UAC → app arranca
[ ] Segunda ejecución → sin UAC
[ ] (Opcional) OTA de prueba tras publicar en entorno de test
```
