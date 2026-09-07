#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DestinationHome,
    [string]$Bundle = (Join-Path (Split-Path $PSScriptRoot -Parent) '.local/build/preview'),
    [switch]$Apply,
    [switch]$Fixture,
    [string]$OutputPath
)
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$ErrorActionPreference = 'Stop'
if ($Apply) {
    $preflight = Get-FleetInstallPlan $Bundle $DestinationHome
    if ($Fixture) { Assert-FleetFixtureHome $DestinationHome }
    elseif (-not $preflight.installable) { throw 'Preview cannot be installed into a user home' }
    $mutationLock = Open-FleetMutationLock $DestinationHome
    try { $report = Invoke-FleetInstall $Bundle $DestinationHome -Fixture:$Fixture }
    finally { $mutationLock.Dispose() }
} else {
    $plan = Get-FleetInstallPlan $Bundle $DestinationHome
    $report = @{status='dry-run';destination=$plan.destination;installable=$plan.installable;files=$plan.files;proposals=@{
        config=(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/codex/config.fragment.toml.template') -Raw)
        instructions=(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../templates/codex/AGENTS.fragment.md') -Raw)
        mode='proposal-only; no TOML or AGENTS.md mutation'
    }}
}
if ($OutputPath) { Write-FleetJson $OutputPath $report }
$report | ConvertTo-Json -Depth 20
