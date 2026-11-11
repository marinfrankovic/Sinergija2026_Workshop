#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fault 2 – "security hardening gone wrong": deletes the MySQL firewall rule AllowAllAzureServices.
.DESCRIPTION
  Container Apps (no VNet) reach MySQL over its public endpoint from Azure outbound IPs. Without the rule
  new connections are rejected/time out (Hikari connection-timeout 5 s). The api revision is restarted so
  pooled connections are dropped and the symptom appears immediately.
  Symptom: badge DEGRADED (db DOWN), /api/portfolios 500 after ~5 s.
  Evidence: console logs "Connection is not available, request timed out" / "Communications link failure",
            App Insights failed dependencies, az mysql flexible-server firewall-rule list.
#>
. "$PSScriptRoot/../_common.ps1"
$azd = Get-AzdValues
$rg = $azd.AZURE_RESOURCE_GROUP; $api = $azd.API_APP_NAME; $mysql = $azd.MYSQL_SERVER_NAME

Write-Step "FAULT 2: delete firewall rule AllowAllAzureServices on $mysql"
az mysql flexible-server firewall-rule delete -g $rg -n $mysql --rule-name AllowAllAzureServices --yes --only-show-errors
Assert-LastExit 'firewall-rule delete'

Write-Step 'Restart the active api revision (drops pooled connections)'
$rev = az containerapp revision list -n $api -g $rg --query "[?properties.active].name | [0]" -o tsv
az containerapp revision restart -n $api -g $rg --revision $rev --only-show-errors -o none
Assert-LastExit 'revision restart'
Write-Ok "Fault injected (revision $rev restarted)."
