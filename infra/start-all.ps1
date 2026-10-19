# limemall one-click start (Windows / PowerShell)
# Starts: docker middleware -> nacos configs -> gateway + 5 business services
# Usage: powershell -ExecutionPolicy Bypass -File start-all.ps1
# NOTE: ASCII only, Windows PowerShell reads .ps1 as ANSI when there is no BOM.
$ErrorActionPreference = 'Stop'

$Infra = $PSScriptRoot
# infra/ lives inside the project root, so the project root is simply infra's parent
$Root  = Split-Path -Parent $Infra
if (-not (Test-Path (Join-Path $Root 'pom.xml'))) { throw "project root not found: $Root has no pom.xml" }
# JDK/Maven are toolchain, kept OUTSIDE the repo: <project-parent>\tools
$Tools = Join-Path (Split-Path -Parent $Root) 'tools'
$Jdk   = Join-Path $Tools 'jdk\jdk-11.0.32.1+1'
if (-not (Test-Path $Jdk)) {
  $jdkHome = Join-Path $Tools 'jdk'
  if (Test-Path $jdkHome) { $Jdk = (Get-ChildItem $jdkHome -Directory | Select-Object -First 1).FullName }
  elseif ($env:JAVA_HOME) { $Jdk = $env:JAVA_HOME }
  else { throw "JDK not found: expected $jdkHome\<version> or JAVA_HOME" }
}
$Mvn   = Join-Path $Tools 'mvn\apache-maven-3.9.9\bin\mvn.cmd'
if (-not (Test-Path $Mvn)) { $Mvn = 'mvn' }
$Settings = Join-Path $Tools 'settings.xml'
$Compose  = Join-Path $Infra 'docker-compose.yml'

$Services = @(
  @{ name = 'lm-gateway';     port = 8080 },
  @{ name = 'item-service';   port = 8081 },
  @{ name = 'cart-service';   port = 8082 },
  @{ name = 'user-service';   port = 8084 },
  @{ name = 'trade-service';  port = 8085 },
  @{ name = 'pay-service';    port = 8086 },
  @{ name = 'seckill-service'; port = 8087 }
)

function Wait-Port([int]$Port, [int]$TimeoutSec) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
      $null = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
      Start-Sleep -Milliseconds 300
      if ($c.Connected) { return $true }
    } catch { } finally { $c.Close() }
    Start-Sleep -Seconds 2
  }
  return $false
}

# ---------- 0. toolchain ----------
if (-not (Test-Path $Jdk)) { throw "JDK not found: $Jdk" }
$env:JAVA_HOME = $Jdk

# ---------- 1. docker middleware ----------
Write-Host '[1/5] checking docker...'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
docker ps | Out-Null
$dockerOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prev
if (-not $dockerOk) {
  Write-Host '     Docker Desktop is not running, starting it...'
  Start-Process 'C:\Users\Admin\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe' -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $ErrorActionPreference = 'Continue'; docker ps | Out-Null; $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev
    if ($ok) { break }
  }
  if (-not $ok) { throw 'Docker Desktop did not become ready' }
}

Write-Host '[2/5] starting middleware containers...'
docker compose -f $Compose up -d
if (-not (Wait-Port 8848 180)) { throw 'Nacos (8848) not ready' }
Write-Host '     waiting for MySQL to accept connections...'
if (-not (Wait-Port 3306 180)) { throw 'MySQL (3306) not ready' }

# RabbitMQ vhost named "/limemall" (note the leading slash) + delayed-message plugin
Start-Sleep -Seconds 8
docker exec lm-mq rabbitmqctl add_vhost "/limemall" 2>$null | Out-Null
docker exec lm-mq rabbitmqctl set_permissions -p "/limemall" limemall ".*" ".*" ".*" 2>$null | Out-Null

# ---------- 3. nacos configs (idempotent) ----------
Write-Host '[3/5] publishing Nacos configs...'
$cfgDir = Join-Path $Infra 'nacos-configs'
$api = 'http://localhost:8848/nacos/v1/cs/configs'
$map = @(
  @{ f = 'shared-jdbc.yaml';    t = 'yaml' },
  @{ f = 'shared-log.yaml';     t = 'yaml' },
  @{ f = 'shared-swagger.yaml'; t = 'yaml' },
  @{ f = 'shared-seata.yaml';   t = 'yaml' },
  @{ f = 'cart-service.yaml';   t = 'yaml' },
  @{ f = 'gateway-routes.json'; t = 'json' }
)
foreach ($m in $map) {
  $r = curl.exe -s -X POST $api --data-urlencode "dataId=$($m.f)" --data-urlencode 'group=DEFAULT_GROUP' --data-urlencode "type=$($m.t)" --data-urlencode "content@$cfgDir\$($m.f)"
  Write-Host ("      {0,-22} {1}" -f $m.f, $r)
}

# ---------- 4. build ----------
$jarMissing = $false
foreach ($s in $Services) { if (-not (Test-Path (Join-Path $Root "$($s.name)\target\$($s.name).jar"))) { $jarMissing = $true } }
if ($jarMissing) {
  Write-Host '[4/5] building jars (first run, may take a few minutes)...'
  & $Mvn -s $Settings -f (Join-Path $Root 'pom.xml') -DskipTests clean package
} else {
  Write-Host '[4/5] jars already built, skip (delete */target to force rebuild)'
}

# ---------- 5. services ----------
Write-Host '[5/5] starting services...'
foreach ($s in $Services) {
  $running = $false
  $c = New-Object System.Net.Sockets.TcpClient
  try { $null = $c.BeginConnect('127.0.0.1', $s.port, $null, $null); Start-Sleep -Milliseconds 200; $running = $c.Connected } catch { } finally { $c.Close() }
  if ($running) { Write-Host ("      {0} already on port {1}" -f $s.name, $s.port); continue }
  Start-Process -FilePath 'powershell' -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Infra 'run-service.ps1'), $s.name) -WorkingDirectory (Join-Path $Root $s.name) -WindowStyle Hidden
  Write-Host ("      launched {0}" -f $s.name)
  Start-Sleep -Seconds 4
}

$failed = @()
foreach ($s in $Services) {
  if (Wait-Port $s.port 180) { Write-Host ("      {0} up on {1}" -f $s.name, $s.port) }
  else { $failed += $s; Write-Warning ("      {0} did NOT come up on port {1}, check logs\{0}\spring.log" -f $s.name, $s.port) }
}

# Retry once: when 7 services boot at the same time the Nacos gRPC client can time out
# (Client not connected / Waited 3000 ms) and the application aborts its startup.
if ($failed.Count -gt 0) {
  Write-Host ''
  Write-Host ("retrying {0} service(s) that failed to start..." -f $failed.Count)
  foreach ($s in $failed) {
    Start-Process -FilePath 'powershell' -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Infra 'run-service.ps1'), $s.name) -WorkingDirectory (Join-Path $Root $s.name) -WindowStyle Hidden
    Write-Host ("      relaunched {0}" -f $s.name)
    Start-Sleep -Seconds 4
  }
  foreach ($s in $failed) {
    if (Wait-Port $s.port 180) { Write-Host ("      {0} up on {1}" -f $s.name, $s.port) }
    else { Write-Warning ("      {0} STILL down on port {1}" -f $s.name, $s.port) }
  }
}

Write-Host ''
Write-Host 'Done. URLs:'
Write-Host '  portal        http://localhost:18080   (jack / 123)'
Write-Host '  admin         http://localhost:18081'
Write-Host '  ops admin     http://localhost:18082'
Write-Host '  gateway       http://localhost:8080'
Write-Host '  nacos         http://localhost:8848/nacos   (nacos / nacos)'
Write-Host '  rabbitmq      http://localhost:15672        (limemall / LmMq2026)'
Write-Host '  sentinel      http://localhost:8090         (sentinel / sentinel)'
Write-Host '  seata console http://localhost:7091         (seata / seata)'
