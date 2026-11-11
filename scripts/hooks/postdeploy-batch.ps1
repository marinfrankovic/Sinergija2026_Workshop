#!/usr/bin/env pwsh
<#
.SYNOPSIS
  azd postdeploy hook – builds the batch image in ACR and points the Container Apps job at it.
.DESCRIPTION
  The batch component is a Container Apps *job* (Microsoft.App/jobs), which azd does not deploy as a
  service. azd exports all environment values (Bicep outputs) as environment variables to hooks.
  The image name is stored as BATCH_IMAGE_NAME so the next `azd provision` keeps the real image
  instead of reverting to the placeholder.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')

$acrName = $env:AZURE_CONTAINER_REGISTRY_NAME
$acrHost = $env:AZURE_CONTAINER_REGISTRY_ENDPOINT
$rg      = $env:AZURE_RESOURCE_GROUP
$job     = $env:BATCH_JOB_NAME
if (-not ($acrName -and $rg -and $job)) { throw 'Missing azd outputs (AZURE_CONTAINER_REGISTRY_NAME / AZURE_RESOURCE_GROUP / BATCH_JOB_NAME). Run azd provision first.' }

$tag   = 'azd-' + (Get-Date -Format 'yyyyMMddHHmmss')
$image = "$acrHost/ledgerly/batch:$tag"

Write-Host "==> Building batch image in ACR: $image" -ForegroundColor Cyan
az acr build --registry $acrName --image "ledgerly/batch:$tag" (Join-Path $repoRoot 'batch') --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'az acr build failed' }

Write-Host "==> Updating Container Apps job $job" -ForegroundColor Cyan
az containerapp job update --name $job --resource-group $rg --image $image --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'az containerapp job update failed' }

azd env set BATCH_IMAGE_NAME $image | Out-Null
Write-Host "Batch job now runs $image (schedule */15 * * * *)." -ForegroundColor Green
