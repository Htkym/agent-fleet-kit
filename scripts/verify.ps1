#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$Bundle = (Join-Path (Split-Path $PSScriptRoot -Parent) '.local/build/preview'),
    [string]$DestinationHome,
    [switch]$Smoke,
    [string]$CodexPath,
    [string]$UserHome,
    [string]$SessionPath,
    [switch]$ExecuteSmoke,
    [string]$OutputPath
)
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path $PSScriptRoot -Parent
$manifest = Get-FleetManifest $Bundle
foreach ($entry in $manifest.sources) {
    if ((Get-FleetHash (Resolve-FleetPath $kitRoot $entry.path)) -cne $entry.sha256) { throw "Source changed; regenerate: $($entry.path)" }
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $kitRoot 'tests/fixtures') -Filter '*.json') {
    if ($file.Name -eq 'task.valid.json') { Assert-FleetSchema task (Read-FleetJson $file.FullName) }
    elseif ($file.Name -eq 'result.unverified.json') { Assert-FleetSchema task-result (Read-FleetJson $file.FullName) }
    elseif ($file.Name -eq 'state.valid.json') { Assert-FleetSchema run-state (Read-FleetJson $file.FullName) }
}
$installed = 'not-requested'
if ($DestinationHome) {
    $plan = Get-FleetInstallPlan $Bundle $DestinationHome
    if (@($plan.files | Where-Object action -NE 'unchanged').Count) { throw 'Installed payload differs from bundle' }
    $installed = 'hash-verified; runtime discovery unverified'
}
if ($Smoke) {
    if (-not $SessionPath -and (-not $CodexPath -or -not $UserHome)) { throw 'Smoke requires -SessionPath or the observed -CodexPath and -UserHome; see operations.md' }
    & (Join-Path $kitRoot 'tests/integration/smoke.ps1') -SessionPath $SessionPath -CodexPath $CodexPath -UserHome $UserHome -Execute:$ExecuteSmoke -Bundle $Bundle -OutputPath $OutputPath
    exit $LASTEXITCODE
}
$report = @{status='static-verified';bundle=$Bundle;files=$manifest.files.Count;installable=$manifest.installable;installed=$installed;agent_runtime='unverified';model_runtime='unverified';acceptance='not-released'}
if ($OutputPath) { Write-FleetJson $OutputPath $report }
$report | ConvertTo-Json -Depth 10
