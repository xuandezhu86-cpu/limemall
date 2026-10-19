# LimeMall seckill load-test helper: create N users and dump their JWT tokens to a CSV
# for the JMeter plan (infra/jmeter/seckill.jmx).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File make-seckill-tokens.ps1 -Users 200 -Prefix jm -Out ..\jmeter\seckill-tokens.csv
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [int]$Users = 200,
  [string]$Prefix = 'jm',
  [string]$Out = '',
  [string]$Gateway = 'http://localhost:8080',
  [string]$MysqlContainer = 'lm-mysql',
  [string]$DbPassword = 'LmDb2026'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $env:TEMP 'seckill-tokens'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Out) { $Out = Join-Path (Split-Path $PSScriptRoot -Parent) 'jmeter\seckill-tokens.csv' }

function Invoke-Sql([string]$sql) {
  $f = Join-Path $tmp 'stmt.sql'
  [System.IO.File]::WriteAllText($f, $sql, $utf8)
  cmd /c "docker exec -i -e MYSQL_PWD=$DbPassword $MysqlContainer mysql --default-character-set=utf8mb4 -uroot < `"$f`" 2>nul"
}

function Query-Sql([string]$sql) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    return (& docker exec -e "MYSQL_PWD=$DbPassword" $MysqlContainer mysql -uroot -N -e $sql 2>$null | Where-Object { $_ -and $_ -notmatch 'Warning|insecure' })
  } finally { $ErrorActionPreference = $prev }
}

function New-Token([string]$user) {
  $body = Join-Path $tmp 'login.json'
  [System.IO.File]::WriteAllText($body, ('{"username":"' + $user + '","password":"123"}'), $utf8)
  $resp = curl.exe -s -m 20 -X POST "$Gateway/users/login" -H 'Content-Type: application/json' -d "@$body"
  try { return ($resp | ConvertFrom-Json).token } catch { return $null }
}

Write-Host "[1/2] creating $Users users with prefix '$Prefix' ..."
$hash = (Query-Sql "SELECT password FROM ``lm_user``.``user`` WHERE id=1;") -join ''
if (-not $hash) { throw 'cannot read the bcrypt hash of the seed user' }
$batch = 200
for ($start = 1; $start -le $Users; $start += $batch) {
  $end = [math]::Min($start + $batch - 1, $Users)
  $rows = @()
  for ($i = $start; $i -le $end; $i++) {
    $name = '{0}_{1:D4}' -f $Prefix, $i
    $phone = '138' + ('{0:D8}' -f $i)
    $rows += "('$name','$hash','$phone',1,100000,'2024-05-01 10:00:00','2024-05-01 10:00:00')"
  }
  Invoke-Sql ("INSERT IGNORE INTO ``lm_user``.``user`` (username,password,phone,status,balance,create_time,update_time) VALUES " + ($rows -join ',') + ';')
}
Write-Host "      users ready"

Write-Host "[2/2] logging in to collect tokens (this is the slow part) ..."
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('userId,token')
$ok = 0
for ($i = 1; $i -le $Users; $i++) {
  $name = '{0}_{1:D4}' -f $Prefix, $i
  $token = New-Token $name
  if (-not $token) { Write-Warning "login failed for $name, skipped"; continue }
  [void]$lines.Add("$name,$token")
  $ok++
  if ($ok % 50 -eq 0) { Write-Host ("      $ok/$Users ...") }
}
[System.IO.File]::WriteAllLines($Out, $lines.ToArray(), $utf8)
Write-Host ("      wrote {0} tokens -> {1}" -f $ok, $Out)
