#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Block 1 – discovery of the running "on-prem" stack. Writes docs/discovery-output.txt.
.DESCRIPTION
  Collects: compose services, images + versions, env var names (secret values masked), port map,
  volumes, docker stats, MySQL version, table sizes/row counts, indexes on transactions,
  and the JAVA_OPTS vs container memory limit mismatch.
#>
param([string]$OutFile = 'docs/discovery-output.txt')
. "$PSScriptRoot/_common.ps1"

Push-Location $script:RepoRoot
$report = [System.Collections.Generic.List[string]]::new()
function Add-Section([string]$Title, [scriptblock]$Body) {
    Write-Step $Title
    $report.Add('')
    $report.Add('=' * 78)
    $report.Add("## $Title")
    $report.Add('=' * 78)
    $text = (& $Body 2>&1 | Out-String).TrimEnd()
    $report.Add($text)
    Write-Host $text
}

try {
    $project = 'ledgerly'
    $report.Add("Ledgerly discovery – $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME")

    Add-Section 'Compose services' { docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.State}}\t{{.Ports}}' }

    Add-Section 'Images and runtime versions' {
        docker compose images
        ''
        'api  java : ' + ((docker compose exec -T api java -version 2>&1 | Select-Object -First 1) -join '')
        'web  nginx: ' + ((docker compose exec -T web nginx -v 2>&1) -join '')
        'cache redis: ' + ((docker compose exec -T cache redis-server --version) -join '')
        'batch os  : ' + ((docker compose exec -T batch cat /etc/alpine-release) -join '')
    }

    Add-Section 'Environment variables (secret values masked)' {
        foreach ($svc in 'web', 'api', 'db', 'cache', 'batch') {
            $id = docker compose ps -q $svc
            if (-not $id) { continue }
            "[$svc]"
            foreach ($e in (docker inspect $id --format '{{range .Config.Env}}{{println .}}{{end}}')) {
                if (-not $e) { continue }
                $name, $value = $e -split '=', 2
                if ($name -match 'PASSWORD|SECRET|KEY|TOKEN') { "  {0,-28} = ******** (SECRET in plaintext!)" -f $name }
                elseif ($name -match '^(PATH|JAVA_HOME|LANG|GOSU_VERSION|NGINX_VERSION|NJS_VERSION|PKG_RELEASE|REDIS_DOWNLOAD.*)$') { continue }
                else { "  {0,-28} = {1}" -f $name, $value }
            }
        }
    }

    Add-Section 'Port map (host -> container)' {
        docker ps --filter "label=com.docker.compose.project=$project" --format 'table {{.Names}}\t{{.Ports}}'
    }

    Add-Section 'Volumes and mounts' {
        docker volume ls --filter "label=com.docker.compose.project=$project"
        ''
        foreach ($svc in 'web', 'api', 'db', 'cache', 'batch') {
            $id = docker compose ps -q $svc
            if ($id) { "[$svc] " + (docker inspect $id --format '{{range .Mounts}}{{.Type}}:{{if .Name}}{{.Name}}{{else}}{{.Source}}{{end}} -> {{.Destination}}  {{end}}') }
        }
    }

    Add-Section 'Resource usage (docker stats --no-stream)' {
        docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' (docker compose ps -q)
    }

    Add-Section 'MySQL version and settings' {
        Invoke-LocalMysql -Sql "SELECT CONCAT('version=', VERSION()), CONCAT('charset=', @@character_set_server), CONCAT('sql_mode=', @@sql_mode)"
    }

    Add-Section 'Database size and row counts' {
        'table          rows(exact)   data_mb  index_mb'
        $sizes = Invoke-LocalMysql -Sql "SELECT table_name, ROUND(data_length/1024/1024,1), ROUND(index_length/1024/1024,1) FROM information_schema.tables WHERE table_schema='ledgerly' ORDER BY table_name"
        foreach ($row in $sizes) {
            $t, $d, $i = $row -split "`t"
            $count = Invoke-LocalMysql -Sql "SELECT COUNT(*) FROM $t"
            '{0,-14} {1,11} {2,9} {3,9}' -f $t, $count, $d, $i
        }
    }

    Add-Section 'Indexes on transactions (look for booking_date!)' {
        Invoke-LocalMysql -Sql "SELECT index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index) FROM information_schema.statistics WHERE table_schema='ledgerly' AND table_name='transactions' GROUP BY index_name"
    }

    Add-Section 'JVM heap vs container memory limit (api)' {
        $id = docker compose ps -q api
        $javaOpts = (docker inspect $id --format '{{range .Config.Env}}{{println .}}{{end}}' | Where-Object { $_ -like 'JAVA_OPTS=*' }) -replace '^JAVA_OPTS=', ''
        $limit = [int64](docker inspect $id --format '{{.HostConfig.Memory}}')
        $limitMb = [math]::Round($limit / 1MB)
        "JAVA_OPTS            : $javaOpts"
        "container mem_limit  : $limitMb MiB"
        if ($javaOpts -match '-Xmx(\d+)([gGmM])') {
            $xmxMb = [int]$Matches[1] * ($(if ($Matches[2] -match '[gG]') { 1024 } else { 1 }))
            if ($limit -gt 0 -and $xmxMb -ge $limitMb) {
                "RISK: -Xmx ($xmxMb MiB) >= container limit ($limitMb MiB) -> OOMKilled under load. Use -XX:MaxRAMPercentage instead."
            } else { 'OK: heap fits the container limit.' }
        }
    }

    Add-Section 'Batch output (reports volume)' {
        docker compose exec -T batch sh -c 'ls -l /reports | tail -n 5; echo "files: $(ls /reports | wc -l)"'
    }

    $path = Join-Path $script:RepoRoot $OutFile
    $report | Set-Content -Path $path -Encoding utf8
    Write-Ok "Discovery written to $OutFile – compare with docs/inventory.md"
} finally { Pop-Location }
