#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fix 1 – make the JVM container-aware instead of hard-coding the heap; restore 1 vCPU / 2Gi.
  Permanent fix: remove ENV JAVA_OPTS="-Xms1g -Xmx2g" from api/Dockerfile (use -XX:MaxRAMPercentage=75.0).
#>
. "$PSScriptRoot/../_common.ps1"
$azd = Get-AzdValues
$rg = $azd.AZURE_RESOURCE_GROUP; $api = $azd.API_APP_NAME

Write-Step "FIX 1: $api -> 1.0 vCPU / 2Gi, JAVA_OPTS=-XX:MaxRAMPercentage=75.0"
az containerapp update -n $api -g $rg --cpu 1.0 --memory 2Gi `
    --set-env-vars "JAVA_OPTS=-XX:MaxRAMPercentage=75.0" --only-show-errors -o none
Assert-LastExit 'az containerapp update'
Write-Ok 'Fixed. Restart count of the new revision should stay at 0.'
