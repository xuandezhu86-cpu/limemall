# limemall microservice launcher (Windows / PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File run-service.ps1 <module-dir-name>
#   e.g. run-service.ps1 lm-gateway
#        run-service.ps1 item-service
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [Parameter(Mandatory = $true)][string]$Module
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
# -D arguments MUST be quoted, otherwise PowerShell splits them at the dot.
& (Join-Path $Jdk 'bin\java.exe') '-Dfile.encoding=UTF-8' '-Duser.timezone=Asia/Shanghai' -jar $jar
