#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$CodexPath,
    [string]$UserHome,
    [switch]$AutoReview,
    [string]$ReadinessEvidence,
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $kitRoot 'scripts/Fleet.psm1') -Force
. (Join-Path $PSScriptRoot 'grade.ps1')
if (-not $ReadinessEvidence) { $ReadinessEvidence = Join-Path $kitRoot 'docs/runtime-readiness.json' }
if (-not $OutputPath) { $OutputPath = Join-Path $kitRoot '.local/artifacts/evaluation.json' }
$cases = (Read-FleetJson (Join-Path $PSScriptRoot 'cases.json')).cases
$map = Read-FleetJson (Join-Path $kitRoot 'config/model-tiers.example.yaml')
$readiness = Read-FleetJson $ReadinessEvidence
$ready = $true
foreach ($key in @('custom_agents_verified','lifecycle_verified','permissions_verified','model_resolution_verified')) {
    if (-not $readiness.ContainsKey($key) -or $readiness[$key] -isnot [bool] -or -not $readiness[$key]) { $ready = $false }
}
$rows = @()
$orders = @(@('A','B','C'),@('B','C','A'),@('C','A','B'),@('A','C','B'))
for ($i=0; $i -lt $cases.Count; $i++) {
    foreach ($condition in $orders[$i]) {
        $rows += @{case_id=$cases[$i].id;condition=$condition;repetition=1;status=$(if ($ready) {'planned'} else {'blocked'});elapsed_seconds=$null;test_exit_code=$null;reported_turn_usage=$null;all_threads_usage='unavailable';acceptance='unverified'}
    }
}
$report = @{format_version=1;protocol='four-cases-three-conditions-one-repetition';root_model=$map.tiers.ROOT.model;root_reasoning='high';rows=$rows;comparison='not-measured';readiness=$readiness}
if (-not $Execute -or -not $ready) {
    Write-FleetJson $OutputPath $report
    @{status=$(if ($Execute) {'blocked'} else {'dry-run'});planned_runs=$rows.Count;runtime_ready=$ready;report=$OutputPath} | ConvertTo-Json
    if ($Execute) { exit 2 }
    exit 0
}
if (-not $CodexPath -or -not $UserHome) { throw '-Execute requires -CodexPath and -UserHome' }
$root = Join-Path $kitRoot ('.local/runs/tests/eval-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$pwshPath = (Get-Process -Id $PID).Path
$gitPath = (Get-Command git).Source
$bundles = @{}
foreach ($condition in @('B','C')) {
    $localMap = Read-FleetJson (Join-Path $kitRoot 'config/model-tiers.example.yaml')
    if ($condition -eq 'B') { foreach ($tier in $localMap.tiers.Keys) { $localMap.tiers[$tier].model = $map.tiers.ROOT.model } }
    $mapPath = Join-Path $root "$condition-models.yaml"
    Write-FleetJson $mapPath $localMap
    $bundlePath = Join-Path $root "$condition-bundle"
    $render = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $kitRoot 'scripts/render.ps1'),'-Preview','-ModelTiers',$mapPath,'-OutputDirectory',$bundlePath) $kitRoot
    if ($render.exit_code -ne 0) { throw 'Evaluation bundle generation failed' }
    $bundles[$condition] = $bundlePath
}
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $UserHome '.codex' }
$halt = $false
foreach ($row in $rows) {
    if ($halt) { $row.status = 'not-run-after-failure'; continue }
    $case = @($cases | Where-Object id -CEQ $row.case_id)[0]
    $fixture = Join-Path $root ($row.case_id + '-' + $row.condition)
    Write-FleetText (Join-Path $fixture '.fleet-fixture') 'disposable-fleet-test-home'
    foreach ($path in $case.files.Keys) { Write-FleetText (Resolve-FleetPath $fixture $path) $case.files[$path] }
    Write-FleetText (Join-Path $fixture 'AGENTS.md') 'This is an isolated evaluation. Preserve tests and existing files outside the requested source ownership. No Git history changes or external side effects. Only Root may coordinate. One writer per worktree. Record unknown values honestly.'
    $init = Invoke-FleetProcess $gitPath @('init',$fixture) $kitRoot
    if ($init.exit_code -ne 0) { throw 'Evaluation fixture initialization failed' }
    if ($row.condition -ne 'A') { $null = Invoke-FleetInstall $bundles[$row.condition] $fixture -Fixture }
    $baseline = Get-FleetSnapshot $fixture
    $baselineTest = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $fixture 'tests/check.ps1')) $fixture
    Write-FleetJson (Join-Path $fixture '.fleet-runs/baseline.json') $baseline
    Write-FleetJson (Join-Path $fixture '.fleet-runs/baseline-test.json') $baselineTest
    $prompt = $case.prompt + "`nAllowed change paths: " + ($case.allowed -join ', ') + "`nVerification command: pwsh -NoProfile -File tests/check.ps1. You may record verification results under .fleet-runs."
    if ($row.condition -eq 'A') { $prompt += "`nDo not use subagents in this condition; complete the work with the parent only." }
    else { $prompt = '$fleet-orchestrator' + "`n" + $prompt + "`nUse a verified custom Agent suitable for independent research or review of significant changes. If the capability is unavailable, return blocked rather than treating a fallback as success." }
    $arguments = @('exec','--ignore-user-config','--json','--ephemeral','-m',$map.tiers.ROOT.model,'-c','model_reasoning_effort="high"','-c',('projects.' + (ConvertTo-Json $fixture.Replace('\','/') -Compress) + '.trust_level="trusted"'))
    if ($AutoReview) { $arguments += '--approve-for-me' } else { $arguments = @('-a','never') + $arguments + @('-s','workspace-write') }
    $arguments += $prompt
    Write-Host "Running $($row.case_id) condition $($row.condition)"
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $run = Invoke-FleetProcess $CodexPath $arguments $fixture @{USERPROFILE=$UserHome;CODEX_HOME=$codexHome} 600
    $timer.Stop()
    Write-FleetText (Join-Path $fixture '.fleet-runs/stdout.jsonl') $run.stdout
    Write-FleetText (Join-Path $fixture '.fleet-runs/stderr.log') $run.stderr
    $grade = Get-FleetEvaluationGrade $baseline $fixture $case.allowed $pwshPath @('-NoProfile','-File',(Join-Path $fixture 'tests/check.ps1'))
    Write-FleetJson (Join-Path $fixture '.fleet-runs/final-test.json') $grade
    $row.elapsed_seconds = $timer.Elapsed.TotalSeconds
    $row.test_exit_code = $grade.test.exit_code
    $row.fixture = $fixture
    $row.changed_paths = $grade.changed_paths
    $row.status = if ($run.timed_out) {'timed-out'} elseif ($run.exit_code -ne 0) {'runtime-failed'} else { $grade.status }
    # Externally tested artifacts do not prove delegation, close, review independence, or model resolution.
    $row.acceptance = 'requires-runtime-evidence-review'
    $row.reported_turn_usage = @($run.stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable } | Where-Object type -EQ 'turn.completed' | ForEach-Object { $_.usage })
    if ($run.timed_out -or $run.exit_code -ne 0) { $halt = $true }
    Write-FleetJson $OutputPath $report
}
$report.comparison = 'raw-observations-only; full acceptance and complete usage require independent review'
Write-FleetJson $OutputPath $report
@{status='recorded';report=$OutputPath} | ConvertTo-Json
if (@($rows | Where-Object status -NE 'artifact-verified').Count) { exit 1 }
