# LimeMall JMeter result parser
#
# Turns one or more JMeter .jtl (CSV) result files into a markdown comparison table.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File jmeter-report.ps1 -Files a.jtl,b.jtl -Labels "cached,direct-db"
#   powershell -ExecutionPolicy Bypass -File jmeter-report.ps1 -Files a.jtl -Out report.md
# NOTE: keep this file ASCII-only, Windows PowerShell reads .ps1 as ANSI without a BOM.
param(
  [Parameter(Mandatory = $true)][string[]]$Files,
  [string[]]$Labels = @(),
  [string]$Out = '',
  [switch]$Append
)

$ErrorActionPreference = 'Stop'
# make sure Chinese labels survive the console codepage
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# -File invocation cannot pass arrays, so accept "a.jtl,b.jtl" as well as a real array
$Files = @($Files | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Labels = @($Labels | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

function Get-Stats([string]$path) {
  $rows = Import-Csv -Path $path
  if (-not $rows -or $rows.Count -eq 0) { return $null }
  $elapsed = $rows | ForEach-Object { [double]$_.elapsed }
  $ok = @($rows | Where-Object { $_.success -eq 'true' })
  $sorted = $elapsed | Sort-Object
  $n = $sorted.Count
  $first = ($rows | Measure-Object -Property timeStamp -Minimum).Minimum
  $last = ($rows | ForEach-Object { [double]$_.timeStamp + [double]$_.elapsed } | Measure-Object -Maximum).Maximum
  $wall = [math]::Max(($last - $first) / 1000.0, 0.001)
  return [pscustomobject]@{
    samples    = $n
    errors     = $n - $ok.Count
    errorRate  = [math]::Round(100.0 * ($n - $ok.Count) / $n, 2)
    avg        = [math]::Round(($elapsed | Measure-Object -Average).Average, 1)
    p50        = [math]::Round($sorted[[int][math]::Floor($n * 0.50)], 1)
    p95        = [math]::Round($sorted[[int][math]::Floor($n * 0.95)], 1)
    p99        = [math]::Round($sorted[[int][math]::Floor($n * 0.99)], 1)
    max        = [math]::Round($sorted[$n - 1], 1)
    throughput = [math]::Round($n / $wall, 1)
    wall       = [math]::Round($wall, 1)
  }
}

$lines = New-Object System.Collections.ArrayList
[void]$lines.Add('| scenario | samples | TPS | avg(ms) | P50 | P95 | P99 | max(ms) | error% |')
[void]$lines.Add('|---|---|---|---|---|---|---|---|---|')

for ($i = 0; $i -lt $Files.Count; $i++) {
  $f = $Files[$i]
  $label = if ($i -lt $Labels.Count -and $Labels[$i]) { $Labels[$i] } else { [System.IO.Path]::GetFileNameWithoutExtension($f) }
  if (-not (Test-Path $f)) {
    [void]$lines.Add("| $label | - | - | - | - | - | - | - | file-not-found |")
    continue
  }
  $s = Get-Stats $f
  if (-not $s) { [void]$lines.Add("| $label | 0 | - | - | - | - | - | - | - |"); continue }
  [void]$lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8}% |" -f `
    $label, $s.samples, $s.throughput, $s.avg, $s.p50, $s.p95, $s.p99, $s.max, $s.errorRate))
}

$text = $lines -join "`r`n"
Write-Output $text
if ($Out) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  if ($Append -and (Test-Path $Out)) {
    [System.IO.File]::AppendAllText($Out, "`r`n" + $text + "`r`n", $enc)
  } else {
    [System.IO.File]::WriteAllText($Out, $text + "`r`n", $enc)
  }
  Write-Output ("`n[written] " + $Out)
}
