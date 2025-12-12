# Script para actualizar portproxy con la IP actual de WSL
# EJECUTAR COMO ADMINISTRADOR

# Obtener IP actual de WSL
$wslIP = (wsl hostname -I).Trim().Split()[0]
Write-Host "IP de WSL detectada: $wslIP" -ForegroundColor Green

# Eliminar reglas antiguas
Write-Host "`nEliminando reglas antiguas..." -ForegroundColor Yellow
netsh interface portproxy delete v4tov4 listenport=80 listenaddress=0.0.0.0
netsh interface portproxy delete v4tov4 listenport=443 listenaddress=0.0.0.0

# Agregar nuevas reglas
Write-Host "`nAgregando nuevas reglas..." -ForegroundColor Yellow
netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=80 connectaddress=$wslIP
netsh interface portproxy add v4tov4 listenport=443 listenaddress=0.0.0.0 connectport=443 connectaddress=$wslIP

# Mostrar reglas actuales
Write-Host "`nReglas de portproxy configuradas:" -ForegroundColor Green
netsh interface portproxy show all

Write-Host "`n✅ Portproxy actualizado correctamente" -ForegroundColor Green
Write-Host "Dispositivos en la red pueden acceder a través de 192.168.1.146" -ForegroundColor Cyan
