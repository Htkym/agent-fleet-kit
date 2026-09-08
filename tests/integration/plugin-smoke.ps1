#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$Package = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\build\plugins'),
    [string]$CopilotPath,
    [string]$Model,
    [ValidateRange(60,1800)][int]$TimeoutSeconds = 900,
    [ValidateRange(30,100)][int]$MaxAiCredits = 60,
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $kitRoot 'scripts\Fleet.psm1') -Force
$null = Get-FleetPluginPackage $Package
if (-not $CopilotPath) { $CopilotPath = (Get-Command copilot -ErrorAction Stop).Source }
$runRoot = Join-Path $kitRoot ('.local\runs\plugin-copilot\' + [guid]::NewGuid().ToString('N'))
$workspace = Join-Path $runRoot 'workspace'
$plugin = Join-Path $runRoot 'fleet-copilot'
[IO.Directory]::CreateDirectory($workspace) | Out-Null
Copy-Item -LiteralPath (Join-Path $kitRoot 'tests\fixtures\plugin-runtime\src') -Destination $workspace -Recurse
Copy-Item -LiteralPath (Join-Path $kitRoot 'tests\fixtures\plugin-runtime\tests') -Destination $workspace -Recurse
Copy-Item -LiteralPath (Join-Path $Package 'plugins\fleet-copilot') -Destination $plugin -Recurse
$node = (Get-Command node -ErrorAction Stop).Source
$testArgs = @('--test','tests\eligibility.test.cjs')
$baseline = Invoke-FleetProcess $node $testArgs $workspace
Write-FleetJson (Join-Path $runRoot 'baseline.json') $baseline
if ($baseline.exit_code -ne 1) { throw 'Expected deliberately failing fixture baseline' }
$testHash = Get-FleetHash (Join-Path $workspace 'tests\eligibility.test.cjs')
$pluginHashes = @(foreach ($file in Get-FleetFiles $plugin | Sort-Object FullName) { @{path=$file.FullName;sha256=(Get-FleetHash $file.FullName)} })
$prompt = @'
This is an explicitly authorized Fleet plugin integration test in a disposable workspace.
Use the fleet-orchestrator Skill from the fleet-copilot plugin (not a same-name global Skill).
Read its actual definition and follow it; do not simply reproduce the procedure from this prompt.
Requirements: eligible(years) returns true for integers >= 5; invalid input rejection remains.
Also uppercase the values of src/labels.json without changing its keys.
Only src/eligibility.cjs and src/labels.json may be edited. Tests and plugin assets are immutable.
The existing verification command is node --test tests\eligibility.test.cjs.
No dependencies, network access, global settings, git commits, or changes outside this fixture.
Use all seven bundled roles for this explicit integration exercise, each in a fresh child context:
Explorer investigates eligibility, Researcher independently inspects existing test requirements,
Implementer fixes only eligibility, Worker Fast performs only the fixed label transformation,
Verifier runs the real command, Reviewer reviews the integrated change, and Reviewer Critical
uses the bundled evidence-review Skill for the boundary and invalid-input contract.
Discover and use registered fleet-copilot:<role> Agents when the actual launcher supports them.
If it does not, follow the documented fallback, include the actual bundled role contract,
and explicitly report which launches were fallbacks. Do not invent supported agent_type values.
Root must assign complete task IDs, revisions, baseline hashes, ownership, and acceptance criteria.
Use at most four outstanding children, one writer at a time, and no recursive delegation.
Use sync unless there is concrete independent Root work. Do not poll known child IDs repeatedly.
Retain concise evidence under .local/evidence. Collect actual child results and preserve test hashes.
Finish with implemented behavior, actual test exit code, role identities, review findings,
and limitations. Do not claim native custom-agent invocation or thread release without evidence.
'@
$environment = @{
    COPILOT_HOME=(Join-Path $runRoot 'home')
    COPILOT_PLUGIN_DIR_ONLY='1'
    COPILOT_AUTO_UPDATE='false'
}
$arguments = @('--plugin-dir',$plugin,'--add-dir',$plugin,'--no-custom-instructions','--no-auto-update',
    '--disable-mcp-server','github-mcp-server','--no-ask-user','--allow-all-tools',
    '--max-ai-credits',[string]$MaxAiCredits,'--output-format','json',
    '--log-dir',(Join-Path $runRoot 'logs'),'--usage-output-file',(Join-Path $runRoot 'usage.json'),'-p',$prompt)
if ($Model) { $arguments += @('--model',$Model) }
$executable = $CopilotPath
if ([IO.Path]::GetExtension($CopilotPath) -eq '.ps1') {
    $executable = (Get-Command pwsh -ErrorAction Stop).Source
    $arguments = @('-NoProfile','-File',$CopilotPath) + $arguments
}
Write-FleetJson (Join-Path $runRoot 'invocation.json') @{executable=$executable;arguments=$arguments;environment=$environment;workspace=$workspace;timeout_seconds=$TimeoutSeconds}
if (-not $Execute) {
    @{status='prepared-only';run=$runRoot;inference='not-executed'} | ConvertTo-Json
    return
}
$run = Invoke-FleetProcess $executable $arguments $workspace $environment $TimeoutSeconds
Write-FleetText (Join-Path $runRoot 'events.jsonl') $run.stdout
Write-FleetText (Join-Path $runRoot 'stderr.txt') $run.stderr
$verification = Invoke-FleetProcess $node $testArgs $workspace
Write-FleetJson (Join-Path $runRoot 'verification.json') $verification
$events = @($run.stdout -split '\r?\n' | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$nativeAgents = @($events | Where-Object type -EQ 'subagent.started' | ForEach-Object { $_.data.agentName } | Sort-Object -Unique)
$completedCalls = @($events | Where-Object type -EQ 'subagent.completed')
$budgetExhausted = @($events | Where-Object { $_.type -eq 'session.warning' -and $_.data.warningType -eq 'session_limits' }).Count -gt 0
$requiredAgents = @('explorer','researcher','implementer','worker_fast','verifier','reviewer','reviewer_critical') | ForEach-Object { "fleet-copilot:fleet_$_" }
$allNativeAgents = @($requiredAgents | Where-Object { $_ -notin $nativeAgents }).Count -eq 0
$roleTools = @{}
foreach ($start in $events | Where-Object type -EQ 'subagent.started') {
    $roleTools[$start.data.agentName] = @($events | Where-Object { $_.type -eq 'tool.execution_start' -and $_.data.parentToolCallId -eq $start.data.toolCallId } | ForEach-Object { $_.data.toolName })
}
$allRolesUsedTools = @($requiredAgents | Where-Object { -not $roleTools.ContainsKey($_) -or $roleTools[$_].Count -eq 0 }).Count -eq 0
$pluginAfterPaths = @(Get-FleetFiles $plugin | Sort-Object FullName | Select-Object -ExpandProperty FullName)
$unchangedPlugin = (($pluginAfterPaths -join "`n") -ceq ($pluginHashes.path -join "`n")) -and @($pluginHashes | Where-Object { (Get-FleetHash $_.path) -cne $_.sha256 }).Count -eq 0
$report = @{
    run=$runRoot;cli_exit_code=$run.exit_code;timed_out=$run.timed_out;test_exit_code=$verification.exit_code
    tests_unchanged=((Get-FleetHash (Join-Path $workspace 'tests\eligibility.test.cjs')) -ceq $testHash)
    plugin_unchanged=$unchangedPlugin;delegation='inspect-native-events';runtime_scope='Copilot-only'
    events_recorded=(-not [string]::IsNullOrWhiteSpace($run.stdout))
    native_agents=$nativeAgents;completed_child_calls=$completedCalls.Count;budget_exhausted=$budgetExhausted
    role_tool_calls=$roleTools
    package_manifest_sha256=(Get-FleetHash (Join-Path $Package 'package-manifest.json'))
}
Write-FleetJson (Join-Path $runRoot 'report.json') $report
$report | ConvertTo-Json
if ($run.timed_out -or $run.exit_code -ne 0 -or -not $report.events_recorded -or $budgetExhausted -or -not $allNativeAgents -or -not $allRolesUsedTools -or $completedCalls.Count -lt 7 -or $verification.exit_code -ne 0 -or -not $report.tests_unchanged -or -not $unchangedPlugin) { throw "Copilot plugin runtime failed; inspect $runRoot" }
