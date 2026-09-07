#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$DestinationHome,[switch]$Apply,[switch]$RecoverPending)
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$ErrorActionPreference = 'Stop'
if ($RecoverPending) {
    if (-not $Apply) { throw 'Pending recovery mutates managed files; inspect pending.json and pass -Apply explicitly' }
    $mutationLock = Open-FleetMutationLock $DestinationHome
    try { $report = Undo-FleetPending $DestinationHome } finally { $mutationLock.Dispose() }
} elseif ($Apply) {
    $preflight = Invoke-FleetRollback $DestinationHome
    if ($preflight.status -eq 'not-installed') { $report = $preflight }
    else {
        $mutationLock = Open-FleetMutationLock $DestinationHome
        try { $report = Invoke-FleetRollback $DestinationHome -Apply } finally { $mutationLock.Dispose() }
    }
} else { $report = Invoke-FleetRollback $DestinationHome }
$report | ConvertTo-Json -Depth 20
