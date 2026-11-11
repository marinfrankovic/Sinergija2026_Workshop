#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Optional – builds a draw.io custom library (docs/diagrams/ledgerly-icons.xml) from the presenter's local
  clone of github.com/glincker/thesvg (brand icons: Docker, nginx, MySQL, Redis, Java/Spring, …).
.DESCRIPTION
  Azure icons come from the draw.io MCP server (embedded official Azure icons); thesvg is the secondary
  source for NON-Azure brand icons. Layout of the clone:  public/icons/<slug>/<variant>.svg
  (variants: default, mono, light, dark, wordmark – "default" always exists). This script reads
  public/icons/<slug>/default.svg for every slug and writes:
    <mxlibrary>[{"data":"data:image/svg+xml;base64,...","w":48,"h":48,"title":"docker","aspect":"fixed"}, ...]</mxlibrary>
  Icons are embedded (no CDN dependency). Open the library in draw.io / the VS Code draw.io editor via
  File > Open Library from > Device.
  Slug names may differ from the defaults – missing slugs are reported and skipped. Use -Search to list/add
  slugs by folder-name pattern; the manifest is src/data/icons.json in the clone (or https://thesvg.org/api/registry.json).
.PARAMETER Root     Local thesvg clone. Default C:\Github\tools\thesvg
.PARAMETER Slugs    Icon slugs (folder names under public\icons).
.PARAMETER Search   Optional wildcard pattern(s) matched against folder names, e.g. '*mysql*','*spring*'. Matches are added.
.PARAMETER OutFile  Relative to the repo root. Default docs/diagrams/ledgerly-icons.xml
.EXAMPLE
  ./scripts/build-drawio-library.ps1
  ./scripts/build-drawio-library.ps1 -Search '*java*','*spring*' -Slugs docker,nginx
#>
param(
    [string]$Root = 'C:\Github\tools\thesvg',
    [string[]]$Slugs = @('docker', 'nginx', 'mysql', 'redis', 'openjdk', 'spring', 'github', 'visualstudiocode', 'powershell', 'microsoftazure'),
    [string[]]$Search = @(),
    [string]$OutFile = 'docs/diagrams/ledgerly-icons.xml',
    [int]$Size = 48
)
. "$PSScriptRoot/_common.ps1"

$iconsDir = Join-Path $Root 'public' 'icons'
if (-not (Test-Path $iconsDir)) { throw "Not a thesvg clone (missing $iconsDir). git clone https://github.com/glincker/thesvg `"$Root`"" }

$wanted = [System.Collections.Generic.List[string]]::new()
$Slugs | ForEach-Object { if ($_ -and -not $wanted.Contains($_)) { $wanted.Add($_) } }
if ($Search) {
    $folders = Get-ChildItem -Path $iconsDir -Directory | Select-Object -ExpandProperty Name
    foreach ($pattern in $Search) {
        $hits = @($folders | Where-Object { $_ -like $pattern })
        Write-Host ("    search '{0}': {1}" -f $pattern, ($(if ($hits) { $hits -join ', ' } else { '(no match)' })))
        $hits | ForEach-Object { if (-not $wanted.Contains($_)) { $wanted.Add($_) } }
    }
}

Write-Step "Reading $($wanted.Count) slug(s) from $iconsDir"
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($slug in $wanted) {
    $svg = Join-Path $iconsDir $slug 'default.svg'
    if (-not (Test-Path $svg)) { Write-Warn2 "slug '$slug' not found – skipped (try -Search '*$slug*')"; continue }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($svg))
    $entries.Add([ordered]@{
        data   = "data:image/svg+xml;base64,$b64"
        w      = $Size
        h      = $Size
        title  = $slug
        aspect = 'fixed'
    })
    Write-Ok $slug
}
if ($entries.Count -eq 0) { throw 'No icons found – nothing written.' }

# -InputObject keeps a JSON array even for one icon; escape only XML-significant characters
$json = ConvertTo-Json -InputObject $entries.ToArray() -Compress -Depth 3
$xml = '<mxlibrary>' + $json.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') + '</mxlibrary>'

$target = Join-Path $script:RepoRoot $OutFile
New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
Set-Content -Path $target -Value $xml -Encoding utf8NoBOM
Write-Ok ("{0} written ({1} icons, {2:N0} KB)" -f $OutFile, $entries.Count, ((Get-Item $target).Length / 1KB))
