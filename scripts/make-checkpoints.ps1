#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds the git history with one tag per workshop checkpoint (00-onprem ... 06-fixed).
.DESCRIPTION
  Commits the repository in layers, one commit + tag per block, so you can jump with
  `git checkout 03-migrated` if a live step fails. Run ONCE on a fresh copy (no commits yet).
  See checkpoints.md for what each tag contains.
.PARAMETER Force
  Delete existing checkpoint tags first (history is not rewritten).
#>
param([switch]$Force)
. "$PSScriptRoot/_common.ps1"

$checkpoints = [ordered]@{
    '00-onprem'     = @('.gitignore', '.gitattributes', '.env', 'README.md', 'checkpoints.md', 'PRESENTER-FACTS.md',
                        'docker-compose.yml', 'web', 'api', 'db/init', 'batch', 'cache', '.vscode', '.github',
                        'scripts/_common.ps1', 'scripts/00-prereqs.ps1', 'scripts/01-onprem-up.ps1')
    '01-discovered' = @('scripts/02-discover.ps1', 'docs/inventory.md')
    '02-diagrammed' = @('docs/diagrams', 'docs/drawio-mcp.md', 'scripts/build-drawio-library.ps1')
    '03-migrated'   = @('azure.yaml', 'infra', 'scripts/hooks', 'scripts/03-migrate-data.ps1', 'docs/migration-plan.md')
    '04-modernized' = @('scripts/04-modernize.ps1')
    '05-broken'     = @('scripts/faults/fault-1-oom.ps1', 'scripts/faults/fault-2-network.ps1',
                        'scripts/faults/fault-3-slowquery.ps1', 'kql')
    '06-fixed'      = @('scripts/faults/fix-1-oom.ps1', 'scripts/faults/fix-2-network.ps1',
                        'scripts/faults/fix-3-slowquery.ps1', 'db/migrations', 'scripts/reset.ps1',
                        'scripts/cleanup.ps1', 'scripts/make-checkpoints.ps1', '.')
}

Push-Location $script:RepoRoot
try {
    if (-not (Test-Path '.git')) { git init -q -b main ; Assert-LastExit 'git init' }
    git rev-parse --verify HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0 -and -not $Force) { throw 'Repository already has commits. Use a fresh copy or -Force (tags only).' }

    foreach ($tag in $checkpoints.Keys) {
        if ($Force) { git tag -d $tag 2>$null | Out-Null }
        foreach ($p in $checkpoints[$tag]) {
            if (Test-Path $p) { git add -- $p ; Assert-LastExit "git add $p" } else { Write-Warn2 "missing: $p" }
        }
        git commit -q --allow-empty -m "checkpoint $tag" ; Assert-LastExit 'git commit'
        git tag -a $tag -m "Ledgerly workshop checkpoint $tag" ; Assert-LastExit "git tag $tag"
        Write-Ok $tag
    }
    git --no-pager log --oneline --decorate
} finally { Pop-Location }
