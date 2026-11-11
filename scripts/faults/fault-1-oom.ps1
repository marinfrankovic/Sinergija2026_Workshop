#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fault 1 – "someone right-sized the api to save money": memory 2Gi -> 1Gi while the image still
  hard-codes JAVA_OPTS=-Xms1g -Xmx2g.
.DESCRIPTION
  -XX:+AlwaysPreTouch is added so the JVM commits the full -Xms heap at start-up. This makes the
  failure deterministic on stage (heap + metaspace + threads > 1Gi -> OOMKilled, exit 137, restart loop).
  Root cause is the same as in production: heap sizing that ignores the container limit.
  Symptom: health badge flips / 502s, replica restart count climbs.
  Evidence: az containerapp replica list, system logs, kql/queries.kql "restarts / OOM".
#>
. "$PSScriptRoot/../_common.ps1"
$azd = Get-AzdValues
$rg = $azd.AZURE_RESOURCE_GROUP; $api = $azd.API_APP_NAME

Write-Step "FAULT 1: $api -> 0.5 vCPU / 1Gi with JAVA_OPTS -Xms1g -Xmx2g"
az containerapp update -n $api -g $rg --cpu 0.5 --memory 1Gi `
    --set-env-vars "JAVA_OPTS=-Xms1g -Xmx2g -XX:+AlwaysPreTouch" --only-show-errors -o none
Assert-LastExit 'az containerapp update'
Write-Ok 'Fault injected. Watch:'
"  az containerapp replica list -n $api -g $rg --query `"[].{name:name, restarts:properties.containers[0].restartCount, state:properties.runningState}`" -o table"
"  az containerapp logs show -n $api -g $rg --type system --tail 30"
