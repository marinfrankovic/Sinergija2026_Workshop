#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Block 0 – checks the presenter laptop: tools, versions, Docker engine, Azure login, resource providers.
.EXAMPLE
  ./scripts/00-prereqs.ps1             # check only
  ./scripts/00-prereqs.ps1 -Register   # also register missing Azure resource providers
#>
param([switch]$Register)
. "$PSScriptRoot/_common.ps1"

Write-Step 'Tools'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'PowerShell 7+ required (pwsh).' }
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

$tools = [ordered]@{
    docker = 'docker --version'
    git    = 'git --version'
    az     = '(az version -o json | ConvertFrom-Json)."azure-cli"'
    azd    = 'azd version'
    node   = 'node --version'   # npx is needed for the Azure MCP Server
    code   = 'code --version'
}
foreach ($t in $tools.Keys) {
    if (Get-Command $t -ErrorAction SilentlyContinue) {
        $v = (Invoke-Expression $tools[$t] 2>$null | Select-Object -First 1)
        Write-Ok "$t $v"
    } else { Write-Warn2 "$t not found on PATH" }
}

Write-Step 'Docker engine + compose'
docker info --format '{{.ServerVersion}} ({{.OperatingSystem}})' ; Assert-LastExit 'docker info (is Docker Desktop running?)'
docker compose version ; Assert-LastExit 'docker compose'

Write-Step 'Bicep (via az)'
az bicep version 2>$null
if ($LASTEXITCODE -ne 0) { Write-Warn2 'Bicep missing -> az bicep install' }

Write-Step 'Azure login'
$acct = az account show --query '{name:name, id:id, user:user.name}' -o json 2>$null | ConvertFrom-Json
if (-not $acct) { Write-Warn2 'Not logged in -> az login ; azd auth login' } else { Write-Ok "$($acct.user) @ $($acct.name) ($($acct.id))" }
azd auth login --check-status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warn2 'azd not logged in -> azd auth login' } else { Write-Ok 'azd logged in' }

Write-Step 'Resource providers'
$providers = 'Microsoft.App', 'Microsoft.DBforMySQL', 'Microsoft.Cache', 'Microsoft.KeyVault',
             'Microsoft.ContainerRegistry', 'Microsoft.OperationalInsights', 'Microsoft.Insights', 'Microsoft.ManagedIdentity'
foreach ($p in $providers) {
    $state = az provider show -n $p --query registrationState -o tsv 2>$null
    if ($state -eq 'Registered') { Write-Ok $p }
    elseif ($Register) { az provider register -n $p | Out-Null; Write-Warn2 "$p registering…" }
    else { Write-Warn2 "$p is '$state' (re-run with -Register)" }
}

Write-Step 'draw.io MCP server (simonkurtzmsft/drawio-mcp-server on localhost:8080)'
$mcp = docker ps --filter 'name=^drawio-mcp$' --format '{{.Status}} {{.Ports}}'
if ($mcp) { Write-Ok "drawio-mcp container: $mcp" }
else { Write-Warn2 'not running -> docker run -d --name drawio-mcp -p 127.0.0.1:8080:8080 simonkurtzmsft/drawio-mcp-server:latest' }
try {
    Invoke-WebRequest -Uri 'http://localhost:8080/health' -TimeoutSec 5 -UseBasicParsing | Out-Null
    Write-Ok 'http://localhost:8080/health responds (MCP endpoint: http://localhost:8080/mcp)'
} catch { Write-Warn2 'http://localhost:8080/health not reachable' }
if ($mcp -and $mcp -match '0\.0\.0\.0:8080') { Write-Warn2 'drawio-mcp is published on all interfaces – prefer -p 127.0.0.1:8080:8080 (no auth on the endpoint)' }

Write-Step 'Port 8081 free for Ledgerly web?'
$busy = docker ps --format '{{.Names}} {{.Ports}}' | Select-String ':8081->' | Where-Object { $_ -notmatch '^ledgerly-' }
if ($busy) { Write-Warn2 "host port 8081 already used: $busy" } else { Write-Ok 'port 8081 available (or used by Ledgerly)' }

Write-Step 'Public IP for the MySQL firewall rule'
try {
    $ip = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5).Trim()
    Write-Ok "Public IP $ip  -> azd env set PRESENTER_IP $ip"
} catch { Write-Warn2 'Could not detect public IP (set PRESENTER_IP manually).' }
