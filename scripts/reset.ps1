#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Re-arms the break & fix block between rehearsals (Azure side):
   - firewall rule AllowAllAzureServices present
   - api back to 1.0 vCPU / 2Gi, JAVA_OPTS override removed (image default applies)
   - index ix_transactions_booking_date dropped (so fault 3 is slow again)
.PARAMETER KeepIndex
  Do not drop the index.
.PARAMETER Local
  Only drop the index in the on-prem MySQL container.
#>
param([switch]$KeepIndex, [switch]$Local)
. "$PSScriptRoot/_common.ps1"
$drop = 'DROP INDEX ix_transactions_booking_date ON transactions'

if ($Local) {
    Write-Step 'Local: drop index (ignore error if missing)'
    try { Invoke-LocalMysql -Sql $drop } catch { Write-Warn2 $_.Exception.Message }
    return
}

$azd = Get-AzdValues
$rg = $azd.AZURE_RESOURCE_GROUP; $api = $azd.API_APP_NAME; $mysql = $azd.MYSQL_SERVER_NAME

Write-Step 'Firewall rule AllowAllAzureServices'
az mysql flexible-server firewall-rule create -g $rg -n $mysql --rule-name AllowAllAzureServices `
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 --only-show-errors -o none

Write-Step "api $api -> 1.0 vCPU / 2Gi, remove JAVA_OPTS override"
az containerapp update -n $api -g $rg --cpu 1.0 --memory 2Gi --remove-env-vars JAVA_OPTS --only-show-errors -o none
Assert-LastExit 'az containerapp update'

if (-not $KeepIndex) {
    Write-Step 'Drop index ix_transactions_booking_date (re-arm fault 3)'
    $pw = if ($env:MYSQL_ADMIN_PASSWORD) { $env:MYSQL_ADMIN_PASSWORD } else { $azd.MYSQL_ADMIN_PASSWORD }
    try { Invoke-AzureMysql -Server $azd.MYSQL_SERVER_FQDN -User $azd.MYSQL_ADMIN_LOGIN -Password $pw -Database $azd.MYSQL_DATABASE_NAME -Sql $drop }
    catch { Write-Warn2 "Index not dropped: $($_.Exception.Message)" }
}
Write-Ok 'Reset done.'
