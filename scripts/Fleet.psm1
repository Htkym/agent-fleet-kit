#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:KitRoot = Split-Path $PSScriptRoot -Parent

function Read-FleetJson([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}

function Write-FleetJson([string]$Path, $Value) {
    $Path = Assert-FleetPlainPath $Path
    $text = (ConvertTo-FleetCanonical $Value | ConvertTo-Json -Depth 60) + "`n"
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary,$text,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path,$true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}

function Open-FleetMutationLock([string]$DestinationHome) {
    $path = Resolve-FleetPath $DestinationHome '.agents/fleet/manifests/mutation.lock'
    [IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
    # The OS handle owns the lock. A leftover file is not evidence of a running process.
    [IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}

function ConvertTo-FleetCanonical($Value) {
    if ($Value -is [Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($key in $Value.Keys | Sort-Object -CaseSensitive) { $sorted[$key] = ConvertTo-FleetCanonical $Value[$key] }
        return $sorted
    }
    if ($Value -is [array]) {
        $items = @($Value | ForEach-Object { ConvertTo-FleetCanonical $_ })
        return ,$items
    }
    $Value
}

function Write-FleetText([string]$Path, [string]$Text) {
    $Path = Assert-FleetPlainPath $Path
    $parent = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-FleetHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FleetTextHash([string]$Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Assert-FleetPlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point refused: $cursor" }
            if ($item.PSObject.Properties.Name -contains 'LinkType' -and $item.LinkType -eq 'HardLink') { throw "Hard link refused: $cursor" }
        }
        $parent = Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    $full
}

function Resolve-FleetPath([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?\[\]\x00-\x1f]') {
        throw "Unsafe relative path: $Relative"
    }
    $segments = $Relative -split '[/\\]'
    foreach ($segment in $segments) {
        if ($segment -in @('', '.', '..') -or $segment -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Unsafe path segment: $Relative"
        }
    }
    $rootPath = Assert-FleetPlainPath $Root
    $full = Assert-FleetPlainPath ([IO.Path]::Combine($rootPath, $Relative))
    if (-not $full.StartsWith($rootPath.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes root: $Relative"
    }
    $full
}

function Get-FleetFiles([string]$Root) {
    $rootPath = Assert-FleetPlainPath $Root
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            $null = Assert-FleetPlainPath $item.FullName
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $item }
        }
    }
}

function Assert-FleetSchema([string]$Kind, $Value) {
    $schema = Join-Path $script:KitRoot "skills/fleet-orchestrator/assets/$Kind.schema.json"
    if (-not (Test-Json -Json ($Value | ConvertTo-Json -Depth 60 -Compress) -SchemaFile $schema -ErrorAction SilentlyContinue)) {
        throw "Invalid $Kind contract"
    }
}

function Test-FleetPattern([string]$Relative, [string]$Pattern) {
    # Only exact paths and directory/** are supported: reject ambiguous glob overlap.
    $path = $Relative.Replace('\','/').ToLowerInvariant()
    $patternPath = $Pattern.Replace('\','/').ToLowerInvariant()
    if ($patternPath.EndsWith('/**')) {
        $prefix = $patternPath.Substring(0, $patternPath.Length - 3)
        return $path.StartsWith($prefix + '/', [StringComparison]::Ordinal)
    }
    if ($patternPath -match '[*?\[\]]') { throw "Unsupported ownership pattern: $Pattern" }
    $path -eq $patternPath
}

function Assert-FleetOwnership($Task, [string[]]$ChangedPaths) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $ChangedPaths) {
        $resolved = Resolve-FleetPath $Task.workspace $path
        if (-not $seen.Add($resolved)) { throw "Duplicate physical path: $path" }
        foreach ($deny in $Task.ownership.forbidden) {
            if (Test-FleetPattern $path $deny) { throw "Forbidden change: $path" }
        }
        $allowed = $false
        foreach ($pattern in @($Task.ownership.source_write) + @($Task.ownership.generated_write)) {
            if (Test-FleetPattern $path $pattern) { $allowed = $true }
        }
        if (-not $allowed) { throw "Unowned change: $path" }
        if ($Task.role -in @('fleet_explorer','fleet_researcher','fleet_reviewer','fleet_reviewer_critical')) { throw 'Read-only role changed a file' }
        if ($Task.role -eq 'fleet_verifier') {
            $generated = $false
            foreach ($pattern in $Task.ownership.generated_write) { if (Test-FleetPattern $path $pattern) { $generated = $true } }
            if (-not $generated) { throw 'Verifier changed source' }
        }
    }
}

function Assert-FleetReady($Task, $RunState, [Parameter(Mandatory)][int]$OpenChildThreads, [Parameter(Mandatory)][bool]$RootWriterActive, [ValidateRange(1,4)][int]$ChildLimit = 4) {
    Assert-FleetSchema task $Task
    Assert-FleetSchema run-state $RunState
    if ($Task.run_id -cne $RunState.run_id -or $Task.task_revision -ne $RunState.task_revision) { throw 'Task belongs to an outdated run' }
    foreach ($dependency in $Task.depends_on) {
        $matches = @($RunState.tasks | Where-Object task_id -CEQ $dependency)
        if ($matches.Count -ne 1 -or $matches[0].state -ne 'accepted' -or $matches[0].task_revision -ne $RunState.task_revision) { throw "Dependency not accepted: $dependency" }
    }
    $active = @($RunState.tasks | Where-Object state -EQ 'running')
    if ($OpenChildThreads -lt 0 -or $OpenChildThreads -ge $ChildLimit) { throw 'Observed open-child budget exhausted or invalid' }
    # The coordinator passes all running writers; Root is counted as a writer too.
    if ($Task.ownership.source_write.Count -and ($RootWriterActive -or @($active | Where-Object writer -EQ $true).Count)) {
        throw 'Single writer slot is reserved'
    }
    $true
}

function Get-FleetSnapshot([string]$Root, [string[]]$Exclude = @('.git/**','.local/**','.fleet-runs/**','artifacts/**','build/**')) {
    $rootPath = Assert-FleetPlainPath $Root
    $files = @()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            $relative = [IO.Path]::GetRelativePath($rootPath,$item.FullName).Replace('\','/')
            $skip = $false
            foreach ($pattern in $Exclude) {
                if (Test-FleetPattern $relative $pattern) { $skip = $true }
                if ($item.PSIsContainer -and $pattern.EndsWith('/**') -and $relative -ieq $pattern.Substring(0,$pattern.Length-3)) { $skip = $true }
            }
            if ($relative -eq '.git') { $skip = $true }
            if ($skip) { continue }
            $null = Assert-FleetPlainPath $item.FullName
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { $files += [ordered]@{path=$relative;sha256=(Get-FleetHash $item.FullName)} }
        }
    }
    $files = @($files | Sort-Object path)
    $git = Get-Command git -ErrorAction SilentlyContinue
    $commit = $null; $branch = $null; $status = $null; $staged = $null
    if ($git) {
        $head = Invoke-FleetProcess $git.Source @('-C',$rootPath,'rev-parse','--verify','HEAD') $rootPath
        if ($head.exit_code -eq 0) { $commit = $head.stdout.Trim() }
        $branchResult = Invoke-FleetProcess $git.Source @('-C',$rootPath,'symbolic-ref','--short','HEAD') $rootPath
        if ($branchResult.exit_code -eq 0) { $branch = $branchResult.stdout.Trim() }
        $statusResult = Invoke-FleetProcess $git.Source @('-C',$rootPath,'status','--porcelain=v1','--untracked-files=all','--','.') $rootPath
        if ($statusResult.exit_code -eq 0) { $status = $statusResult.stdout }
        $stagedResult = Invoke-FleetProcess $git.Source @('-C',$rootPath,'diff','--cached','--binary','--no-ext-diff','--','.') $rootPath
        if ($stagedResult.exit_code -eq 0) { $staged = Get-FleetTextHash $stagedResult.stdout }
    }
    @{commit=$commit;branch=$branch;files=$files;digest=(Get-FleetTextHash ($files | ConvertTo-Json -Depth 5 -Compress));git_status=$status;staged_digest=$staged;excluded=$Exclude}
}

function Assert-FleetResult($Task, $Result, $Revision, [string]$EvidenceRoot, $ExecutionRecords) {
    Assert-FleetSchema task $Task
    Assert-FleetSchema task-result $Result
    if ($Result.task_id -cne $Task.task_id -or $Result.run_id -cne $Task.run_id -or $Result.task_revision -ne $Task.task_revision) {
        throw 'Stale or mismatched task result'
    }
    if ($Result.status -ne 'completed' -or $Result.blockers.Count) { throw 'Result is not ready for verification' }
    if ($Result.observed_revision.digest -cne $Revision.digest -or $Result.observed_revision.commit -cne $Revision.commit) {
        throw 'Revision mismatch'
    }
    Assert-FleetOwnership $Task $Result.changed_paths
    foreach ($check in $Result.verification) {
        if ($check.command_ref -cnotin $Task.verification.command_refs) { throw 'Unexpected verification command reference' }
    }
    foreach ($commandRef in $Task.verification.command_refs) {
        $matches = @($Result.verification | Where-Object command_ref -CEQ $commandRef)
        if ($matches.Count -ne 1) { throw "Missing or duplicate verification: $commandRef" }
        $check = $matches[0]
        if ($check.status -ne 'passed' -or $check.exit_code -ne 0) { throw "Unverified command: $commandRef" }
        if ($check.revision.digest -cne $Revision.digest -or $check.revision.commit -cne $Revision.commit) { throw 'Verification is for another revision' }
        $log = Resolve-FleetPath $EvidenceRoot $check.artifact
        if ((Get-FleetHash $log) -cne $check.sha256) { throw 'Evidence missing or changed' }
        $records = @($ExecutionRecords | Where-Object command_ref -CEQ $commandRef)
        if ($records.Count -ne 1) { throw 'External execution record required' }
        $record = $records[0]
        if ($record.exit_code -ne 0 -or $record.sha256 -cne $check.sha256 -or $record.revision.digest -cne $Revision.digest -or $record.revision.commit -cne $Revision.commit -or ($record.command | ConvertTo-Json -Compress) -cne ($check.command | ConvertTo-Json -Compress)) {
            throw 'Result contradicts the trusted execution record'
        }
    }
    # This validates evidence consistency. Root still owns semantic acceptance and review.
    $true
}

function Set-FleetTaskState($TaskState, [string]$Next, [switch]$EvidenceChecked, [switch]$RootAccepted) {
    $edges = @{
        planned=@('ready','blocked','cancelled'); ready=@('running','blocked','cancelled')
        running=@('completed','blocked','failed','cancelled'); completed=@('verified','blocked','failed')
        verified=@('accepted','blocked','failed'); accepted=@(); blocked=@(); failed=@(); cancelled=@()
    }
    if ($Next -notin $edges[$TaskState.state]) { throw "Illegal transition: $($TaskState.state) -> $Next; retry requires a new attempt" }
    if ($Next -eq 'verified' -and -not $EvidenceChecked) { throw 'Evidence check required' }
    if ($Next -eq 'accepted' -and -not $RootAccepted) { throw 'Root acceptance required' }
    $TaskState.state = $Next
    $TaskState
}

function Invoke-FleetProcess([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 30) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $start.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        @{exit_code=$(if ($timedOut) {$null} else {$process.ExitCode});timed_out=$timedOut;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult()}
    } finally { $process.Dispose() }
}

function Get-FleetManifest([string]$Bundle) {
    $path = Resolve-FleetPath $Bundle 'manifest.json'
    $digestPath = Resolve-FleetPath $Bundle 'manifest.sha256'
    if (-not (Test-Path -LiteralPath $digestPath) -or [IO.File]::ReadAllText($digestPath).Trim() -cne (Get-FleetHash $path)) { throw 'Manifest was modified or has no digest' }
    $manifest = Read-FleetJson $path
    if ($manifest.format_version -ne 1 -or $manifest.files.Count -lt 6) { throw 'Invalid bundle manifest' }
    $roles = @('fleet_explorer','fleet_researcher','fleet_implementer','fleet_verifier','fleet_reviewer')
    $skills = @('fleet-orchestrator')
    if ($manifest.renderer_version -eq 2) {
        $roles += @('fleet_worker_fast','fleet_reviewer_critical')
        $skills += @('evidence-review','benchmark-lab')
    } elseif ($manifest.renderer_version -ne 1) { throw 'Unsupported renderer version' }
    if ((($manifest.resolved.Keys | Sort-Object) -join ',') -cne (($roles | Sort-Object) -join ',')) { throw 'Incomplete resolved role set' }
    if ($manifest.installable -isnot [bool]) { throw 'Manifest installable must be boolean' }
    if ($manifest.installable) {
        if ($manifest.validation -ne 'runtime-verified' -or $manifest.runtime_evidence.Count -eq 0) { throw 'Runtime verification missing' }
        foreach ($role in $manifest.resolved.Keys) {
            if ($manifest.resolved[$role].status -ne 'runtime-verified') { throw 'Preview status cannot be installed' }
        }
        foreach ($evidence in $manifest.runtime_evidence) {
            $recordPath = Resolve-FleetPath $Bundle $evidence.path
            if ((Get-FleetHash $recordPath) -cne $evidence.sha256) { throw 'Runtime evidence changed' }
            $record = Read-FleetJson $recordPath
            if ($record.metadata_source -ne 'runtime' -or $record.exit_code -ne 0 -or $record.cli_version -cne $manifest.cli_version) { throw 'Invalid runtime evidence' }
        }
    } elseif ($manifest.validation -ne 'preview-catalog-only') { throw 'Invalid preview validation state' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest.files) {
        if (-not $seen.Add($entry.path)) { throw 'Duplicate manifest destination' }
        if ($entry.path -notmatch '^\.codex/agents/fleet_(explorer|researcher|implementer|verifier|reviewer|worker_fast|reviewer_critical)\.toml$|^\.agents/skills/(fleet-orchestrator|evidence-review|benchmark-lab)/') { throw 'Unmanaged destination refused' }
        $file = Resolve-FleetPath $Bundle ("payload/" + $entry.path)
        if ((Get-FleetHash $file) -cne $entry.sha256) { throw "Generated file modified: $($entry.path)" }
    }
    foreach ($role in $roles) { if (".codex/agents/$role.toml" -notin $manifest.files.path) { throw "Missing Agent: $role" } }
    foreach ($skill in $skills) { if (".agents/skills/$skill/SKILL.md" -notin $manifest.files.path) { throw "Missing Skill: $skill" } }
    foreach ($required in @('SKILL.md','agents/openai.yaml','assets/task.schema.json','assets/task-result.schema.json','assets/run-state.schema.json')) {
        if (".agents/skills/fleet-orchestrator/$required" -notin $manifest.files.path) { throw "Missing Skill resource: $required" }
    }
    $payloadRoot = Resolve-FleetPath $Bundle 'payload'
    foreach ($file in Get-FleetFiles $payloadRoot) {
        $relative = [IO.Path]::GetRelativePath($payloadRoot,$file.FullName).Replace('\','/')
        if (-not $seen.Contains($relative)) { throw "Untracked generated file: $relative" }
    }
    $manifest
}

function Assert-FleetFixtureHome([string]$DestinationHome) {
    $fixtureRoot = Join-Path $script:KitRoot '.local/runs/tests'
    $relative = [IO.Path]::GetRelativePath($fixtureRoot, [IO.Path]::GetFullPath($DestinationHome))
    $null = Resolve-FleetPath $fixtureRoot $relative
    $marker = Resolve-FleetPath $DestinationHome '.fleet-fixture'
    if (-not (Test-Path -LiteralPath $marker) -or [IO.File]::ReadAllText($marker).Trim() -ne 'disposable-fleet-test-home') { throw 'Not an authorized disposable fixture home' }
}

function Get-FleetInstallPlan([string]$Bundle, [string]$DestinationHome) {
    $manifest = Get-FleetManifest $Bundle
    $root = Assert-FleetPlainPath $DestinationHome
    $receiptPath = Resolve-FleetPath $root '.agents/fleet/manifests/current.json'
    $pendingPath = Resolve-FleetPath $root '.agents/fleet/manifests/pending.json'
    if (Test-Path -LiteralPath $pendingPath) { throw 'Interrupted transaction exists; inspect and rollback -RecoverPending first' }
    $old = if (Test-Path -LiteralPath $receiptPath) { Read-FleetJson $receiptPath } else { $null }
    $oldFiles = @{}
    if ($old) {
        foreach ($entry in $old.files) {
            $target = Resolve-FleetPath $root $entry.path
            if ((Get-FleetHash $target) -cne $entry.sha256) { throw "Installed file changed: $($entry.path)" }
            $oldFiles[$entry.path] = $entry
        }
    }
    $plan = @()
    foreach ($entry in $manifest.files) {
        $target = Resolve-FleetPath $root $entry.path
        $current = Get-FleetHash $target
        if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Destination is not a file: $target" }
        if ($null -ne $current -and -not $oldFiles.ContainsKey($entry.path)) { throw "Unmanaged existing file refused: $($entry.path)" }
        $action = if ($current -ceq $entry.sha256) { 'unchanged' } elseif ($current) { 'update' } else { 'create' }
        $plan += @{path=$entry.path;action=$action;before=$current;after=$entry.sha256}
    }
    if ($old) {
        foreach ($entry in $old.files) {
            if ($entry.path -notin $manifest.files.path) { throw 'File removal requires rollback before installing this bundle' }
        }
    }
    @{manifest=$manifest;files=$plan;previous_receipt=$old;destination=$root;config_merge='proposal-only';installable=$manifest.installable}
}

function Invoke-FleetInstall([string]$Bundle, [string]$DestinationHome, [switch]$Fixture, [int]$FailAfter = -1) {
    if ($Fixture) { Assert-FleetFixtureHome $DestinationHome }
    elseif ($FailAfter -ge 0) { throw 'Fault injection is fixture-only' }
    $plan = Get-FleetInstallPlan $Bundle $DestinationHome
    if (-not $plan.installable -and -not $Fixture) { throw 'Bundle is not runtime-verified; preview cannot be installed into a user home' }
    $changes = @($plan.files | Where-Object action -NE 'unchanged')
    if (-not $changes.Count) { return @{status='unchanged';files=$plan.files} }
    $root = $plan.destination
    $receiptPath = Resolve-FleetPath $root '.agents/fleet/manifests/current.json'
    $pendingPath = Resolve-FleetPath $root '.agents/fleet/manifests/pending.json'
    $id = [guid]::NewGuid().ToString('N')
    $journal = @{format_version=1;transaction_id=$id;files=@();previous_receipt=$plan.previous_receipt;bundle_sha256=(Get-FleetHash (Join-Path $Bundle 'manifest.json'))}
    foreach ($entry in $changes) {
        $target = Resolve-FleetPath $root $entry.path
        $backup = $null
        if ($entry.before) {
            $backup = ".agents/fleet/backups/$id/$($entry.path)"
            $backupPath = Resolve-FleetPath $root $backup
            [IO.Directory]::CreateDirectory((Split-Path $backupPath -Parent)) | Out-Null
            [IO.File]::Copy($target, $backupPath, $false)
            if ((Get-FleetHash $backupPath) -cne $entry.before) { throw 'Backup verification failed' }
        }
        $journal.files += @{path=$entry.path;before=$entry.before;after=$entry.after;backup=$backup}
    }
    Write-FleetJson $pendingPath $journal
    try {
        $count = 0
        foreach ($entry in $journal.files) {
            $target = Resolve-FleetPath $root $entry.path
            if ((Get-FleetHash $target) -cne $entry.before) { throw 'Destination changed during installation' }
            if ($count -eq $FailAfter) { throw 'Injected fixture failure' }
            $source = Resolve-FleetPath $Bundle ("payload/" + $entry.path)
            if ((Get-FleetHash $source) -cne $entry.after) { throw 'Bundle changed during installation' }
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
            [IO.File]::Copy($source, $target, [bool]$entry.before)
            if ((Get-FleetHash $target) -cne $entry.after) { throw 'Installed hash mismatch' }
            $count++
        }
        $receipt = @{format_version=1;transaction_id=$id;files=$plan.manifest.files;bundle_sha256=$journal.bundle_sha256;fixture=[bool]$Fixture}
        Write-FleetJson $receiptPath $receipt
        Remove-Item -LiteralPath $pendingPath
        @{status='installed';files=$plan.files;receipt=$receiptPath}
    } catch {
        $failure = $_
        try { Undo-FleetPending $root | Out-Null } catch { throw "Install failed; pending journal retained for recovery: $($_.Exception.Message). Original: $failure" }
        throw $failure
    }
}

function Undo-FleetPending([string]$DestinationHome) {
    $root = Assert-FleetPlainPath $DestinationHome
    $pendingPath = Resolve-FleetPath $root '.agents/fleet/manifests/pending.json'
    $journal = Read-FleetJson $pendingPath
    if ($journal.format_version -ne 1 -or $journal.transaction_id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid recovery journal' }
    # Preflight the whole transaction before changing any file.
    foreach ($entry in $journal.files) {
        if ($entry.path -notmatch '^\.codex/agents/fleet_(explorer|researcher|implementer|verifier|reviewer|worker_fast|reviewer_critical)\.toml$|^\.agents/skills/(fleet-orchestrator|evidence-review|benchmark-lab)/') { throw 'Recovery path outside managed scope' }
        $current = Get-FleetHash (Resolve-FleetPath $root $entry.path)
        if ($current -cne $entry.before -and $current -cne $entry.after) { throw "User edit prevents recovery: $($entry.path)" }
        if ($entry.before) {
            if ($entry.backup -cne ".agents/fleet/backups/$($journal.transaction_id)/$($entry.path)") { throw 'Invalid backup location' }
            if ((Get-FleetHash (Resolve-FleetPath $root $entry.backup)) -cne $entry.before) { throw 'Backup damaged; recovery refused' }
        }
    }
    foreach ($entry in $journal.files) {
        $target = Resolve-FleetPath $root $entry.path
        if ((Get-FleetHash $target) -ceq $entry.before) { continue }
        if ($entry.before) { [IO.File]::Copy((Resolve-FleetPath $root $entry.backup), $target, $true) }
        else { Remove-Item -LiteralPath $target }
    }
    $receiptPath = Resolve-FleetPath $root '.agents/fleet/manifests/current.json'
    if ($journal.previous_receipt) { Write-FleetJson $receiptPath $journal.previous_receipt }
    elseif (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath }
    Remove-Item -LiteralPath $pendingPath
    @{status='recovered'}
}

function Invoke-FleetRollback([string]$DestinationHome, [switch]$Apply, [int]$FailAfter = -1) {
    $root = Assert-FleetPlainPath $DestinationHome
    if ($FailAfter -ge 0) { Assert-FleetFixtureHome $root }
    $pending = Resolve-FleetPath $root '.agents/fleet/manifests/pending.json'
    if (Test-Path -LiteralPath $pending) { throw 'Pending transaction requires explicit recovery' }
    $receiptPath = Resolve-FleetPath $root '.agents/fleet/manifests/current.json'
    if (-not (Test-Path -LiteralPath $receiptPath)) { return @{status='not-installed';files=@()} }
    $receipt = Read-FleetJson $receiptPath
    if ($receipt.format_version -ne 1) { throw 'Invalid receipt' }
    foreach ($entry in $receipt.files) {
        if ($entry.path -notmatch '^\.codex/agents/fleet_(explorer|researcher|implementer|verifier|reviewer|worker_fast|reviewer_critical)\.toml$|^\.agents/skills/(fleet-orchestrator|evidence-review|benchmark-lab)/') { throw 'Rollback path outside managed scope' }
        if ((Get-FleetHash (Resolve-FleetPath $root $entry.path)) -cne $entry.sha256) { throw "User edit prevents rollback: $($entry.path)" }
    }
    if ($Apply) {
        $id = [guid]::NewGuid().ToString('N')
        $journal = @{format_version=1;transaction_id=$id;files=@();previous_receipt=$receipt;bundle_sha256=$receipt.bundle_sha256}
        foreach ($entry in $receipt.files) {
            $target = Resolve-FleetPath $root $entry.path
            $backup = ".agents/fleet/backups/$id/$($entry.path)"
            $backupPath = Resolve-FleetPath $root $backup
            [IO.Directory]::CreateDirectory((Split-Path $backupPath -Parent)) | Out-Null
            [IO.File]::Copy($target,$backupPath,$false)
            if ((Get-FleetHash $backupPath) -cne $entry.sha256) { throw 'Rollback backup verification failed' }
            $journal.files += @{path=$entry.path;before=$entry.sha256;after=$null;backup=$backup}
        }
        Write-FleetJson $pending $journal
        # A pending deletion is recoverable through the same before/after transaction journal.
        $count = 0
        foreach ($entry in $receipt.files) {
            $target = Resolve-FleetPath $root $entry.path
            if ((Get-FleetHash $target) -cne $entry.sha256) { throw 'Destination changed during rollback' }
            if ($count -eq $FailAfter) { throw 'Injected rollback failure; use -RecoverPending -Apply' }
            Remove-Item -LiteralPath $target
            $count++
        }
        Remove-Item -LiteralPath $receiptPath
        Remove-Item -LiteralPath $pending
    }
    @{status=$(if ($Apply) {'rolled-back'} else {'dry-run'});files=$receipt.files}
}

Export-ModuleMember -Function *-Fleet*
