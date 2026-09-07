#requires -Version 7.4
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$kitRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $kitRoot 'scripts/Fleet.psm1') -Force
. (Join-Path $PSScriptRoot 'evals/grade.ps1')
. (Join-Path $PSScriptRoot 'integration/runtime-support.ps1')
$runRoot = Join-Path $kitRoot ('.local/runs/tests/' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($runRoot) | Out-Null
$script:checks = [Collections.Generic.List[object]]::new()
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Reason) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert $rejected $Reason
}
function Check([string]$Name, [string[]]$Acceptance, [scriptblock]$Body) {
    try {
        & $Body | Out-Null
        $script:checks.Add(@{name=$Name;acceptance=$Acceptance;status='passed';error=$null})
        Write-Host "PASS $Name"
    } catch {
        $script:checks.Add(@{name=$Name;acceptance=$Acceptance;status='failed';error=$_.Exception.Message})
        Write-Host "FAIL $Name : $($_.Exception.Message)"
    }
}
function Clone($Value) { $Value | ConvertTo-Json -Depth 60 | ConvertFrom-Json -AsHashtable }
function New-TestHome([string]$Name) {
    $path = Join-Path $runRoot $Name
    Write-FleetText (Join-Path $path '.fleet-fixture') 'disposable-fleet-test-home'
    $path
}
$task = Read-FleetJson (Join-Path $PSScriptRoot 'fixtures/task.valid.json')
$task.workspace = Join-Path $runRoot 'work 空白 日本語'
[IO.Directory]::CreateDirectory($task.workspace) | Out-Null
$result = Read-FleetJson (Join-Path $PSScriptRoot 'fixtures/result.unverified.json')
$revision = $result.observed_revision
$state = Read-FleetJson (Join-Path $PSScriptRoot 'fixtures/state.valid.json')
$bundle = Join-Path $runRoot 'bundle'
$pwshPath = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshPath)) { $pwshPath = Join-Path $PSHOME 'pwsh' }

Check 'valid task/result/state schemas' @('A29') {
    Assert-FleetSchema task $task
    Assert-FleetSchema task-result $result
    Assert-FleetSchema run-state $state
}
Check 'missing field and unknown property rejected' @('A29') {
    $invalid = Clone $task; $invalid.Remove('ownership')
    Reject { Assert-FleetSchema task $invalid } 'Missing ownership accepted'
    $invalid = Clone $task; $invalid.api_spawn_argument = $true
    Reject { Assert-FleetSchema task $invalid } 'Unknown field accepted'
}
Check 'false success rejected by schema' @('A20','A29') {
    $invalid = Clone $result; $invalid.verification[0].status = 'passed'
    Reject { Assert-FleetSchema task-result $invalid } 'Missing execution evidence accepted'
}
Check 'argv permits repeated options and rejects empty command' @('A29') {
    $valid = Clone $result; $valid.verification[0].command = @('codex','-c','a=1','-c','b=2')
    Assert-FleetSchema task-result $valid
    $valid.verification[0].command = @()
    Reject { Assert-FleetSchema task-result $valid } 'Empty argv accepted'
}
Check 'unverified result cannot be accepted' @('A20') {
    Reject { Assert-FleetResult $task $result $revision $runRoot @() } 'Unexecuted test accepted'
}
Check 'stale task revision and run ID rejected' @('A25') {
    $invalid = Clone $result; $invalid.task_revision = 2
    Reject { Assert-FleetResult $task $invalid $revision $runRoot @() } 'Stale task accepted'
    $invalid = Clone $result; $invalid.run_id = 'other'
    Reject { Assert-FleetResult $task $invalid $revision $runRoot @() } 'Wrong run accepted'
}
Check 'path traversal ADS reserved names rejected' @('A13','A32') {
    foreach ($path in @('../escape','src/../../escape','C:/escape','src/file:stream','src/CON.txt','src/file.','src//file','src/./file')) {
        Reject { Resolve-FleetPath $task.workspace $path } "Unsafe path accepted: $path"
    }
}
Check 'Japanese spaces long paths and case folding' @('A32') {
    $relative = 'src/' + (('長いパス directory/' * 12)) + '日本語 file.txt'
    $path = Resolve-FleetPath $task.workspace $relative
    Write-FleetText $path '改行と文字コードを保持する。'
    Assert ([IO.File]::ReadAllText($path) -ceq '改行と文字コードを保持する。') 'UTF-8 round trip failed'
    Assert-FleetOwnership $task @('SRC/Hello.ps1')
    Reject { Assert-FleetOwnership $task @('src/Hello.ps1','SRC/hello.ps1') } 'Case alias accepted'
}
Check 'forbidden shared paths and unsupported globs' @('A13','A19') {
    Reject { Assert-FleetOwnership $task @('src/shared/api.ps1') } 'Forbidden file accepted'
    Reject { Assert-FleetOwnership $task @('lock.json') } 'Unowned shared file accepted'
    Reject { Test-FleetPattern 'src/file.ps1' 'src/*.ps1' } 'Unsupported glob accepted'
}
Check 'read-only role and verifier source boundary' @('A13','A17') {
    $read = Clone $task; $read.role = 'fleet_reviewer'
    Reject { Assert-FleetOwnership $read @('src/file.ps1') } 'Reviewer source write accepted'
    $read.role = 'fleet_verifier'
    Reject { Assert-FleetOwnership $read @('src/file.ps1') } 'Verifier source write accepted'
    Assert-FleetOwnership $read @('artifacts/result.txt')
}
Check 'junction alias rejected' @('A32') {
    $outside = Join-Path $runRoot 'junction target'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    $junction = Join-Path $task.workspace 'alias'
    New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
    Reject { Resolve-FleetPath $task.workspace 'alias/file.txt' } 'Junction accepted'
}
Check 'hardlink alias rejected' @('A32') {
    $source = Join-Path $runRoot 'hardlink-source.txt'
    Write-FleetText $source 'keep'
    $alias = Join-Path $task.workspace 'hardlink.txt'
    New-Item -ItemType HardLink -Path $alias -Target $source | Out-Null
    Reject { Resolve-FleetPath $task.workspace 'hardlink.txt' } 'Hardlink accepted'
}
Check 'evidence writers reject junction redirection' @('A13','A32') {
    $outside = Join-Path $runRoot 'evidence target'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    $redirect = Join-Path $task.workspace 'evidence-alias'
    New-Item -ItemType Junction -Path $redirect -Target $outside | Out-Null
    Reject { Write-FleetText (Join-Path $redirect 'stdout.log') 'data' } 'Log followed junction'
    Reject { Write-FleetJson (Join-Path $redirect 'result.json') @{passed=$true} } 'JSON followed junction'
    Assert (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Evidence escaped fixture'
}
Check 'state gates and explicit retry' @('A20','A26') {
    $item = Clone $state.tasks[0]
    Reject { Set-FleetTaskState $item accepted -RootAccepted } 'Skipped states accepted'
    foreach ($next in @('ready','running','completed')) { $null = Set-FleetTaskState $item $next }
    Reject { Set-FleetTaskState $item verified } 'Missing evidence gate accepted'
    $null = Set-FleetTaskState $item verified -EvidenceChecked
    Reject { Set-FleetTaskState $item accepted } 'Child accepted its own work'
    $null = Set-FleetTaskState $item accepted -RootAccepted
    Reject { Set-FleetTaskState $item running } 'Implicit retry accepted'
}
Check 'dependency and single writer readiness gates' @('A04','A11','A19','A25') {
    $runState = Clone $state
    $work = Clone $task
    Assert (Assert-FleetReady $work $runState -OpenChildThreads 0 -RootWriterActive $false) 'Ready task rejected'
    $work.depends_on = @('T-missing')
    Reject { Assert-FleetReady $work $runState -OpenChildThreads 0 -RootWriterActive $false } 'Missing dependency accepted'
    $work.depends_on = @()
    $runState.tasks[0].state = 'running'
    $runState.tasks[0].writer = $true
    Reject { Assert-FleetReady $work $runState -OpenChildThreads 0 -RootWriterActive $false } 'Concurrent source writer accepted'
    $runState.tasks[0].state = 'completed'
    Reject { Assert-FleetReady $work $runState -OpenChildThreads 4 -RootWriterActive $false } 'Completed but open children were ignored'
    Reject { Assert-FleetReady $work $runState -OpenChildThreads 0 -RootWriterActive $true } 'Root writer was ignored'
}
Check 'actual command evidence and immutable revision' @('A20','A23') {
    $executed = Invoke-FleetProcess $pwshPath @('-NoProfile','-Command','Write-Output 42') $task.workspace
    Assert ($executed.exit_code -eq 0) 'Command failed'
    Write-FleetText (Join-Path $runRoot 'verification.log') $executed.stdout
    $valid = Clone $result
    $valid.verification[0] = @{
        command_ref='unit';command=@($pwshPath,'-NoProfile','-Command','Write-Output 42');exit_code=0;status='passed'
        artifact='verification.log';sha256=(Get-FleetHash (Join-Path $runRoot 'verification.log'));not_run_reason=$null
        revision=$revision;failure_class='none'
    }
    $external = Clone $valid.verification[0]
    Assert (Assert-FleetResult $task $valid $revision $runRoot @($external)) 'Valid evidence rejected'
    $unexpected = Clone $valid
    $unexpected.verification += (Clone $valid.verification[0])
    $unexpected.verification[1].command_ref = 'unassigned'
    Reject { Assert-FleetResult $task $unexpected $revision $runRoot @($external) } 'Unassigned verification claim accepted'
    Reject { Assert-FleetResult $task $valid $revision $runRoot @() } 'Self-report accepted without execution record'
    $other = Clone $revision; $other.digest = 'b' * 64
    Reject { Assert-FleetResult $task $valid $other $runRoot @($external) } 'Different revision accepted'
    Write-FleetText (Join-Path $runRoot 'verification.log') 'edited'
    Reject { Assert-FleetResult $task $valid $revision $runRoot @($external) } 'Modified evidence accepted'
}
Check 'native evidence rejects generic extra or unclosed children' @('A06','A12','A20','A28') {
    $thread=@{id='root';turns=@(@{items=@(
        @{type='collabAgentToolCall';tool='spawnAgent';status='completed';senderThreadId='root';receiverThreadIds=@('child');agentsStates=@{}},
        @{type='collabAgentToolCall';tool='closeAgent';status='completed';senderThreadId='root';receiverThreadIds=@('child');agentsStates=@{child=@{status='shutdown'}}}
    )})}
    $children=@(@{id='child';parentThreadId='root';agentRole='fleet_explorer';model='gpt-5.6-terra';reasoningEffort='medium'})
    $observed=Get-FleetNativeObservations $thread 'fleet_explorer' $children
    Assert ($observed.selection -eq 'pass' -and $observed.close -eq 'pass' -and -not $observed.accepted -and $observed.runtime_model -eq 'unverified') 'Configured metadata was promoted to runtime acceptance'
    $extra=Clone $thread; $extra.turns[0].items[0].receiverThreadIds += 'generic'
    $observed=Get-FleetNativeObservations $extra 'fleet_explorer' $children
    Assert ($observed.selection -eq 'blocked' -and $observed.close -eq 'blocked') 'Extra child was ignored'
    $children[0].agentRole='default'
    Assert ((Get-FleetNativeObservations $thread 'fleet_explorer' $children).selection -eq 'blocked') 'Generic fallback accepted'
    $children[0].agentRole='fleet_explorer'; $thread.turns[0].items[1].agentsStates.child.status='completed'
    Assert ((Get-FleetNativeObservations $thread 'fleet_explorer' $children).close -eq 'blocked') 'Completed treated as shutdown'
    $activity=@{id='root';turns=@(@{items=@(
        @{type='subAgentActivity';kind='started';agentThreadId='child';agentPath='/root/fleet_explorer'},
        @{type='subAgentActivity';kind='completed';agentThreadId='child';agentPath='/root/fleet_explorer'}
    )})}
    $observed=Get-FleetNativeObservations $activity 'fleet_explorer' $children
    Assert ($observed.selection -eq 'pass' -and $observed.child_thread_ids.Count -eq 1 -and $observed.close -eq 'blocked') 'Activity event lost child or inferred close'
    $children[0].agentRole='default'
    Assert ((Get-FleetNativeObservations $activity 'fleet_explorer' $children).selection -eq 'blocked') 'Activity path was treated as named definition proof'
}
Check 'diagnostic configuration projection omits managed secret values' @('A18','A28') {
    $response=@{id=1;result=@{config=@{model='gpt-6-astra';model_provider='openai';model_reasoning_effort='high';sandbox_mode='read-only';approval_policy='never';approvals_reviewer='user';agents=@{enabled=$true;secret='CANARY_AGENT_SECRET'};shell_environment_policy=@{inherit='all';exclude=@();set=@{PASSWORD='CANARY_PASSWORD'}};mcp_servers=@{}};layers=@(@{name=@{type='system';file='system.toml'};version='one';disabledReason=$null;config=@{secret='CANARY_LAYER_SECRET'}})}}
    $reader=[IO.StringReader]::new(($response | ConvertTo-Json -Depth 30 -Compress))
    $session=@{process=@{StandardOutput=$reader};protected=@();deadline=[DateTime]::UtcNow.AddSeconds(3);secret=$null;log=[Collections.Generic.List[string]]::new();current_id=1;current_method='config/read'}
    $safe=Read-FleetDiagnosticRpc $session
    $json=$safe | ConvertTo-Json -Depth 30 -Compress
    Assert ($json -notmatch 'CANARY_' -and ($session.log -join '') -notmatch 'CANARY_') 'Managed secret copied into diagnostic'
    Assert ($safe.result.config.shell_environment_policy.set_names -contains 'PASSWORD') 'Safe field names missing'
    $reader.Dispose()
}
Check 'diagnostic detects protected file change and stops its own process' @('A16','A24','A30') {
    $guardPath=Join-Path $runRoot 'guard.txt'; Write-FleetText $guardPath 'before'
    $markerPath=Join-Path $runRoot 'must-not-run.txt'
    $scriptPath=Join-Path $runRoot 'change-guard.ps1'
    Write-FleetText $scriptPath "[IO.File]::WriteAllText('$guardPath','after'); Start-Sleep -Seconds 10; [IO.File]::WriteAllText('$markerPath','bad')"
    $watch=[Diagnostics.Stopwatch]::StartNew()
    Reject { Invoke-FleetDiagnosticCommand $pwshPath @('-NoProfile','-File',$scriptPath) $runRoot @{} @((Get-FleetGuardFile $guardPath)) 15 } 'Guard change did not stop process'
    Assert ($watch.Elapsed.TotalSeconds -lt 8 -and -not (Test-Path $markerPath)) 'Owned process continued after guard failure'
}
Check 'config backup is encrypted restricted and round trips without changing source' @('A30') {
    $homePath=Join-Path $runRoot 'private-config-home'
    $missing=Save-FleetPrivateConfig $homePath 'absent-config'
    Assert (-not $missing.source.exists -and $null -eq $missing.path -and -not (Test-Path $homePath)) 'Missing config created files or a backup'
    Assert-FleetGuard @($missing.source)
    Write-FleetText (Join-Path $homePath '.codex/config.toml') 'secret = "CANARY_CONFIG"'
    Reject { Assert-FleetGuard @($missing.source) } 'Unexpected config creation was not detected'
    $beforeHash=Get-FleetHash (Join-Path $homePath '.codex/config.toml')
    $saved=Save-FleetPrivateConfig $homePath 'fixture-snapshot'
    Assert ($saved.stable -and $saved.sha256 -ceq $beforeHash -and (Get-FleetHash (Join-Path $homePath '.codex/config.toml')) -ceq $beforeHash) 'Snapshot changed source'
    Assert (([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($saved.path))) -notmatch 'CANARY_CONFIG') 'Plaintext backup leaked'
    Reject { Save-FleetPrivateConfig $homePath 'fixture-snapshot' } 'Existing backup overwritten'
}
Check 'strict render refuses unverified model tier' @('A09','A10') {
    $run = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $kitRoot 'scripts/render.ps1'),'-OutputDirectory',$bundle) $kitRoot
    Assert ($run.exit_code -ne 0 -and $run.stderr.Contains('Unverified model tier')) 'Unverified production generation accepted'
}
Check 'preview generation includes seven agents three skills and legacy manifests' @('A06','A09') {
    $run = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $kitRoot 'scripts/render.ps1'),'-Preview','-OutputDirectory',$bundle) $kitRoot
    Assert ($run.exit_code -eq 0) $run.stderr
    $manifest = Get-FleetManifest $bundle
    Assert (-not $manifest.installable) 'Preview marked installable'
    Assert (@($manifest.files | Where-Object path -Like '.codex/agents/*').Count -eq 7) 'Agent count mismatch'
    Assert (@($manifest.files | Where-Object path -Like '.agents/skills/*/SKILL.md').Count -eq 3) 'Skill count mismatch'
    if (Test-Path (Join-Path $kitRoot '.local/archive/build/personal/manifest.json')) { $null=Get-FleetManifest (Join-Path $kitRoot '.local/archive/build/personal') }
    $critical=Clone $task; $critical.role='fleet_reviewer_critical'
    Assert-FleetSchema task $critical
    Reject { Assert-FleetOwnership $critical @('src/main.txt') } 'Critical reviewer source write accepted'
    $worker=Clone $task; $worker.role='fleet_worker_fast'
    Assert-FleetSchema task $worker
}
Check 'regeneration is byte-identical and preserves mtime' @('A30') {
    $manifestPath = Join-Path $bundle 'manifest.json'
    $before = Get-FleetHash $manifestPath
    $mtime = (Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc
    $run = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $kitRoot 'scripts/render.ps1'),'-Preview','-OutputDirectory',$bundle) $kitRoot
    Assert ($run.exit_code -eq 0) $run.stderr
    Assert ((Get-FleetHash $manifestPath) -ceq $before) 'Generation not deterministic'
    Assert ((Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc -eq $mtime) 'Identical generation changed mtime'
}
$testHome = New-TestHome 'user home'
Write-FleetText (Join-Path $testHome '.codex/config.toml') "# user comment`r`n[unrelated]`r`nvalue = 'preserve'`r`n"
Write-FleetText (Join-Path $testHome '.codex/AGENTS.md') 'Existing user instructions'
Write-FleetText (Join-Path $testHome 'untracked.txt') 'user data'
$protected = @('.codex/config.toml','.codex/AGENTS.md','untracked.txt')
$protectedHashes = @{}; foreach ($path in $protected) { $protectedHashes[$path] = Get-FleetHash (Join-Path $testHome $path) }
Check 'dry-run does not mutate destination' @('A15','A30') {
    $before = @(Get-FleetFiles $testHome).Count
    $plan = Get-FleetInstallPlan $bundle $testHome
    Assert ($plan.files.Count -gt 5) 'Empty plan'
    Assert (@(Get-FleetFiles $testHome).Count -eq $before) 'Dry-run wrote files'
    Write-FleetText (Join-Path $testHome '.local/private.txt') 'not part of the source snapshot'
    Assert (@((Get-FleetSnapshot $testHome).files | Where-Object path -Like '.local/*').Count -eq 0) 'Local-only files entered the source snapshot'
}
Check 'preview cannot be installed without fixture mode' @('A10','A30') {
    Reject { Invoke-FleetInstall $bundle $testHome } 'Preview installed into user home'
}
Check 'install repeated install and unrelated bytes retained' @('A15','A30') {
    $first = Invoke-FleetInstall $bundle $testHome -Fixture
    Assert ($first.status -eq 'installed') 'Install did not run'
    $second = Invoke-FleetInstall $bundle $testHome -Fixture
    Assert ($second.status -eq 'unchanged') 'Install not idempotent'
    foreach ($path in $protected) { Assert ((Get-FleetHash (Join-Path $testHome $path)) -ceq $protectedHashes[$path]) "User file changed: $path" }
}
Check 'tracked staged and untracked changes survive install rollback' @('A14','A15','A30') {
    $gitHome = New-TestHome 'dirty git'
    $git = (Get-Command git).Source
    $init = Invoke-FleetProcess $git @('init',$gitHome) $kitRoot
    Assert ($init.exit_code -eq 0) $init.stderr
    Write-FleetText (Join-Path $gitHome '.gitignore') ".codex/`n.agents/`n"
    Write-FleetText (Join-Path $gitHome 'tracked.txt') 'base'
    $add = Invoke-FleetProcess $git @('-C',$gitHome,'add','tracked.txt','.gitignore') $kitRoot
    Assert ($add.exit_code -eq 0) $add.stderr
    $commit = Invoke-FleetProcess $git @('-C',$gitHome,'-c','user.name=Fleet fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','-m','fixture baseline') $kitRoot
    Assert ($commit.exit_code -eq 0) $commit.stderr
    Write-FleetText (Join-Path $gitHome 'tracked.txt') 'staged user value'
    $add = Invoke-FleetProcess $git @('-C',$gitHome,'add','tracked.txt') $kitRoot
    Assert ($add.exit_code -eq 0) $add.stderr
    Write-FleetText (Join-Path $gitHome 'tracked.txt') 'unstaged user value'
    Write-FleetText (Join-Path $gitHome 'untracked 日本語.txt') 'untracked user value'
    $before = Get-FleetSnapshot $gitHome -Exclude @('.git/**','.agents/fleet/**')
    $null = Invoke-FleetInstall $bundle $gitHome -Fixture
    $null = Invoke-FleetRollback $gitHome -Apply
    $after = Get-FleetSnapshot $gitHome -Exclude @('.git/**','.agents/fleet/**')
    Assert ($before.digest -ceq $after.digest -and $before.staged_digest -ceq $after.staged_digest -and $before.git_status -ceq $after.git_status -and $before.commit -ceq $after.commit) 'Existing Git changes were altered'
}
Check 'post-install edit prevents install and rollback' @('A31') {
    $file = Join-Path $testHome '.codex/agents/fleet_explorer.toml'
    $bytes = [IO.File]::ReadAllBytes($file)
    Write-FleetText $file 'user edit'
    Reject { Invoke-FleetInstall $bundle $testHome -Fixture } 'User edit overwritten'
    Reject { Invoke-FleetRollback $testHome -Apply } 'User edit deleted'
    Assert ([IO.File]::ReadAllText($file) -ceq 'user edit') 'User edit lost'
    [IO.File]::WriteAllBytes($file,$bytes)
}
Check 'rollback removes only managed files and repeats safely' @('A30') {
    $plan = Invoke-FleetRollback $testHome
    Assert ($plan.status -eq 'dry-run') 'Rollback defaults to mutation'
    $null = Invoke-FleetRollback $testHome -Apply
    Assert ((Invoke-FleetRollback $testHome -Apply).status -eq 'not-installed') 'Rollback not idempotent'
    foreach ($path in $protected) { Assert ((Get-FleetHash (Join-Path $testHome $path)) -ceq $protectedHashes[$path]) "User file changed: $path" }
}
Check 'partial rollback remains recoverable' @('A24','A30') {
    $rollbackHome = New-TestHome 'rollback failure'
    $null = Invoke-FleetInstall $bundle $rollbackHome -Fixture
    Reject { Invoke-FleetRollback $rollbackHome -Apply -FailAfter 2 } 'Rollback injection did not fail'
    Assert (Test-Path -LiteralPath (Join-Path $rollbackHome '.agents/fleet/manifests/pending.json')) 'No recovery journal'
    $null = Undo-FleetPending $rollbackHome
    $plan = Get-FleetInstallPlan $bundle $rollbackHome
    Assert (@($plan.files | Where-Object action -NE 'unchanged').Count -eq 0) 'Rollback recovery failed to restore files'
    $null = Invoke-FleetRollback $rollbackHome -Apply
}
Check 'pending recovery refuses later user edits' @('A24','A31') {
    $pendingHome = New-TestHome 'pending user edit'
    $null = Invoke-FleetInstall $bundle $pendingHome -Fixture
    Reject { Invoke-FleetRollback $pendingHome -Apply -FailAfter 1 } 'Missing injected failure'
    $journal = Read-FleetJson (Join-Path $pendingHome '.agents/fleet/manifests/pending.json')
    $changed = Resolve-FleetPath $pendingHome $journal.files[0].path
    Write-FleetText $changed 'user change after interrupted rollback'
    Reject { Undo-FleetPending $pendingHome } 'Recovery destroyed later user edit'
    Assert ([IO.File]::ReadAllText($changed) -ceq 'user change after interrupted rollback') 'Later user edit lost'
}
Check 'mutation lock excludes concurrent installer' @('A30') {
    $lockedHome = New-TestHome 'concurrent'
    $held = Open-FleetMutationLock $lockedHome
    try { Reject { Open-FleetMutationLock $lockedHome } 'Second lock acquired' }
    finally { $held.Dispose() }
    $released = Open-FleetMutationLock $lockedHome
    $released.Dispose()
}
Check 'unmanaged identical and different files never adopted' @('A15','A30') {
    $collisionHome = New-TestHome 'collision'
    $target = Join-Path $collisionHome '.codex/agents/fleet_explorer.toml'
    Write-FleetText $target 'existing user file'
    Reject { Get-FleetInstallPlan $bundle $collisionHome } 'Unmanaged file overwritten'
    [IO.File]::Copy((Join-Path $bundle 'payload/.codex/agents/fleet_explorer.toml'),$target,$true)
    Reject { Get-FleetInstallPlan $bundle $collisionHome } 'Identical unmanaged file adopted'
}
Check 'partial install failure restores original state' @('A24','A30') {
    $failureHome = New-TestHome 'failure'
    Reject { Invoke-FleetInstall $bundle $failureHome -Fixture -FailAfter 2 } 'Fault injection did not fail'
    Assert (-not (Test-Path -LiteralPath (Join-Path $failureHome '.codex/agents/fleet_explorer.toml'))) 'Partial install left payload'
    Assert (-not (Test-Path -LiteralPath (Join-Path $failureHome '.agents/fleet/manifests/pending.json'))) 'Recovery left pending transaction'
    $null = Invoke-FleetInstall $bundle $failureHome -Fixture
    $null = Invoke-FleetRollback $failureHome -Apply
}
Check 'generated hand edits are detected' @('A31') {
    $file = Join-Path $bundle 'payload/.codex/agents/fleet_explorer.toml'
    $bytes = [IO.File]::ReadAllBytes($file)
    Write-FleetText $file 'tampered'
    Reject { Get-FleetManifest $bundle } 'Generated edit accepted'
    [IO.File]::WriteAllBytes($file,$bytes)
}
Check 'duplicate or traversal manifest entries rejected' @('A13','A32') {
    $file = Join-Path $bundle 'manifest.json'
    $bytes = [IO.File]::ReadAllBytes($file)
    $manifest = Read-FleetJson $file
    $manifest.files += Clone $manifest.files[0]
    Write-FleetJson $file $manifest
    Write-FleetText (Join-Path $bundle 'manifest.sha256') (Get-FleetHash $file)
    Reject { Get-FleetManifest $bundle } 'Duplicate destination accepted'
    [IO.File]::WriteAllBytes($file,$bytes)
    Write-FleetText (Join-Path $bundle 'manifest.sha256') (Get-FleetHash $file)
}
Check 'preview manifest edits cannot unlock normal apply' @('A10','A31') {
    $file = Join-Path $bundle 'manifest.json'
    $bytes = [IO.File]::ReadAllBytes($file)
    $manifest = Read-FleetJson $file
    $manifest.installable = $true
    Write-FleetJson $file $manifest
    Reject { Get-FleetManifest $bundle } 'Manifest edit was not detected'
    Write-FleetText (Join-Path $bundle 'manifest.sha256') (Get-FleetHash $file)
    Reject { Get-FleetManifest $bundle } 'Preview boolean promoted to installable'
    $manifest.installable = 'false'
    Write-FleetJson $file $manifest
    Write-FleetText (Join-Path $bundle 'manifest.sha256') (Get-FleetHash $file)
    Reject { Get-FleetManifest $bundle } 'String boolean was accepted'
    [IO.File]::WriteAllBytes($file,$bytes)
    Write-FleetText (Join-Path $bundle 'manifest.sha256') (Get-FleetHash $file)
}
Check 'config layer override and duplicate location diagnosis' @('A07','A08') {
    $diagnosticHome = New-TestHome 'doctor'
    $project = Join-Path $runRoot 'diagnostic project'
    Write-FleetText (Join-Path $diagnosticHome '.agents/skills/example/SKILL.md') 'existing'
    Write-FleetText (Join-Path $project '.agents/skills/example/SKILL.md') 'existing'
    Write-FleetText (Join-Path $project 'AGENTS.override.md') 'override'
    $run = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $kitRoot 'scripts/doctor.ps1'),'-UserHome',$diagnosticHome,'-ProjectRoot',$project) $kitRoot
    Assert ($run.exit_code -eq 0) $run.stderr
    $diagnosis = $run.stdout | ConvertFrom-Json -AsHashtable
    Assert ($diagnosis.collisions.Count -eq 1 -and $diagnosis.overrides.Count -eq 1) 'Collision/override not detected'
    Assert ($diagnosis.config_resolution -eq 'unverified') 'Effective configuration inferred'
}
Check 'evaluation gate refuses unverified runtime without inference' @('A16','A28') {
    $output = Join-Path $runRoot 'eval-blocked.json'
    $run = Invoke-FleetProcess $pwshPath @('-NoProfile','-File',(Join-Path $PSScriptRoot 'evals/run.ps1'),'-Execute','-OutputPath',$output) $kitRoot
    Assert ($run.exit_code -eq 2) 'Unverified evaluation did not stop'
    $evaluation = Read-FleetJson $output
    Assert ($evaluation.rows.Count -eq 12 -and @($evaluation.rows | Where-Object status -NE 'blocked').Count -eq 0) 'Evaluation missing runs were fabricated'
}
Check 'altered verifier is rejected before execution' @('A13','A17','A20') {
    $fixture = Join-Path $runRoot 'altered verifier'
    Write-FleetText (Join-Path $fixture 'src/input.txt') 'original'
    $verifier = Join-Path $fixture 'tests/check.ps1'
    Write-FleetText $verifier 'exit 0'
    $baseline = Get-FleetSnapshot $fixture
    Write-FleetText $verifier "Set-Content -LiteralPath (Join-Path `$PSScriptRoot '../executed.txt') -Value 'should not run'"
    $grade = Get-FleetEvaluationGrade $baseline $fixture @('src/input.txt') $pwshPath @('-NoProfile','-File',$verifier)
    Assert (-not $grade.test_ran -and $grade.status -eq 'artifact-failed') 'Altered verifier ran'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'executed.txt'))) 'Altered verifier side effect occurred'
}
Check 'verifier source mutation is detected' @('A17') {
    $fixture = Join-Path $runRoot 'verifier source mutation'
    Write-FleetText (Join-Path $fixture 'src/input.txt') 'original'
    $verifier = Join-Path $fixture 'tests/check.ps1'
    Write-FleetText $verifier "Set-Content -LiteralPath (Join-Path `$PSScriptRoot '../src/input.txt') -Value 'changed'"
    $baseline = Get-FleetSnapshot $fixture
    $grade = Get-FleetEvaluationGrade $baseline $fixture @('src/input.txt') $pwshPath @('-NoProfile','-File',$verifier)
    Assert ($grade.test_ran -and $grade.verifier_changed_source -and $grade.status -eq 'artifact-failed') 'Verifier mutation accepted'
}
Check 'dedicated cache needs no token and conflicts fail without values' @('F1') {
    Assert-FleetAuthenticationEnvironment 'chatgpt-cache' @{}
    Reject { Assert-FleetAuthenticationEnvironment 'chatgpt-cache' @{CODEX_ACCESS_TOKEN='synthetic-secret'} } 'Competing token accepted'
    Reject { Assert-FleetAuthenticationEnvironment 'chatgpt-cache' @{OPENAI_BASE_URL='https://example.invalid'} } 'Provider override accepted'
    Reject { Read-FleetValidationSession (Join-Path $env:USERPROFILE '.codex/manifest.json') } 'Personal home accepted'
    $waiting=Get-FleetAuthenticationStatus @{exit_code=1;stdout='';stderr='not logged in'}
    $logged=Get-FleetAuthenticationStatus @{exit_code=0;stdout='';stderr='Logged in using ChatGPT'}
    Assert ($waiting.status -eq 'action-required-once' -and -not $waiting.inference_verified) 'Missing login became inference'
    Assert ($logged.status -eq 'authenticated' -and -not $logged.inference_verified) 'Login status became inference'
    $redacted=Protect-FleetDiagnosticText 'https://auth.example.invalid/?code=synthetic Bearer synthetic-secret' ''
    Assert ($redacted -notmatch 'synthetic|https://') 'Authentication URL or secret leaked'
}
Check 'session reuse rejects changed CLI definitions and escaping environment' @('F1','A10','A30') {
    $private=New-FleetPrivateDirectory (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) ('CodexFleetValidation/test-' + [guid]::NewGuid().ToString('N')))
    $sessionEnv=New-FleetRuntimeEnvironment $private
    $sessionEnv.CODEX_HOME=Join-Path $private 'codex-home'; $sessionEnv.CODEX_SQLITE_HOME=$sessionEnv.CODEX_HOME
    $null=[IO.Directory]::CreateDirectory($sessionEnv.CODEX_HOME)
    $fixture=New-TestHome 'session validation'
    $definition=Join-Path $fixture 'definition.toml'
    Write-FleetText $definition 'synthetic definition'
    $state=@{format_version=1;session_root=$private;authentication='chatgpt-cache';environment=$sessionEnv;workspace=$fixture;guards=@((Get-FleetGuardFile $definition));cli_path=$pwshPath;cli_sha256=(Get-FleetHash $pwshPath);bundle=$bundle;bundle_sha256=(Get-FleetHash (Join-Path $bundle 'manifest.json'))}
    $path=Join-Path $private 'manifest.json'
    Write-FleetJson $path $state
    $null=Read-FleetValidationSession $path
    $bad=Clone $state; $bad.environment.USERPROFILE=$env:USERPROFILE
    Write-FleetJson $path $bad
    Reject { Read-FleetValidationSession $path } 'Personal environment accepted'
    $bad=Clone $state; $bad.cli_sha256='0' * 64
    Write-FleetJson $path $bad
    Reject { Read-FleetValidationSession $path } 'Changed CLI accepted'
    Write-FleetJson $path $state
    Write-FleetText $definition 'changed definition'
    Reject { Read-FleetValidationSession $path } 'Changed definition accepted'
}
$report = [ordered]@{
    format_version=1;kind='deterministic-fixtures';recorded_at=(Get-Date).ToString('o');fixture_root=$runRoot
    powershell=$PSVersionTable.PSVersion.ToString();checks=@($script:checks.ToArray())
    passed=@($script:checks | Where-Object status -EQ 'passed').Count;failed=@($script:checks | Where-Object status -EQ 'failed').Count
    runtime_agent_tests='unverified';release_gate='blocked-until-runtime-acceptance'
}
if (-not $OutputPath) { $OutputPath = Join-Path $kitRoot '.local/artifacts/tests.json' }
Write-FleetJson $OutputPath $report
Write-Host "Results: $($report.passed) passed, $($report.failed) failed. $OutputPath"
if ($report.failed) { exit 1 }
