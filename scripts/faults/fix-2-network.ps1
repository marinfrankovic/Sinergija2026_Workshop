#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fix 2 – recreate AllowAllAzureServices (0.0.0.0). Long-term: VNet-integrated Container Apps environment
  + MySQL private access / private endpoint, then remove public access entirely.
#>
. "$PSScriptRoot/../_common.ps1"
$azd = Get-AzdValues
$rg = $azd.AZURE_RESOURCE_GROUP; $mysql = $azd.MYSQL_SERVER_NAME

Write-Step "FIX 2: recreate firewall rule AllowAllAzureServices on $mysql"
az mysql flexible-server firewall-rule create -g $rg -n $mysql --rule-name AllowAllAzureServices `
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 --only-show-errors -o none
Assert-LastExit 'firewall-rule create'
az mysql flexible-server firewall-rule list -g $rg -n $mysql -o table
Write-Ok 'Fixed. Health badge returns to UP within ~10–20 s (next pool connection attempt).'
