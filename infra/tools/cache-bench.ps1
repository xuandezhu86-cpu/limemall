# LimeMall multi-level cache verification (Windows / PowerShell)
#
# Covers:
#   1. latency: cached read (/items/{id}) vs direct DB read (/items/db/{id})
#   2. cache stats: L1/L2 hit counters, db loads, bloom rejects
#   3. penetration: repeated requests for a NON-existing id must not hit the DB
#   4. breakdown: after invalidating, N concurrent requests must trigger exactly ONE db load
#   5. cross-instance consistency: update on instance B must invalidate instance A's local cache
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File cache-bench.ps1
#   powershell -ExecutionPolicy Bypass -File cache-bench.ps1 -A http://localhost:8081 -B http://localhost:8088
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [string]$A = 'http://localhost:8081',
  [string]$B = 'http://localhost:8088',
  [long]$ItemId = 1,
  [int]$Rounds = 150,
  [int]$Concurrent = 60,
  [string]$RedisContainer = 'lm-redis'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$tmp = Join-Path $env:TEMP 'cache-bench'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Measure-Url([string]$url, [int]$count) {
  # one curl process, N sequential transfers: avoids process-start overhead in the numbers
  $curlArgs = @()
  for ($i = 0; $i -lt $count; $i++) { $curlArgs += @('-o', 'NUL', '-w', '%{time_total}\n', $url) }
  $out = & curl.exe -s @curlArgs
  $times = @($out | Where-Object { $_ -match '^\d' } | ForEach-Object { [double]$_ * 1000 })
  if ($times.Count -eq 0) { return $null }
  $sorted = $times | Sort-Object
  return [pscustomobject]@{
    count = $times.Count
    avg   = [math]::Round(($times | Measure-Object -Average).Average, 2)
    p50   = [math]::Round($sorted[[int][math]::Floor($sorted.Count * 0.50)], 2)
    p95   = [math]::Round($sorted[[int][math]::Floor($sorted.Count * 0.95)], 2)
    max   = [math]::Round($sorted[-1], 2)
  }
}

function Get-Stats([string]$base) {
  return (curl.exe -s -m 10 "$base/items/cache/stats" | ConvertFrom-Json)
}

function Show-Stats($s, [string]$tag) {
  Write-Host ("    {0}: L1 hit={1} miss={2} | L2 hit={3} miss={4} | dbLoads={5} bloomRejects={6} nullCached={7} lockRebuild={8} lockSpin={9}" -f `
    $tag, $s.l1.hit, $s.l1.miss, $s.l2.hit, $s.l2.miss, $s.db.loads, $s.db.bloomRejects, $s.db.nullCached, $s.db.lockRebuilds, $s.db.lockSpins)
}

function Get-BloomBits([long]$id, [long]$bitSize, [int]$hashCount) {
  # mirror the Java BloomFilterService: MD5 digest -> 4 x 32-bit hashes -> mod bitSize
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $digest = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$id))
  $bits = @()
  for ($i = 0; $i -lt $hashCount; $i++) {
    $o = $i * 4
    $h = ([long]$digest[$o] -shl 24) -bor ([long]$digest[$o + 1] -shl 16) -bor ([long]$digest[$o + 2] -shl 8) -bor [long]$digest[$o + 3]
    $bits += [long]([math]::Abs($h % $bitSize))
  }
  return $bits
}

Write-Host '=============================================================='
Write-Host ' LimeMall multi-level cache verification'
Write-Host ("  instance A = {0}   instance B = {1}" -f $A, $B)
Write-Host '=============================================================='

# ---------- 0. warm up ----------
Write-Host ''
Write-Host '[0] warm up ...'
& curl.exe -s -m 10 -o NUL "$A/items/$ItemId" | Out-Null
& curl.exe -s -m 10 -o NUL "$A/items/$ItemId" | Out-Null
$s0 = Get-Stats $A
Show-Stats $s0 'before'

# ---------- 1. latency ----------
Write-Host ''
Write-Host ("[1] latency: {0} sequential requests each" -f $Rounds)
$cached = Measure-Url "$A/items/$ItemId" $Rounds
$direct = Measure-Url "$A/items/db/$ItemId" $Rounds
Write-Host ("    cached  /items/{0}      avg={1}ms p50={2}ms p95={3}ms max={4}ms" -f $ItemId, $cached.avg, $cached.p50, $cached.p95, $cached.max)
Write-Host ("    direct  /items/db/{0}   avg={1}ms p50={2}ms p95={3}ms max={4}ms" -f $ItemId, $direct.avg, $direct.p50, $direct.p95, $direct.max)
if ($direct.avg -gt 0) {
  Write-Host ("    => cached is {0}x faster on average" -f [math]::Round($direct.avg / [math]::Max($cached.avg, 0.01), 1))
}

# ---------- 2. penetration ----------
Write-Host ''
Write-Host '[2] penetration: requesting NON-existing ids'
$before = Get-Stats $A
$ghost1 = 99999991
& curl.exe -s @(1..50 | ForEach-Object { "-o"; "NUL"; "$A/items/$ghost1" }) | Out-Null
$afterBloom = Get-Stats $A
Write-Host ("    layer 1 bloom filter : dbLoads +{0} (expect +0), bloomRejects +{1}, L1 hit +{2}" -f `
    ($afterBloom.db.loads - $before.db.loads), ($afterBloom.db.bloomRejects - $before.db.bloomRejects), ($afterBloom.l1.hit - $before.l1.hit))
Write-Host '             the 1st request is rejected by the bloom filter, the other 49 are served by the null cache in L1'

# Force a bloom FALSE POSITIVE for another ghost id: set exactly the bits the filter would hash to.
# The filter then answers "maybe exists", so the request falls through to the DB / null cache,
# which is what layer 2 (null caching) has to handle.
$ghost2 = 88888888
$bitSize = 16777216
# NOTE: PowerShell variable names are case-INsensitive, so this loop must NOT use $b
# (that would overwrite the $B base URL of instance B).
foreach ($bit in (Get-BloomBits $ghost2 $bitSize 4)) {
  & docker exec $RedisContainer redis-cli -n 0 SETBIT item:bloom $bit 1 | Out-Null
}
& docker exec $RedisContainer redis-cli -n 0 DEL "item:cache:$ghost2" | Out-Null
$before2 = Get-Stats $A
& curl.exe -s @(1..50 | ForEach-Object { "-o"; "NUL"; "$A/items/$ghost2" }) | Out-Null
$afterNull = Get-Stats $A
Write-Host ("    layer 2 null cache   : dbLoads +{0} (expect +1: only the first request), nullCached +{1}, L1 hit +{2}" -f `
    ($afterNull.db.loads - $before2.db.loads), ($afterNull.db.nullCached - $before2.db.nullCached), ($afterNull.l1.hit - $before2.l1.hit))
Write-Host '             bloom said "maybe", DB said "no such row", the empty result is cached for 60s so the DB is hit only once'
& curl.exe -s -m 10 -X POST -o NUL "$A/items/cache/bloom/rebuild" | Out-Null
Write-Host '    bloom filter rebuilt'

# ---------- 3. breakdown ----------
Write-Host ''
Write-Host ("[3] breakdown: invalidate the key, then {0} concurrent requests (expect exactly ONE db load)" -f $Concurrent)
# PUT the unchanged payload back: it clears L2 and broadcasts so both instances drop their L1
$current = curl.exe -s -m 10 "$A/items/db/$ItemId" | ConvertFrom-Json
$payload = @{ id = [long]$current.id; name = $current.name; price = $current.price; stock = $current.stock; image = $current.image;
              category = $current.category; brand = $current.brand; spec = $current.spec; sold = $current.sold;
              commentCount = $current.commentCount; isAD = $current.isAD } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText((Join-Path $tmp 'item.json'), $payload, $utf8)
& curl.exe -s -m 10 -X PUT -H 'Content-Type: application/json' --data-binary "@$(Join-Path $tmp 'item.json')" -o NUL "$A/items" | Out-Null
Start-Sleep -Milliseconds 800   # let the fanout message reach instance A
$before3 = Get-Stats $A
$cfg = Join-Path $tmp 'burst.conf'
$block = @("url = `"$A/items/$ItemId`"", 'output = "NUL"') -join "`r`n"
$blocks = @(1..$Concurrent | ForEach-Object { $block })
[System.IO.File]::WriteAllText($cfg, ($blocks -join "`r`nnext`r`n"), $utf8)
& curl.exe -s -K $cfg --parallel --parallel-immediate --parallel-max $Concurrent | Out-Null
Start-Sleep -Seconds 1
$after3 = Get-Stats $A
Write-Host ("    dbLoads +{0}  (expect +1), lockRebuilds +{1}, lockSpins +{2}" -f `
    ($after3.db.loads - $before3.db.loads), ($after3.db.lockRebuilds - $before3.db.lockRebuilds), ($after3.db.lockSpins - $before3.db.lockSpins))

# ---------- 4. cross-instance consistency ----------
Write-Host ''
Write-Host '[4] cross-instance consistency (L1 invalidation broadcast)'
# pre-flight: a second instance is required for this check
$preflight = curl.exe -s -m 30 -o NUL -w "%{http_code}" "$B/items/$ItemId"
if ($preflight -ne '200') {
  Write-Host ("    SKIPPED: no second item-service instance reachable at {0} (http {1})" -f $B, $preflight) -ForegroundColor Yellow
  Write-Host '    start one with:  java -Xms256m -Xmx512m -jar item-service/target/item-service.jar --server.port=8088'
  Write-Host ''
  Write-Host '[5] final stats'
  Show-Stats (Get-Stats $A) 'after '
  exit 0
}
& curl.exe -s -m 30 -o NUL "$A/items/$ItemId" | Out-Null
& curl.exe -s -m 30 -o NUL "$B/items/$ItemId" | Out-Null
$aBefore = (curl.exe -s -m 30 "$A/items/$ItemId" | ConvertFrom-Json).price
$newPrice = [int]$aBefore + 1
$payload2 = $payload -replace ('"price":' + $aBefore), ('"price":' + $newPrice)
[System.IO.File]::WriteAllText((Join-Path $tmp 'item2.json'), $payload2, $utf8)
& curl.exe -s -m 10 -X PUT -H 'Content-Type: application/json' --data-binary "@$(Join-Path $tmp 'item2.json')" -o NUL "$B/items" | Out-Null
$putCode = curl.exe -s -m 10 -X PUT -H 'Content-Type: application/json' --data-binary "@$(Join-Path $tmp 'item2.json')" -o NUL -w "%{http_code}" "$B/items"
Start-Sleep -Seconds 1
$aAfterRaw = curl.exe -s -m 10 "$A/items/$ItemId"
$bAfterRaw = curl.exe -s -m 10 "$B/items/$ItemId"
$aAfter = ($aAfterRaw | ConvertFrom-Json).price
$bAfter = ($bAfterRaw | ConvertFrom-Json).price
Write-Host ("    A read {0} -> update on B to {1} (PUT code={2}) -> A reads {3}, B reads {4}" -f $aBefore, $newPrice, $putCode, $aAfter, $bAfter)
if ([int]$aAfter -ne $newPrice -or [int]$bAfter -ne $newPrice) {
  Write-Host ("    debug: A raw = " + $aAfterRaw.Substring(0, [Math]::Min(120, $aAfterRaw.Length)))
  Write-Host ("    debug: B raw = " + $bAfterRaw.Substring(0, [Math]::Min(120, $bAfterRaw.Length)))
  Write-Host ("    debug: payload sent = " + (Get-Content (Join-Path $tmp 'item2.json') -Raw).Substring(0, [Math]::Min(120, 120)))
}
if ([int]$aAfter -eq $newPrice -and [int]$bAfter -eq $newPrice) {
  Write-Host '    => PASS: instance A saw the new value immediately (its L1 was invalidated by the MQ broadcast)' -ForegroundColor Green
} else {
  Write-Host '    => FAIL: instance A still serves a stale value' -ForegroundColor Yellow
}
# restore the original price
$payload3 = $payload2 -replace ('"price":' + $newPrice), ('"price":' + $aBefore)
[System.IO.File]::WriteAllText((Join-Path $tmp 'item3.json'), $payload3, $utf8)
& curl.exe -s -m 10 -X PUT -H 'Content-Type: application/json' --data-binary "@$(Join-Path $tmp 'item3.json')" -o NUL "$A/items" | Out-Null
Write-Host ("    price restored to {0}" -f $aBefore)

# ---------- 5. final stats ----------
Write-Host ''
Write-Host '[5] final stats'
$sEnd = Get-Stats $A
Show-Stats $sEnd 'after '
Write-Host ("    L1 hitRate={0}  L2 hitRate={1}" -f $sEnd.l1.caffeineHitRate, $sEnd.l2.hitRate)
Write-Host ''
