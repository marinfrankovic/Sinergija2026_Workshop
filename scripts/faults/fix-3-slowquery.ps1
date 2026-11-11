#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fix 3 – CREATE INDEX ix_transactions_booking_date ON transactions(booking_date);  (db/migrations/001-...)
  Shows EXPLAIN before/after and re-times one report call.
.PARAMETER Local
  Apply to the on-prem MySQL 5.7 container instead of Azure.
#>
param([switch]$Local)
. "$PSScriptRoot/../_common.ps1"

$explain = "EXPLAIN SELECT COUNT(*) FROM transactions WHERE portfolio_id = 1 AND booking_date >= '2025-06-01' AND booking_date < '2025-07-01'"
$ddl = 'CREATE INDEX ix_transactions_booking_date ON transactions (booking_date)'

if ($Local) {
    $run = { param($sql) Invoke-LocalMysql -Sql $sql }
    $base = 'http://localhost:8081'
} else {
    $azd = Get-AzdValues
    $pw = if ($env:MYSQL_ADMIN_PASSWORD) { $env:MYSQL_ADMIN_PASSWORD } else { $azd.MYSQL_ADMIN_PASSWORD }
    $run = { param($sql) Invoke-AzureMysql -Server $azd.MYSQL_SERVER_FQDN -User $azd.MYSQL_ADMIN_LOGIN -Password $pw -Database $azd.MYSQL_DATABASE_NAME -Sql $sql }
    $base = $azd.WEB_URI
}

Write-Step 'EXPLAIN before (expect type=ALL, ~200k rows)'
& $run $explain
Write-Step "FIX 3: $ddl"
& $run $ddl
Write-Step 'EXPLAIN after (expect type=range, key=ix_transactions_booking_date)'
& $run $explain

Write-Step 'Re-time one report call'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = Invoke-RestMethod "$base/api/reports/monthly?year=2025&month=6" -TimeoutSec 120
Write-Ok ("round-trip {0} ms, server {1} ms" -f $sw.ElapsedMilliseconds, $r.durationMs)
