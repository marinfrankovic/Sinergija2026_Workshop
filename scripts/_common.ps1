<#
.SYNOPSIS
  Shared helpers for the Ledgerly workshop scripts. Dot-source it:  . "$PSScriptRoot/_common.ps1"
.NOTES
  PowerShell 7+. All paths are relative to the repository root (works from any clone location, e.g. a synced OneDrive folder).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot here = <repo>/scripts (this file's folder), also when dot-sourced from scripts/faults
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:Mysql8Image = 'mysql:8.0'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "    OK  $Message" -ForegroundColor Green }
function Write-Warn2([string]$Message){ Write-Host "    !!  $Message" -ForegroundColor Yellow }

function Assert-LastExit([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)" }
}

# Reads the legacy .env file (KEY=VALUE, # comments) into a hashtable.
function Get-DotEnv {
    $map = @{}
    $path = Join-Path $script:RepoRoot '.env'
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $k, $v = $line -split '=', 2
        $map[$k.Trim()] = $v.Trim()
    }
    return $map
}

# Returns azd environment values (Bicep outputs + azd env set values) as a hashtable.
function Get-AzdValues {
    Push-Location $script:RepoRoot
    try {
        $map = @{}
        foreach ($line in (azd env get-values)) {
            if ($line -match '^([A-Za-z0-9_]+)="?(.*?)"?$') { $map[$Matches[1]] = $Matches[2] }
        }
        Assert-LastExit 'azd env get-values'
        foreach ($k in 'AZURE_RESOURCE_GROUP', 'API_APP_NAME', 'MYSQL_SERVER_FQDN') {
            if (-not $map.ContainsKey($k)) { throw "azd value $k not found – run 'azd provision' first." }
        }
        return $map
    } finally { Pop-Location }
}

# Runs a mysql command against Azure Database for MySQL via a throw-away mysql:8.0 client container.
# -Password can be the admin password or a Microsoft Entra access token (then use -Cleartext).
function Invoke-AzureMysql {
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$Password,
        [Parameter(Mandatory)] [string]$Sql,
        [string]$Database = 'ledgerly',
        [switch]$Cleartext
    )
    $dockerArgs = @('run', '--rm', '-e', "MYSQL_PWD=$Password", $script:Mysql8Image,
              'mysql', '-h', $Server, '-u', $User, '--ssl-mode=REQUIRED', '-N', '-B')
    if ($Cleartext) { $dockerArgs += '--enable-cleartext-plugin' }
    $dockerArgs += @('-D', $Database, '-e', $Sql)
    $out = & docker @dockerArgs
    Assert-LastExit "mysql on $Server"
    return $out
}

# Runs a mysql command inside the on-prem MySQL 5.7 container as root.
function Invoke-LocalMysql {
    param([Parameter(Mandatory)] [string]$Sql, [string]$Database = 'ledgerly')
    $envMap = Get-DotEnv
    Push-Location $script:RepoRoot
    try {
        $out = docker compose exec -T -e "MYSQL_PWD=$($envMap.MYSQL_ROOT_PASSWORD)" db mysql -uroot -N -B -D $Database -e $Sql
        Assert-LastExit 'mysql in db container'
        return $out
    } finally { Pop-Location }
}

function Get-WebUri { (Get-AzdValues).WEB_URI }
