# limemall stop script (Windows / PowerShell)
# Usage:
#   powershell -ExecutionPolicy Bypass -File stop-all.ps1          # stop java services only
#   powershell -ExecutionPolicy Bypass -File stop-all.ps1 -All     # also stop containers
# NOTE: ASCII only.
param([switch]$All)

$Infra = $PSScriptRoot
$ports = @(8080, 8081, 8082, 8084, 8085, 8086, 8087, 8088)

foreach ($p in $ports) {
  $procId = (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)
  if ($procId) {
    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    Write-Host "stopped service on port $p (pid $procId)"
  }
}

if ($All) {
  docker compose -f (Join-Path $Infra 'docker-compose.yml') down
  Write-Host 'containers stopped (data volumes kept)'
}
