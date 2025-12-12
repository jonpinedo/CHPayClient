# Script para configurar port forwarding de Windows a WSL
# EJECUTAR COMO ADMINISTRADOR

Write-Host "Configurando port forwarding puerto 443..." -ForegroundColor Cyan

# Agregar port forwarding
netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=443 connectaddress=127.0.0.1

# Verificar configuracion
Write-Host "`nConfiguracion actual de port proxy:" -ForegroundColor Green
netsh interface portproxy show all

# Verificar que el puerto esta abierto
Write-Host "`nPort forwarding configurado correctamente!" -ForegroundColor Green
Write-Host "Ahora el puerto 443 esta disponible desde cualquier interfaz de red" -ForegroundColor Yellow

# Informacion adicional
Write-Host "`nPara eliminar el port forwarding mas tarde, ejecuta:" -ForegroundColor Cyan
Write-Host "netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0" -ForegroundColor White

Write-Host "`nPresiona cualquier tecla para continuar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
