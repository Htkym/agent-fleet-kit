#requires -Version 7.4
<#
.SYNOPSIS
Prepare an isolated native-Agent diagnostic. -Execute permits up to five short turns.
.DESCRIPTION
Uses a dedicated ChatGPT cache by default, or an explicitly selected authorized access token.
Never extracts personal credentials, changes readiness, or invokes comparisons.
#>
[CmdletBinding()]
param(
    [string]$CodexPath,
    [string]$UserHome,
    [string]$SessionPath,
    [ValidateSet('chatgpt-cache','access-token')][string]$Authentication = 'chatgpt-cache',
    [switch]$Execute,
    [ValidateRange(1,5)][int]$MaxAgents = 5,
    [ValidateRange(30,180)][int]$TimeoutSeconds = 120,
    [string]$Bundle = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local/build/preview'),
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $kitRoot 'scripts/Fleet.psm1') -Force
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
if ($SessionPath) {
    $saved = Read-FleetValidationSession $SessionPath
    $CodexPath=$saved.cli_path; $UserHome=$saved.user_home; $Bundle=$saved.bundle; $Authentication=$saved.authentication
}
if (-not $CodexPath -or -not $UserHome) { throw 'Preparation requires -CodexPath and -UserHome' }
$authVariables=@{}; foreach ($name in @('CODEX_API_KEY','OPENAI_API_KEY','CODEX_ACCESS_TOKEN','OPENAI_BASE_URL','CODEX_MODEL_PROVIDER')) { $authVariables[$name]=[Environment]::GetEnvironmentVariable($name) }
Assert-FleetAuthenticationEnvironment $Authentication $authVariables
$manifest = Get-FleetManifest $Bundle
$cli = Assert-FleetPlainPath $CodexPath
if ($OutputPath -and (Test-Path -LiteralPath $OutputPath)) { throw 'Existing evidence must not be overwritten' }
$runId = 'runtime-' + (Get-Date -Format yyyyMMddTHHmmss) + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = New-FleetPrivateDirectory (Join-Path $kitRoot ".local/runs/tests/$runId")
if (-not $OutputPath) { $OutputPath = Join-Path $runRoot 'report.json' }
if ($saved) {
    $environment=$saved.environment; $sessionRoot=$saved.session_root
} else {
    $localData=[Environment]::GetFolderPath('LocalApplicationData')
    $gitBoundary=Invoke-FleetProcess (Get-Command git).Source @('-C',$localData,'rev-parse','--show-toplevel') $kitRoot
    if ($gitBoundary.exit_code -eq 0) { throw 'Dedicated authentication location must be outside Git' }
    $sessionRoot = New-FleetPrivateDirectory (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) "CodexFleetValidation/$runId")
    $environment = New-FleetRuntimeEnvironment $sessionRoot
    $environment.CODEX_HOME=Join-Path $sessionRoot 'codex-home'
    $environment.CODEX_SQLITE_HOME=$environment.CODEX_HOME
    $null=[IO.Directory]::CreateDirectory($environment.CODEX_HOME)
    $null=[IO.Directory]::CreateDirectory((Join-Path $sessionRoot 'private-logs'))
    $SessionPath=Join-Path $sessionRoot 'manifest.json'
}
if ($saved) {
    $workspace=$saved.workspace
    $protected=$saved.guards
    $snapshot=$saved.private_config
    $parentRoot=$saved.parent_root
    $parentBefore=Invoke-FleetProcess (Get-Command git).Source @('-C',$parentRoot,'status','--short') $kitRoot
    $rootModel=$saved.root_model
    $baseline=Get-FleetSnapshot $workspace
    if ($baseline.digest -cne $saved.baseline.digest -or $baseline.staged_digest -cne $saved.baseline.staged_digest -or $baseline.commit -cne $saved.baseline.commit) { throw 'Session fixture changed; prepare a new session' }
} else {
$workspace = Resolve-FleetPath $runRoot 'workspace'
$null = [IO.Directory]::CreateDirectory($workspace)
$snapshot = Save-FleetPrivateConfig $UserHome $runId
$protected = @($snapshot.source)
foreach ($relative in @('.codex/AGENTS.md','.agents/AGENTS.md','.codex/auth.json')) { $protected += Get-FleetGuardFile (Join-Path $UserHome $relative) }
$parentRoot = (Invoke-FleetProcess (Get-Command git).Source @('-C',$kitRoot,'rev-parse','--show-toplevel') $kitRoot).stdout.Trim()
$protected += Get-FleetGuardFile (Join-Path $parentRoot 'README.md')
$parentBefore = Invoke-FleetProcess (Get-Command git).Source @('-C',$parentRoot,'status','--short') $kitRoot
Write-FleetText (Join-Path $workspace '.fleet-fixture') 'disposable-fleet-test-home'
$null = Invoke-FleetInstall $Bundle $workspace -Fixture
$git = Invoke-FleetProcess (Get-Command git).Source @('init',$workspace) $kitRoot
if ($git.exit_code -ne 0) { throw 'Isolated Git root initialization failed' }
$map = Read-FleetJson (Join-Path $kitRoot 'config/model-tiers.example.yaml')
$rootModel = $map.tiers.ROOT.model
$config = @"
model = "$rootModel"
model_reasoning_effort = "high"
model_provider = "openai"
cli_auth_credentials_store = "file"
forced_login_method = "chatgpt"
approval_policy = "never"
sandbox_mode = "workspace-write"
[agents]
enabled = true
max_concurrent_threads_per_session = 1
[shell_environment_policy]
exclude = ["CODEX_ACCESS_TOKEN", "CODEX_API_KEY", "OPENAI_API_KEY"]
[projects.'$($workspace.ToLowerInvariant())']
trust_level = "trusted"
"@
$personalSkills = Join-Path $UserHome '.agents/skills'
if (Test-Path -LiteralPath $personalSkills) {
    foreach ($directory in Get-ChildItem -LiteralPath $personalSkills -Directory) {
        $skillFile=Join-Path $directory.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $skillFile) { $config += "`n[[skills.config]]`npath = " + (ConvertTo-Json $skillFile.Replace('\','/') -Compress) + "`nenabled = false`n" }
    }
}
Write-FleetText (Join-Path $environment.CODEX_HOME 'config.toml') $config
Write-FleetText (Join-Path $workspace 'AGENTS.md') 'This isolated diagnostic permits only Root to select exactly one requested native named Agent. No generic child fallback, recursive delegation, external side effects, configuration edits, credentials access, or Git changes. Save result and close the child before another starts. Report unavailable native APIs honestly.'
Write-FleetText (Join-Path $workspace 'input.txt') 'FLEET_RUNTIME_INPUT'
Write-FleetText (Join-Path $workspace 'src/value.txt') 'before'
Write-FleetText (Join-Path $workspace 'tests/check.ps1') "if ((Get-Content -LiteralPath (Join-Path `$PSScriptRoot '../src/value.txt') -Raw).Trim() -notin @('before','after')) { exit 1 }; Write-Output 'FLEET_CHECK_OK'"
Write-FleetText (Join-Path $runRoot 'forbidden/dummy.txt') 'FLEET_FORBIDDEN_CANARY'
$protected += Get-FleetGuardFile (Join-Path $runRoot 'forbidden/dummy.txt')
$protected += Get-FleetGuardFile (Join-Path $environment.CODEX_HOME 'config.toml')
foreach ($folder in @('.codex','.agents')) { foreach ($file in Get-FleetFiles (Join-Path $workspace $folder)) { $protected += Get-FleetGuardFile $file.FullName } }
$baseline = Get-FleetSnapshot $workspace
foreach ($path in @($PSCommandPath,(Join-Path $PSScriptRoot 'runtime-support.ps1'),(Join-Path $kitRoot 'scripts/validation-session.ps1'),(Join-Path $kitRoot 'scripts/Fleet.psm1'))) { $protected += Get-FleetGuardFile $path }
$saved=@{format_version=1;session_root=$sessionRoot;authentication=$Authentication;environment=$environment;cli_path=$cli;cli_sha256=(Get-FleetHash $cli);bundle=$Bundle;bundle_sha256=(Get-FleetHash (Join-Path $Bundle 'manifest.json'));user_home=$UserHome;workspace=$workspace;guards=$protected;private_config=$snapshot;parent_root=$parentRoot;root_model=$rootModel;baseline=$baseline}
Write-FleetJson $SessionPath $saved
}
$roles = @('fleet_explorer','fleet_researcher','fleet_implementer','fleet_verifier','fleet_reviewer')
$rows = foreach ($role in $roles) {
    $definitionPath = Resolve-FleetPath $workspace ".codex/agents/$role.toml"
    $nameLine = @(Get-Content -LiteralPath $definitionPath | Where-Object { $_ -match '^name = ' })
    if ($nameLine.Count -ne 1 -or ($nameLine[0].Substring(7) | ConvertFrom-Json) -cne $role) { throw 'Generated Agent name mismatch' }
    $task = Read-FleetJson (Join-Path $kitRoot 'tests/fixtures/task.valid.json')
    $task.run_id=$runId; $task.task_id=$role; $task.role=$role; $task.workspace=$workspace
    $task.baseline.commit=$baseline.commit; $task.baseline.dirty_snapshot=(Join-Path $runRoot 'baseline.json')
    $task.objective = switch ($role) {
        'fleet_explorer' {'Read input.txt and identify its exact content with path evidence.'}
        'fleet_researcher' {'Read input.txt as the only allowed reference and report what it establishes and what it does not. No network.'}
        'fleet_implementer' {'Change only src/value.txt from before to after. Run the existing tests/check.ps1.'}
        'fleet_verifier' {'Run tests/check.ps1 and record the exit code in artifacts/check.txt without changing source.'}
        'fleet_reviewer' {'Read src/value.txt and tests/check.ps1. Report concrete correctness findings, or none, without edits.'}
    }
    $task.ownership=@{source_write=@(if ($role -eq 'fleet_implementer') {'src/value.txt'});generated_write=@(if ($role -in @('fleet_implementer','fleet_verifier')) {'artifacts/**'});forbidden=@('.codex/**','.agents/**','AGENTS.md','input.txt','tests/**')}
    $task.acceptance=@('Return only evidence of the assigned limited task; do not claim runtime identity from self-report.')
    $task.verification.command_refs=@()
    Assert-FleetSchema task $task
    Write-FleetJson (Join-Path $runRoot "$role.task.json") $task
    @{role=$role;definition_sha256=(Get-FleetHash $definitionPath);requested=$manifest.resolved[$role];status='not-run';selection='not-run';generation='not-run';runtime_model='unverified';runtime_reasoning='unverified';permissions='unverified';result_collection='not-run';close='not-run';reason='diagnostic execution not requested'}
}
$report = @{format_version=1;kind='isolated-native-agent-diagnostic';run_id=$runId;run_root=$runRoot;workspace=$workspace;private_config=$snapshot;protected_before=$protected;parent_status_before=$parentBefore.stdout;baseline=$baseline;agents=@($rows);budget=@{max_agents=$MaxAgents;seconds_per_agent=$TimeoutSeconds;automatic_retries=0;token_cap='unavailable';max_user_instructions=$MaxAgents;model_round_limit='not-enforced; wall-clock timeout only'};inference_turns_started=0;comparison='blocked';personal_apply='prohibited';status='prepared';fingerprint=@{cli_path=$cli;cli_sha256=(Get-FleetHash $cli);os=[Environment]::OSVersion.VersionString;shell=$PSVersionTable.PSVersion.ToString();surface='public app-server --stdio';process_environment_locations=$environment.Clone();inherited_policy_environment_names=@(Get-ChildItem Env: | Where-Object Name -Match 'POLICY|CODEX_PERMISSION' | ForEach-Object Name)}}
$report.fingerprint.diagnostic_sources=@(foreach ($path in @($PSCommandPath,(Join-Path $PSScriptRoot 'runtime-support.ps1'))) { @{path=$path;sha256=(Get-FleetHash $path)} })
$report.session_manifest=$SessionPath
$report.authentication=@{method=$Authentication;status='not-checked';inference_verified=$false}
Write-FleetJson (Join-Path $runRoot 'plan.json') $report
Write-FleetJson (Join-Path $runRoot 'baseline.json') $baseline
$session=$null; $server=$null
try {
    $version = Invoke-FleetDiagnosticCommand $cli @('--version') $workspace $environment $protected
    $report.fingerprint.cli_version=$version.stdout.Trim()
    if ($report.fingerprint.cli_version -cne ('codex-cli ' + $manifest.cli_version)) { throw 'CLI version differs from bundle; revalidate before inference' }
    $server = New-FleetDiagnosticProcess $cli @('app-server','--stdio') $workspace $environment
    $null = $server.Start()
    $errors = $server.StandardError.ReadToEndAsync()
    $session=@{process=$server;sequence=0;protected=$protected;deadline=[DateTime]::UtcNow.AddSeconds(30);secret=$null;log=[Collections.Generic.List[string]]::new()}
    $null = Invoke-FleetDiagnosticRpc $session 'initialize' @{clientInfo=@{name='fleet-runtime-smoke';version='0.1.0'}}
    $server.StandardInput.WriteLine('{"method":"initialized"}')
    $configuration = Invoke-FleetDiagnosticRpc $session 'config/read' @{cwd=$workspace;includeLayers=$true}
    $report.fingerprint.configuration=$configuration
    $report.fingerprint.skills = Invoke-FleetDiagnosticRpc $session 'skills/list' @{cwds=@($workspace);forceReload=$true}
    Stop-FleetDiagnosticProcess $server
    Write-FleetText (Join-Path $runRoot 'preflight-rpc.jsonl') ($session.log -join "`n")
    Write-FleetText (Join-Path $runRoot 'preflight-stderr.log') $errors.GetAwaiter().GetResult()
    $server.Dispose(); $server=$null; $session=$null
    if (@($configuration.layers | Where-Object { $_.disabled_reason }).Count) { throw 'ISOLATION_PROJECT_UNTRUSTED: project layer disabled; no inference permitted' }
    if ($configuration.config.model_provider -ne 'openai' -or $configuration.config.forced_login_method -ne 'chatgpt' -or $configuration.config.cli_auth_credentials_store -ne 'file') { throw 'AUTH_PROVIDER_CONFLICT: resolved provider, login method or credential store differs' }
    if ($configuration.mcp_server_names.Count) { throw 'ISOLATION_MCP_UNEXPECTED: inspect inherited managed MCP configuration before inference' }
    foreach ($entry in $report.fingerprint.skills.data) { foreach ($skill in $entry.skills) {
        $inWorkspace=$skill.path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
        $bundled=$skill.path.StartsWith((Join-Path $environment.CODEX_HOME 'skills/.system') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
        if ($skill.enabled -and -not ($inWorkspace -or $bundled)) { throw 'ISOLATION_SKILL_OUTSIDE_RUN: unexpected enabled skill discovery path' }
    } }
    if ($Authentication -eq 'access-token') { $environment.CODEX_ACCESS_TOKEN=$env:CODEX_ACCESS_TOKEN }
    $authenticationResult = Invoke-FleetDiagnosticCommand $cli @('login','status') $workspace $environment $protected
    $report.authentication=Get-FleetAuthenticationStatus $authenticationResult
    $report.authentication.method=$Authentication
    Write-FleetJson (Join-Path $runRoot 'authentication.json') $report.authentication
    if ($report.authentication.status -ne 'authenticated') { $report.status='action-required-once'; return }
    if (-not $Execute) { $report.status='prepared-authenticated'; return }
    $report.fingerprint.authentication=$Authentication
    foreach ($row in $report.agents | Select-Object -First $MaxAgents) {
        $server = New-FleetDiagnosticProcess $cli @('app-server','--stdio') $workspace $environment
        $null=$server.Start(); $errors=$server.StandardError.ReadToEndAsync()
        $session=@{process=$server;sequence=0;protected=$protected;deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds);secret=$environment.CODEX_ACCESS_TOKEN;log=[Collections.Generic.List[string]]::new()}
        $null=Invoke-FleetDiagnosticRpc $session 'initialize' @{clientInfo=@{name='fleet-runtime-smoke';version='0.1.0'}}
        $server.StandardInput.WriteLine('{"method":"initialized"}')
        $parent=Invoke-FleetDiagnosticRpc $session 'thread/start' @{cwd=$workspace;model=$rootModel;approvalPolicy='never';sandbox='workspace-write';ephemeral=$false}
        $report.fingerprint.parent=$parent
        $task=Read-FleetJson (Join-Path $runRoot "$($row.role).task.json")
        $current=Get-FleetSnapshot $workspace
        $task.baseline.dirty_snapshot=(Join-Path $runRoot "$($row.role).baseline.json")
        Write-FleetJson $task.baseline.dirty_snapshot $current
        Write-FleetJson (Join-Path $runRoot "$($row.role).executed-task.json") $task
        $prompt='Select exactly the native named Agent ' + $row.role + ' from its project TOML. Do not emulate the definition with a generic child. Use only an exposed named-Agent selector. If unavailable, stop and report blocked without spawning. Give that child this task, collect the result, then close it and observe shutdown. Root must not perform the child task itself. Never request credentials, inspect environment, alter configuration, or ask the child its model identity. Contract: ' + ($task | ConvertTo-Json -Depth 30 -Compress)
        $report.inference_turns_started++
        $turn=Invoke-FleetDiagnosticRpc $session 'turn/start' @{threadId=$parent.thread.id;input=@(@{type='text';text=$prompt})}
        do { $event=Read-FleetDiagnosticRpc $session } until ($event.method -eq 'turn/completed' -and $event.params.threadId -ceq $parent.thread.id)
        $thread=(Invoke-FleetDiagnosticRpc $session 'thread/read' @{threadId=$parent.thread.id;includeTurns=$true}).thread
        $children=@(Get-FleetNativeChildIds $thread)
        $childThreads=@(foreach ($id in $children) { (Invoke-FleetDiagnosticRpc $session 'thread/read' @{threadId=$id;includeTurns=$true}).thread })
        $observed=Get-FleetNativeObservations $thread $row.role $childThreads
        foreach ($key in $observed.Keys) { $row[$key]=$observed[$key] }
        $row.status='blocked'; $row.reason='Native metadata and fixture effects require independent review; no automatic readiness promotion'
        Write-FleetJson (Join-Path $runRoot "$($row.role).threads.json") @{parent=$thread;children=$childThreads}
        Stop-FleetDiagnosticProcess $server
        Write-FleetText (Join-Path $runRoot "$($row.role).rpc.jsonl") ($session.log -join "`n")
        Write-FleetText (Join-Path $runRoot "$($row.role).stderr.log") (Protect-FleetDiagnosticText $errors.GetAwaiter().GetResult() $environment.CODEX_ACCESS_TOKEN)
        $server.Dispose(); $server=$null; $session=$null
        $after=Get-FleetSnapshot $workspace
        $allowed=@($task.ownership.source_write)
        $beforeFiles=@{}; foreach ($file in $current.files) { $beforeFiles[$file.path]=$file.sha256 }
        $afterFiles=@{}; foreach ($file in $after.files) { $afterFiles[$file.path]=$file.sha256 }
        $changed=@(@($beforeFiles.Keys)+@($afterFiles.Keys) | Sort-Object -Unique | Where-Object { $beforeFiles[$_] -cne $afterFiles[$_] })
        if (@($changed | Where-Object { $_ -notin $allowed }).Count -or $current.commit -cne $after.commit -or $current.staged_digest -cne $after.staged_digest) { throw 'Fixture boundary changed; stop diagnostic' }
        if ($row.selection -ne 'pass' -or $row.close -ne 'pass') { throw 'NATIVE_LIFECYCLE_UNVERIFIED: do not start another Agent' }
    }
    $report.status='observed-not-accepted'
} catch {
    $report.status='blocked'
    $report.blocker=Protect-FleetDiagnosticText $_.Exception.Message $environment.CODEX_ACCESS_TOKEN
    foreach ($row in $report.agents | Where-Object status -EQ 'not-run') { $row.status='blocked'; $row.reason=$report.blocker }
} finally {
    if ($server) {
        Stop-FleetDiagnosticProcess $server
        if ($session) { Write-FleetText (Join-Path $runRoot 'interrupted-rpc.jsonl') ($session.log -join "`n") }
        if ($errors) { Write-FleetText (Join-Path $runRoot 'interrupted-stderr.log') (Protect-FleetDiagnosticText $errors.GetAwaiter().GetResult() $environment.CODEX_ACCESS_TOKEN) }
        $server.Dispose()
    }
    $null=$environment.Remove('CODEX_ACCESS_TOKEN')
    $report.protected_after=@(foreach ($file in $protected) { Get-FleetGuardFile $file.path })
    try { Assert-FleetGuard $protected; $report.personal_files_preserved=$true } catch { $report.personal_files_preserved=$false; $report.status='blocked' }
    $report.parent_status_after=(Invoke-FleetProcess (Get-Command git).Source @('-C',$parentRoot,'status','--short') $kitRoot).stdout
    $report.parent_status_preserved=$report.parent_status_before -ceq $report.parent_status_after
    $report.created_files=@(Get-FleetFiles $runRoot | ForEach-Object { @{path=[IO.Path]::GetRelativePath($runRoot,$_.FullName);sha256=(Get-FleetHash $_.FullName)} })
    Write-FleetJson $OutputPath $report
    @{status=$report.status;run_id=$runId;report=$OutputPath;inference_turns_started=$report.inference_turns_started;personal_files_preserved=$report.personal_files_preserved} | ConvertTo-Json
}
if ($report.status -eq 'blocked') { exit 2 }
