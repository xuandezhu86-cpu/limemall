# limemall microservice launcher (Windows / PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File run-service.ps1 <module-dir-name> [-Port <n>]
#   e.g. run-service.ps1 lm-gateway
#        run-service.ps1 item-service
#        run-service.ps1 item-service -Port 8088     # second instance for cache tests
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [Parameter(Mandatory = $true)][string]$Module,
  # Start an extra instance on another port: the management port (business port + 1000)
  # is also overridden, otherwise the second instance would fail with
  # "Web server failed to start. Port 9081 was already in use."
  [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

# infra/ lives inside the project root, so the project root is simply infra's parent
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root 'pom.xml'))) { throw "project root not found: $Root has no pom.xml" }

# JDK/Maven are toolchain, kept OUTSIDE the repo: <project-parent>\tools
$Tools = Join-Path (Split-Path -Parent $Root) 'tools'
$Jdk = Join-Path $Tools 'jdk\jdk-11.0.32.1+1'
if (-not (Test-Path $Jdk)) {
  $jdkHome = Join-Path $Tools 'jdk'
  if (Test-Path $jdkHome) { $Jdk = (Get-ChildItem $jdkHome -Directory | Select-Object -First 1).FullName }
  elseif ($env:JAVA_HOME) { $Jdk = $env:JAVA_HOME }
  else { throw "JDK not found: expected $jdkHome\<version> or JAVA_HOME" }
}
$env:JAVA_HOME = $Jdk

$moduleDir = Join-Path $Root $Module
$jar = Join-Path $moduleDir "target\$Module.jar"
if (-not (Test-Path $jar)) { throw "jar not found: $jar (run 'mvn -DskipTests clean package' first)" }

Set-Location $moduleDir
Write-Host "[limemall] starting $Module from $jar"
# Heap is capped on purpose: a dev machine runs 10+ JVMs (services + extra instances),
# without -Xmx each one grabs ~1GB of RSS and the box starts swapping.
# Override with: $env:LM_JAVA_OPTS = '-Xmx1g' before calling this script.
$heap = if ($env:LM_JAVA_OPTS) { $env:LM_JAVA_OPTS } else { '-Xms256m -Xmx512m' }
$extra = @()
if ($Port -gt 0) {
  $mgmt = $Port + 1000
  $extra = @("--server.port=$Port", "--management.server.port=$mgmt")
  Write-Host "[limemall] override ports: server=$Port management=$mgmt"
}
# -D arguments MUST be quoted, otherwise PowerShell splits them at the dot.
& (Join-Path $Jdk 'bin\java.exe') '-Dfile.encoding=UTF-8' '-Duser.timezone=Asia/Shanghai' $heap.Split(' ') -jar $jar @extra
