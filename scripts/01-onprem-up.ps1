#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Block 1 – starts the "on-prem" Ledgerly stack (Docker Compose), waits for health, opens the browser.
.NOTES
  First start seeds 200k transactions into MySQL 5.7 – allow 1–2 minutes.
#>
param([int]$TimeoutSeconds = 240, [switch]$NoBrowser)
. "$PSScriptRoot/_common.ps1"

Push-Location $script:RepoRoot
try {
    Write-Step 'docker compose up -d --build'
    docker compose up -d --build ; Assert-LastExit 'docker compose up'

    Write-Step "Waiting for http://localhost:8081/api/health (max $TimeoutSeconds s)"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $health = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri 'http://localhost:8081/api/health' -TimeoutSec 10
            if ($health.status -eq 'UP') { break }
        } catch { }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 5
    }
    Write-Host ''
    if (-not $health -or $health.status -ne 'UP') { docker compose ps; throw 'Ledgerly did not become healthy in time (docker compose logs api db).' }
    Write-Ok "Ledgerly is UP: db=$($health.db) cache=$($health.cache) version=$($health.version)"
    docker compose ps
    if (-not $NoBrowser) { Start-Process 'http://localhost:8081' }
} finally { Pop-Location }
