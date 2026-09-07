# Windows-only helpers for the bounded diagnostic, not the comparison runner.
function New-FleetPrivateDirectory([string]$Path) {
    $Path = Assert-FleetPlainPath $Path
    if (Test-Path -LiteralPath $Path) { throw 'Private directory must be new' }
    $null = [IO.Directory]::CreateDirectory($Path)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($identity in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
    $actual = Get-Acl -LiteralPath $Path
    if (-not $actual.AreAccessRulesProtected -or @($actual.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @($sid.Value,'S-1-5-18') }).Count) { throw 'Private ACL verification failed' }
    $Path
}

function Get-FleetGuardFile([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) { return @{path=$full;exists=$false;sha256=$null;size=$null;last_write_utc=$null;link_target=$null} }
    $item = Get-Item -LiteralPath $full -Force
    @{path=$full;exists=$true;sha256=(Get-FleetHash $full);size=$item.Length;last_write_utc=$item.LastWriteTimeUtc.ToString('o');link_target=$item.LinkTarget}
}

function Assert-FleetGuard($Files) {
    foreach ($file in $Files) {
        $current = Get-FleetGuardFile $file.path
        foreach ($key in @('exists','sha256','size','last_write_utc','link_target')) {
            $expected=$file[$key]
            if ($key -eq 'last_write_utc' -and $expected -is [DateTime]) { $expected=$expected.ToUniversalTime().ToString('o') }
            if ($current[$key] -cne $expected) { throw "Protected file changed: $($file.path)" }
        }
    }
}

function Save-FleetPrivateConfig([string]$UserHome, [string]$RunId) {
    $configPath = Assert-FleetPlainPath (Join-Path $UserHome '.codex/config.toml')
    $before = Get-FleetGuardFile $configPath
    if (-not $before.exists) { return @{path=$null;sha256=$null;encryption='none; source absent';acl=$null;stable=$true;source=$before} }
    $private = New-FleetPrivateDirectory (Join-Path $UserHome "AppData/Local/CodexFleetPreservation/$RunId")
    $stream = [IO.File]::Open($configPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { $bytes = [byte[]]::new($stream.Length); $stream.ReadExactly($bytes) } finally { $stream.Dispose() }
    try {
        $readHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $path = Join-Path $private 'config.toml.dpapi'
        [IO.File]::WriteAllBytes($path,[Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
        $restored = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $savedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($restored)).ToLowerInvariant()
        if ($readHash -cne $before.sha256 -or $savedHash -cne $readHash) { throw 'Config snapshot changed while being saved' }
        Assert-FleetGuard @($before)
        @{path=$path;sha256=$readHash;encryption='DPAPI CurrentUser';acl='current user and SYSTEM only';stable=$true;source=$before}
    } finally {
        if ($bytes) { [Array]::Clear($bytes) }
        if ($restored) { [Array]::Clear($restored) }
    }
}

function New-FleetRuntimeEnvironment([string]$Root, [switch]$PathsOnly) {
    $homePath = Join-Path $Root 'home'
    $temporary = Join-Path $Root 'temp'
    if (-not $PathsOnly) { foreach ($relative in @('home/.codex','home/AppData/Local','home/AppData/Roaming','temp')) { $null = [IO.Directory]::CreateDirectory((Resolve-FleetPath $Root $relative)) } }
    @{USERPROFILE=$homePath;HOME=$homePath;HOMEDRIVE=[IO.Path]::GetPathRoot($homePath).TrimEnd('\');HOMEPATH=$homePath.Substring(2);CODEX_HOME=(Join-Path $homePath '.codex');CODEX_SQLITE_HOME=(Join-Path $homePath '.codex');APPDATA=(Join-Path $homePath 'AppData/Roaming');LOCALAPPDATA=(Join-Path $homePath 'AppData/Local');TEMP=$temporary;TMP=$temporary}
}

function New-FleetDiagnosticProcess([string]$Executable, [string[]]$Arguments, [string]$Workspace, $Environment) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $Workspace
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    # Avoid implicit credential fallback; retain managed host policy and corporate TLS settings.
    foreach ($name in @('CODEX_API_KEY','OPENAI_API_KEY','CODEX_ACCESS_TOKEN')) { $null = $start.Environment.Remove($name) }
    foreach ($key in $Environment.Keys) { $start.Environment[$key] = $Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $process
}

function Wait-FleetDiagnosticTask($Task, $Process, $ProtectedFiles, [DateTime]$Deadline) {
    while (-not $Task.IsCompleted) {
        Assert-FleetGuard $ProtectedFiles
        if ([DateTime]::UtcNow -ge $Deadline) { throw 'Diagnostic time budget exhausted' }
        $null = $Task.Wait(200)
    }
    Assert-FleetGuard $ProtectedFiles
    $Task.GetAwaiter().GetResult()
}

function Stop-FleetDiagnosticProcess($Process) {
    try { $processId = $Process.Id } catch { return }
    if ($processId -and -not $Process.HasExited) {
        $Process.StandardInput.Close()
        if (-not $Process.WaitForExit(1000)) { $Process.Kill($true); $Process.WaitForExit() }
    }
}

function Protect-FleetDiagnosticText([string]$Text, [string]$Secret) {
    if ($Secret) { $Text = $Text.Replace($Secret,'[redacted-access-token]') }
    $Text -replace '(?i)Bearer\s+[^\s"\\]+','Bearer [redacted]' -replace '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b','[redacted-jwt]' -replace '(?i)https?://[^\s"<>\\]+','[redacted-url]'
}

function Assert-FleetAuthenticationEnvironment([string]$Mode, $Variables) {
    $present = @('CODEX_API_KEY','OPENAI_API_KEY','CODEX_ACCESS_TOKEN','OPENAI_BASE_URL','CODEX_MODEL_PROVIDER' | Where-Object { $Variables[$_] })
    if ($Mode -eq 'chatgpt-cache' -and $present.Count) { throw 'AUTH_METHOD_CONFLICT: competing authentication or provider environment; values omitted' }
    if ($Mode -eq 'access-token' -and ($present.Count -ne 1 -or $present[0] -ne 'CODEX_ACCESS_TOKEN')) { throw 'AUTH_METHOD_CONFLICT: access-token requires only an already authorized CODEX_ACCESS_TOKEN' }
}

function Read-FleetValidationSession([string]$Path) {
    $path = Assert-FleetPlainPath $Path
    $root = Assert-FleetPlainPath (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexFleetValidation')
    $directory = Split-Path $path -Parent
    if ((Split-Path $directory -Parent) -cne $root -or (Split-Path $path -Leaf) -cne 'manifest.json') { throw 'Invalid dedicated session path' }
    $state = Read-FleetJson $path
    if ($state.format_version -ne 1 -or $state.authentication -notin @('chatgpt-cache','access-token') -or $state.session_root -cne $directory -or $state.environment.CODEX_HOME -cne (Join-Path $directory 'codex-home')) { throw 'Invalid dedicated session manifest' }
    $null = Assert-FleetPlainPath $state.environment.CODEX_HOME
    $expectedEnvironment=New-FleetRuntimeEnvironment $directory -PathsOnly
    $expectedEnvironment.CODEX_HOME=Join-Path $directory 'codex-home'
    $expectedEnvironment.CODEX_SQLITE_HOME=$expectedEnvironment.CODEX_HOME
    if ($state.environment.Count -ne $expectedEnvironment.Count) { throw 'Unexpected session environment' }
    foreach ($key in $expectedEnvironment.Keys) { if ($state.environment[$key] -cne $expectedEnvironment[$key]) { throw 'Session environment escapes dedicated paths' } }
    foreach ($key in @('USERPROFILE','HOME','CODEX_HOME','CODEX_SQLITE_HOME','APPDATA','LOCALAPPDATA','TEMP','TMP')) { $null=Assert-FleetPlainPath $state.environment[$key] }
    Assert-FleetFixtureHome $state.workspace
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $acl = Get-Acl -LiteralPath $directory
    if (-not $acl.AreAccessRulesProtected -or @($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @($sid,'S-1-5-18') }).Count) { throw 'Dedicated session ACL changed' }
    Assert-FleetGuard $state.guards
    if ((Get-FleetHash $state.cli_path) -cne $state.cli_sha256 -or (Get-FleetHash (Join-Path $state.bundle 'manifest.json')) -cne $state.bundle_sha256) { throw 'Session CLI or bundle changed; prepare a new session' }
    $null = Get-FleetManifest $state.bundle
    $state
}

function Get-FleetAuthenticationStatus($Result) {
    # Status output remains private; authentication is separate from inference evidence.
    @{status=$(if ($Result.exit_code -eq 0 -and ($Result.stderr + $Result.stdout) -match 'Logged in using ChatGPT') {'authenticated'} else {'action-required-once'});exit_code=$Result.exit_code;inference_verified=$false}
}

function Invoke-FleetDiagnosticCommand([string]$Executable,[string[]]$Arguments,[string]$Workspace,$Environment,$ProtectedFiles,[int]$TimeoutSeconds=20) {
    Assert-FleetGuard $ProtectedFiles
    $process = New-FleetDiagnosticProcess $Executable $Arguments $Workspace $Environment
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Close()
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $null = Wait-FleetDiagnosticTask ($process.WaitForExitAsync()) $process $ProtectedFiles $deadline
        @{exit_code=$process.ExitCode;stdout=(Protect-FleetDiagnosticText $stdout.GetAwaiter().GetResult() $Environment.CODEX_ACCESS_TOKEN);stderr=(Protect-FleetDiagnosticText $stderr.GetAwaiter().GetResult() $Environment.CODEX_ACCESS_TOKEN)}
    } finally { Stop-FleetDiagnosticProcess $process; $process.Dispose() }
}

function Invoke-FleetDiagnosticRpc($Session,[string]$Method,$Params) {
    $Session.sequence++
    $id = $Session.sequence
    $Session.current_method = $Method
    $Session.current_id = $id
    $Session.process.StandardInput.WriteLine((@{id=$id;method=$Method;params=$Params} | ConvertTo-Json -Depth 30 -Compress))
    while ($true) {
        $message = Read-FleetDiagnosticRpc $Session
        if ($message.ContainsKey('id') -and $message.id -eq $id) {
            if ($message.ContainsKey('error')) { throw "RPC $Method failed: $($message.error.code)" }
            return $message.result
        }
    }
}

function Read-FleetDiagnosticRpc($Session) {
    $line = Wait-FleetDiagnosticTask ($Session.process.StandardOutput.ReadLineAsync()) $Session.process $Session.protected $Session.deadline
    if ($null -eq $line) { throw 'App-server closed its output' }
    $line = Protect-FleetDiagnosticText $line $Session.secret
    $message = $line | ConvertFrom-Json -AsHashtable
    if ($Session.current_method -eq 'config/read' -and $message.id -eq $Session.current_id -and $message.ContainsKey('result')) {
        # Hash complete configuration in memory; publish only non-secret diagnostic fields.
        $result = $message.result
        $safe = @{}
        foreach ($key in @('model','model_provider','model_reasoning_effort','sandbox_mode','approval_policy','approvals_reviewer','cli_auth_credentials_store','forced_login_method')) { $safe[$key]=$result.config[$key] }
        $safe.agents=@{}; foreach ($key in @('enabled','max_concurrent_threads_per_session','default_subagent_model','default_subagent_reasoning_effort')) { $safe.agents[$key]=$result.config.agents[$key] }
        $policy=$result.config.shell_environment_policy
        $safe.shell_environment_policy=@{inherit=$policy.inherit;exclude=$policy.exclude;set_names=@($policy.set.Keys)}
        $message.result = @{config=$safe;config_sha256=(Get-FleetTextHash ($result.config | ConvertTo-Json -Depth 60 -Compress));layers=@(foreach ($layer in $result.layers) { @{name=$layer.name;version=$layer.version;disabled_reason=$layer.disabledReason;config_sha256=(Get-FleetTextHash ($layer.config | ConvertTo-Json -Depth 60 -Compress))} });mcp_server_names=@($result.config.mcp_servers.Keys);note='config/read response projected to non-secret fields; complete config and layer bodies omitted'}
        $line = $message | ConvertTo-Json -Depth 30 -Compress
    }
    $Session.log.Add($line)
    # Reject any server request for approval or interactive authentication. No automatic approvals.
    if ($message.ContainsKey('id') -and $message.ContainsKey('method')) { throw "Interactive request stops diagnostic: $($message.method)" }
    $message
}

function Get-FleetNativeChildIds($Thread) {
    @($Thread.turns | ForEach-Object { $_.items } | ForEach-Object {
        if ($_.type -eq 'collabAgentToolCall' -and $_.tool -eq 'spawnAgent') { $_.receiverThreadIds }
        elseif ($_.type -eq 'subAgentActivity' -and $_.kind -eq 'started') { $_.agentThreadId }
    } | Sort-Object -Unique)
}

function Get-FleetNativeObservations($Thread, [string]$Role, $ChildThreads) {
    $items = @($Thread.turns | ForEach-Object { $_.items } | Where-Object type -EQ 'collabAgentToolCall')
    $spawns = @($items | Where-Object { $_.tool -eq 'spawnAgent' })
    $children = @(Get-FleetNativeChildIds $Thread)
    $matches = @($ChildThreads | Where-Object { $_.id -in $children -and $_.parentThreadId -ceq $Thread.id -and $_.agentRole -ceq $Role })
    $close = @($items | Where-Object { $_.tool -eq 'closeAgent' -and $_.status -eq 'completed' })
    $selected = $children.Count -eq 1 -and $ChildThreads.Count -eq 1 -and $matches.Count -eq 1 -and @($spawns | Where-Object status -NE 'completed').Count -eq 0
    $closed = $selected -and @($close | Where-Object { $_.receiverThreadIds -contains $matches[0].id -and $_.agentsStates[$matches[0].id].status -eq 'shutdown' }).Count -gt 0
    @{selection=$(if ($selected) {'pass'} else {'blocked'});generation=$(if ($selected) {'pass'} else {'blocked'});parent_thread_id=$Thread.id;child_thread_ids=$children;configured_model=$(if ($selected) {$matches[0].model} else {$null});configured_reasoning=$(if ($selected) {$matches[0].reasoningEffort} else {$null});metadata_meaning='thread configured/latest persisted values, not backend or per-turn telemetry';runtime_model='unverified';runtime_reasoning='unverified';permissions='unverified';result_collection='unverified';close=$(if ($closed) {'pass'} else {'blocked'});source='app-server thread/read: native spawn or subAgentActivity started, joined with child agentRole/parentThreadId; never assistant text';accepted=$false}
}
