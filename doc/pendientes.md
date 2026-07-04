# Cambios pendientes

## Firma de código del Desktop (Windows)

**Estado:** pendiente de implementar.

### Problema

Windows 11 (Control Inteligente de aplicaciones / Smart App Control) puede bloquear
`chpay.exe` y las actualizaciones OTA porque el binario no está firmado ni tiene
reputación en la nube de Microsoft.

### Solución prevista (TPVs propios)

1. **Generar un certificado de firma de código autogenerado** (uso interno).
2. **Desplegar el certificado público** en todos los TPV (idealmente vía GPO:
   almacén “Entidades de certificación raíz de confianza” o “Editores de confianza”).
3. **Firmar cada `chpay.exe`** antes de publicar OTA (`signtool`, con sellado de
   tiempo para que siga válido tras caducar el certificado).
4. **Misma clave en todas las releases**; un exe publicado sin firmar volverá a
   bloquearse.

Instalar el certificado en los TPV **sin firmar el exe no sirve**. Firmar + cert
en confianza cubre instalación manual y OTA (`chpay-update.exe` en `%TEMP%`).

### Trabajo técnico a hacer

- [ ] Script para crear/exportar el certificado (`New-SelfSignedCertificate` o similar).
- [ ] Paso opcional de firma en `publish_desktop.ps1` (ruta/contraseña en
      `secrets.local.ps1`, no versionado).
- [ ] Documentar despliegue GPO para administradores de capítulo.
- [ ] Probar ciclo OTA completo en un TPV piloto con SAC activo.

### Alternativa comercial

Certificado EV/OV de una CA de pago (~100–500 €/año) si en el futuro hay TPVs fuera
del dominio o sin GPO.
