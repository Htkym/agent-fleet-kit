#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$CodexPath,
    [string]$UserHome = [Environment]::GetFolderPath('UserProfile'),
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutputPath
)
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$ErrorActionPreference = 'Stop'
if (-not $UserHome) { throw 'Pass -UserHome explicitly; this host does not expose a user home' }
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $UserHome '.codex' }
if (-not $CodexPath) {
    $found = Get-Command codex -ErrorAction SilentlyContinue
    if ($found) { $CodexPath = $found.Source }
}
$version = $null
$cliError = $null
if ($CodexPath -and (Test-Path -LiteralPath $CodexPath -PathType Leaf)) {
    $probe = Invoke-FleetProcess $CodexPath @('--version') $ProjectRoot
    if ($probe.exit_code -eq 0) { $version = $probe.stdout.Trim() } else { $cliError = 'CLI version probe failed' }
} else { $cliError = 'CLI unavailable; provide its observed absolute path' }
$layers = @()
$candidatePaths = @((Join-Path $codexHome 'config.toml'), (Join-Path $codexHome 'AGENTS.md'), (Join-Path $codexHome 'AGENTS.override.md'))
$cursor = [IO.Path]::GetFullPath($ProjectRoot)
while ($cursor) {
    $candidatePaths += @( (Join-Path $cursor 'AGENTS.md'), (Join-Path $cursor 'AGENTS.override.md'), (Join-Path $cursor '.codex/config.toml'))
    $parent = Split-Path $cursor -Parent
    if ($parent -eq $cursor) { break }
    $cursor = $parent
}
foreach ($path in $candidatePaths | Select-Object -Unique) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        $layers += @{path=$path;sha256=(Get-FleetHash $path);reparse_point=[bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint);effective='unverified'}
    }
}
$definitions = @()
$definitionRoots = @(
    @{path=(Join-Path $UserHome '.agents/skills');kind='skill'},
    @{path=(Join-Path $codexHome 'agents');kind='agent'}
)
$cursor = [IO.Path]::GetFullPath($ProjectRoot)
while ($cursor) {
    $definitionRoots += @{path=(Join-Path $cursor '.agents/skills');kind='skill'}
    $definitionRoots += @{path=(Join-Path $cursor '.codex/agents');kind='agent'}
    $parent = Split-Path $cursor -Parent
    if ($parent -eq $cursor) { break }
    $cursor = $parent
}
foreach ($root in $definitionRoots) {
    if (-not (Test-Path -LiteralPath $root.path -PathType Container)) { continue }
    foreach ($item in Get-ChildItem -LiteralPath $root.path -Force) {
        if ($root.kind -eq 'skill' -and $item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $item.FullName 'SKILL.md'))) {
            $definitions += @{kind='skill';name=$item.Name;path=$item.FullName;identity='directory-candidate'}
        } elseif ($root.kind -eq 'agent' -and $item.Extension -eq '.toml') {
            # Filename is a collision hint only: effective TOML name requires CLI discovery.
            $definitions += @{kind='agent';name=$item.BaseName;path=$item.FullName;identity='filename-candidate'}
        }
    }
}
$collisions = @($definitions | Group-Object { $_.kind + ':' + $_.name.ToLowerInvariant() } | Where-Object Count -GT 1 | ForEach-Object { @{name=$_.Name;paths=@($_.Group.path)} })
$catalog = @()
$cachePath = Join-Path $codexHome 'models_cache.json'
if (Test-Path -LiteralPath $cachePath) {
    $cache = Read-FleetJson $cachePath
    foreach ($model in $cache.models) {
        $catalog += @{id=$model.slug;reasoning=@($model.supported_reasoning_levels.effort);status='catalog-only'}
    }
}
$report = [ordered]@{
    format_version=1;recorded_at=(Get-Date).ToString('o');os=[Environment]::OSVersion.VersionString
    powershell=$PSVersionTable.PSVersion.ToString();cli_path=$CodexPath;cli_version=$version;cli_error=$cliError
    codex_home=$codexHome;authentication='unverified';layers=$layers;definitions=$definitions;collisions=$collisions
    overrides=@($layers | Where-Object { $_.path.EndsWith('AGENTS.override.md', [StringComparison]::OrdinalIgnoreCase) })
    model_catalog=$catalog;runtime_model='unverified';permissions='unverified';agent_discovery='unverified'
    usage='unavailable';config_resolution='unverified';writes_performed='none (except explicit OutputPath)'
}
if ($OutputPath) { Write-FleetJson $OutputPath $report }
$report | ConvertTo-Json -Depth 20
