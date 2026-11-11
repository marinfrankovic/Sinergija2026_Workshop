#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Tears everything down: Azure (azd down --purge --force -> also purges the soft-deleted Key Vault)
  and the local stack incl. volumes.
.PARAMETER KeepAzure   Only clean up locally.
.PARAMETER KeepLocal   Only clean up Azure.
.PARAMETER IncludeMcp  Also remove the drawio-mcp container.
#>
param([switch]$KeepAzure, [switch]$KeepLocal, [switch]$IncludeMcp)
. "$PSScriptRoot/_common.ps1"

Push-Location $script:RepoRoot
try {
    if (-not $KeepAzure) {
        Write-Step 'azd down --purge --force  (deletes rg-ledgerly-workshop)'
        azd down --purge --force ; Assert-LastExit 'azd down'
    }
    if (-not $KeepLocal) {
        Write-Step 'docker compose down -v'
        docker compose down -v --remove-orphans ; Assert-LastExit 'docker compose down'
        Remove-Item -Recurse -Force (Join-Path $script:RepoRoot 'out') -ErrorAction SilentlyContinue
    }
    if ($IncludeMcp) {
        Write-Step 'Remove drawio-mcp container'
        docker rm -f drawio-mcp | Out-Null
    }
    Write-Ok 'Cleanup complete.'
} finally { Pop-Location }
