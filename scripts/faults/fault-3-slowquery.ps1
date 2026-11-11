#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fault 3 – month-end load: parallel calls to the monthly report (full table scans, no index on booking_date).
.DESCRIPTION
  Symptom: report takes seconds, UI button spins, App Insights slow requests (> 2000 ms), MySQL CPU high.
  Evidence: kql "slow requests" + "MySQL slow log" (AzureDiagnostics Category == "MySqlSlowLogs"),
            EXPLAIN shows type=ALL on transactions.
.PARAMETER Local
  Run against the on-prem stack (http://localhost:8081) instead of Azure – handy for rehearsal.
#>
param([int]$Requests = 40, [int]$Parallel = 8, [switch]$Local)
. "$PSScriptRoot/../_common.ps1"
$base = if ($Local) { 'http://localhost:8081' } else { Get-WebUri }

Write-Step "FAULT 3: $Requests report calls, $Parallel in parallel -> $base/api/reports/monthly"
$results = 1..$Requests | ForEach-Object -ThrottleLimit $Parallel -Parallel {
    $month = ($_ % 12) + 1
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-RestMethod "$($using:base)/api/reports/monthly?year=2025&month=$month" -TimeoutSec 120
        [pscustomobject]@{ Call = $_; Month = $month; Ms = $sw.ElapsedMilliseconds; ServerMs = $r.durationMs; Ok = $true }
    } catch {
        [pscustomobject]@{ Call = $_; Month = $month; Ms = $sw.ElapsedMilliseconds; ServerMs = $null; Ok = $false }
    }
}
$results | Sort-Object Call | Format-Table -AutoSize
$stats = $results | Measure-Object Ms -Average -Maximum
Write-Ok ("avg {0:N0} ms, max {1:N0} ms, failed {2}" -f $stats.Average, $stats.Maximum, ($results | Where-Object { -not $_.Ok }).Count)
