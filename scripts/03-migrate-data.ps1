#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Block 3 – migrates the ledgerly database from on-prem MySQL 5.7 (compose "db") to
  Azure Database for MySQL Flexible Server 8.0.
.DESCRIPTION
  1. Pre-checks for 5.7 -> 8.0 compatibility on the source.
  2. mysqldump inside the 5.7 container (--single-transaction --routines --triggers --set-gtid-purged=OFF).
  3. Import with a temporary mysql:8.0 client container (--ssl-mode=REQUIRED).
  4. Verifies row counts on both sides.
  Needs: azd provision done, PRESENTER_IP firewall rule, MYSQL_ADMIN_PASSWORD in the azd env.
.PARAMETER FreezeSource
  Cutover mode: stop api + batch on-prem before the dump so no writes are lost.
#>
param([switch]$FreezeSource)
. "$PSScriptRoot/_common.ps1"

$azd      = Get-AzdValues
$server   = $azd.MYSQL_SERVER_FQDN
$admin    = $azd.MYSQL_ADMIN_LOGIN
$database = $azd.MYSQL_DATABASE_NAME
$password = if ($env:MYSQL_ADMIN_PASSWORD) { $env:MYSQL_ADMIN_PASSWORD } else { $azd.MYSQL_ADMIN_PASSWORD }
if (-not $password) { throw 'MYSQL_ADMIN_PASSWORD not set (azd env set MYSQL_ADMIN_PASSWORD ...)' }

$outDir   = Join-Path $script:RepoRoot 'out'
$dumpFile = Join-Path $outDir 'ledgerly-dump.sql'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$tables = 'portfolios', 'instruments', 'positions', 'transactions'

Push-Location $script:RepoRoot
try {
    # ---------------------------------------------------------------- 1. pre-checks
    Write-Step 'Compatibility pre-checks on MySQL 5.7 (source)'
    Invoke-LocalMysql -Sql "SELECT CONCAT('source version: ', VERSION())"
    'utf8mb3 tables (become utf8mb3 + deprecation warning on 8.0):'
    Invoke-LocalMysql -Sql "SELECT table_name, table_collation FROM information_schema.tables WHERE table_schema='ledgerly' AND table_collation LIKE 'utf8\_%'"
    'Columns named like 8.0 reserved words (RANK, GROUPS, ROW_NUMBER, LEAD, LAG, SYSTEM, ...):'
    Invoke-LocalMysql -Sql "SELECT CONCAT(table_name,'.',column_name) FROM information_schema.columns WHERE table_schema='ledgerly' AND UPPER(column_name) IN ('RANK','GROUPS','ROW_NUMBER','LEAD','LAG','SYSTEM','CUME_DIST','DENSE_RANK','NTILE','WINDOW','OVER','RECURSIVE','LATERAL','ARRAY','MEMBER')"
    'Routines/triggers/views (sql_mode NO_AUTO_CREATE_USER is removed in 8.0):'
    Invoke-LocalMysql -Sql "SELECT CONCAT('routines=', (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='ledgerly'), ' triggers=', (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='ledgerly'), ' views=', (SELECT COUNT(*) FROM information_schema.views WHERE table_schema='ledgerly'))"
    'Tables without primary key (sql_require_primary_key may be ON in Azure):'
    Invoke-LocalMysql -Sql "SELECT t.table_name FROM information_schema.tables t LEFT JOIN information_schema.table_constraints c ON c.table_schema=t.table_schema AND c.table_name=t.table_name AND c.constraint_type='PRIMARY KEY' WHERE t.table_schema='ledgerly' AND c.constraint_name IS NULL"

    # ---------------------------------------------------------------- 2. dump
    if ($FreezeSource) {
        Write-Step 'Cutover: stopping api + batch on-prem (read-only window starts)'
        docker compose stop api batch ; Assert-LastExit 'compose stop'
    }
    Write-Step 'mysqldump (inside the 5.7 container)'
    $envMap = Get-DotEnv
    docker compose exec -T -e "MYSQL_PWD=$($envMap.MYSQL_ROOT_PASSWORD)" db sh -c `
        'mysqldump -uroot --single-transaction --routines --triggers --set-gtid-purged=OFF --default-character-set=utf8 --no-tablespaces ledgerly > /root/ledgerly-dump.sql'
    Assert-LastExit 'mysqldump'
    docker compose cp db:/root/ledgerly-dump.sql $dumpFile ; Assert-LastExit 'docker compose cp'
    Write-Ok ("dump: out/ledgerly-dump.sql ({0:N1} MB)" -f ((Get-Item $dumpFile).Length / 1MB))

    # ---------------------------------------------------------------- 3. import
    Write-Step "Import into $server/$database (mysql:8.0 client, TLS required)"
    docker run --rm -e "MYSQL_PWD=$password" -v "${outDir}:/dump:ro" $script:Mysql8Image `
        sh -c "mysql -h $server -u $admin --ssl-mode=REQUIRED $database < /dump/ledgerly-dump.sql"
    Assert-LastExit 'import'

    # ---------------------------------------------------------------- 4. verify
    Write-Step 'Row counts: on-prem vs Azure'
    $rows = foreach ($t in $tables) {
        $src = [int](Invoke-LocalMysql -Sql "SELECT COUNT(*) FROM $t")
        $dst = [int](Invoke-AzureMysql -Server $server -User $admin -Password $password -Database $database -Sql "SELECT COUNT(*) FROM $t")
        [pscustomobject]@{ Table = $t; OnPrem = $src; Azure = $dst; Match = ($src -eq $dst) }
    }
    $rows | Format-Table -AutoSize
    'Target version: ' + (Invoke-AzureMysql -Server $server -User $admin -Password $password -Database $database -Sql 'SELECT VERSION()')
    if ($rows.Match -contains $false) { throw 'Row count mismatch – do NOT cut over (rollback = keep on-prem running).' }
    Write-Ok 'All row counts match. Next: open the web URL (azd show / WEB_URI) and check the health badge.'
} finally { Pop-Location }
