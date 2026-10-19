# LimeMall seckill anti-oversell concurrency check (Windows / PowerShell)
#
# What it does:
#   1. creates N test users (reusing the BCrypt hash of user "jack")
#   2. resets the activity stock to M, clears previous seckill orders + Redis caches, warms up
#   3. fires N concurrent seckill requests with curl --parallel
#   4. verifies: orders == M ? db stock == 0 ? redis stock == 0 ? buyers == M ?
#
# Usage: powershell -ExecutionPolicy Bypass -File seckill-concurrency-check.ps1 -Users 60 -Stock 20
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [int]$Users = 60,
  [int]$Stock = 20,
  [long]$ActivityId = 1001,
  [string]$Gateway = 'http://localhost:8080',
  [string]$MysqlContainer = 'lm-mysql',
  [string]$RedisContainer = 'lm-redis',
  [string]$DbPassword = 'LmDb2026'
)

$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP 'seckill-check'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Invoke-Sql([string]$sql) {
  $f = Join-Path $tmp 'stmt.sql'
  [System.IO.File]::WriteAllText($f, $sql, $utf8)
  cmd /c "docker exec -i -e MYSQL_PWD=$DbPassword $MysqlContainer mysql --default-character-set=utf8mb4 -uroot < `"$f`" 2>nul"
}

function Query-Sql([string]$sql) {
  # Pass the password through MYSQL_PWD: otherwise the mysql client writes a
  # "Using a password" warning to stderr and PowerShell (ErrorActionPreference=Stop)
  # treats it as a fatal error.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & docker exec -e "MYSQL_PWD=$DbPassword" $MysqlContainer mysql -uroot -N -e $sql 2>$null
    return ($out | Where-Object { $_ -and $_ -notmatch 'Warning|insecure' })
  } finally { $ErrorActionPreference = $prev }
}

function New-Token([string]$user) {
  $body = Join-Path $tmp 'login.json'
  [System.IO.File]::WriteAllText($body, ('{"username":"' + $user + '","password":"123"}'), $utf8)
  $resp = curl.exe -s -m 20 -X POST "$Gateway/users/login" -H 'Content-Type: application/json' -d "@$body"
  try { return ($resp | ConvertFrom-Json).token } catch { return $null }
}

Write-Host "[1/4] creating $Users test users ..."
$hash = (Query-Sql "SELECT password FROM ``lm_user``.``user`` WHERE id=1;") -join ''
if (-not $hash) { throw 'cannot read the bcrypt hash of the seed user' }
$rows = @()
for ($i = 1; $i -le $Users; $i++) {
  $name = 'lm_u{0:D3}' -f $i
  $phone = '139' + ('{0:D8}' -f $i)
  $rows += "('$name','$hash','$phone',1,100000,'2024-05-01 10:00:00','2024-05-01 10:00:00')"
}
Invoke-Sql ("INSERT IGNORE INTO ``lm_user``.``user`` (username,password,phone,status,balance,create_time,update_time) VALUES " + ($rows -join ',') + ';')

Write-Host "[2/4] resetting activity stock to $Stock and clearing old data ..."
Invoke-Sql "UPDATE ``lm_seckill``.seckill_activity SET total_stock=$Stock, available_stock=$Stock WHERE id=$ActivityId; DELETE FROM ``lm_seckill``.seckill_order WHERE activity_id=$ActivityId;"
& docker exec $RedisContainer redis-cli -n 1 DEL "seckill:stock:$ActivityId" "seckill:buyers:$ActivityId" "seckill:bucket:$ActivityId" | Out-Null

$adminToken = New-Token 'jack'
if (-not $adminToken) { throw 'login failed, please make sure user-service is running' }
curl.exe -s -m 20 -X POST "$Gateway/seckill/activity/$ActivityId/warmup" -H "authorization: $adminToken" | Out-Null
Write-Host ("     redis stock after warmup = " + (& docker exec $RedisContainer redis-cli -n 1 GET "seckill:stock:$ActivityId"))

Write-Host "[3/4] firing $Users concurrent seckill requests ..."
$cfg = Join-Path $tmp 'parallel.conf'
$blocks = @()
$tokens = 0
foreach ($i in 1..$Users) {
  $name = 'lm_u{0:D3}' -f $i
  $token = New-Token $name
  if (-not $token) { Write-Warning "login failed for $name, skipped"; continue }
  $tokens++
  # One block per request, separated by "next": in a curl config file, list options
  # such as header keep accumulating across blocks, so without "next" the 60th request
  # would carry 60 authorization headers and the gateway would answer 431
  # (Request Header Fields Too Large).
  $block = @(
    "url = `"$Gateway/seckill/$ActivityId`"",
    'request = "POST"',
    "header = `"authorization: $token`"",
    'output = "NUL"'
  ) -join "`r`n"
  $blocks += $block
}
[System.IO.File]::WriteAllText($cfg, ($blocks -join "`r`nnext`r`n"), $utf8)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$codes = curl.exe -s -K $cfg --parallel --parallel-immediate --parallel-max $Users -w "%{http_code}\n"
$sw.Stop()
Write-Host ("     tokens=$tokens, elapsed={0:N2}s (per-request codes are not captured in parallel mode; the DB/Redis figures below are authoritative)" -f $sw.Elapsed.TotalSeconds)

Write-Host "[4/4] verifying (expect stock=$Stock -> exactly $Stock orders, no oversell) ..."
Start-Sleep -Seconds 5
$orders = (Query-Sql "SELECT COUNT(*) FROM ``lm_seckill``.seckill_order WHERE activity_id=$ActivityId;") -join ''
$dbStock = (Query-Sql "SELECT available_stock FROM ``lm_seckill``.seckill_activity WHERE id=$ActivityId;") -join ''
$redisStock = (& docker exec $RedisContainer redis-cli -n 1 GET "seckill:stock:$ActivityId")
$buyers = (& docker exec $RedisContainer redis-cli -n 1 SCARD "seckill:buyers:$ActivityId")
$pending = (Query-Sql "SELECT COUNT(*) FROM ``lm_seckill``.seckill_order WHERE activity_id=$ActivityId AND status=0;") -join ''
$soldItems = (Query-Sql "SELECT COUNT(*) FROM ``lm_seckill``.seckill_order WHERE activity_id=$ActivityId;") -join ''

$pass = ($orders -eq "$Stock") -and ($dbStock -eq '0') -and ($redisStock -eq '0') -and ($buyers -eq "$Stock")
Write-Host ''
Write-Host ("  seckill orders      = {0}   (expect {1})" -f $orders, $Stock)
Write-Host ("  activity stock (DB) = {0}   (expect 0)" -f $dbStock)
Write-Host ("  redis stock         = {0}   (expect 0)" -f $redisStock)
Write-Host ("  redis buyers        = {0}   (expect {1})" -f $buyers, $Stock)
Write-Host ("  pending orders      = {0}   (expect 0; >0 means async writes still in flight)" -f $pending)
Write-Host ''
if ($pass) { Write-Host 'RESULT: PASS - no oversell under concurrency.' -ForegroundColor Green }
else { Write-Host 'RESULT: CHECK FAILED - inspect the numbers above.' -ForegroundColor Yellow }
