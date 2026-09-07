#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Login','Resume')][string]$Action,
    [Parameter(Mandatory)][string]$SessionPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/integration/runtime-support.ps1')
$state=Read-FleetValidationSession $SessionPath
$variables=@{}; foreach ($name in @('CODEX_API_KEY','OPENAI_API_KEY','CODEX_ACCESS_TOKEN','OPENAI_BASE_URL','CODEX_MODEL_PROVIDER')) { $variables[$name]=[Environment]::GetEnvironmentVariable($name) }
Assert-FleetAuthenticationEnvironment $state.authentication $variables
if ($Action -eq 'Resume') {
    & (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/integration/smoke.ps1') -SessionPath $SessionPath -Execute
    exit $LASTEXITCODE
}
if ($state.authentication -ne 'chatgpt-cache') { throw 'Login requires a dedicated chatgpt-cache session' }
# Invoked only by the user. Native CLI owns the browser login and file credential store.
$process=New-FleetDiagnosticProcess $state.cli_path @('login') $state.workspace $state.environment
$process.StartInfo.RedirectStandardInput=$false
$process.StartInfo.RedirectStandardOutput=$false
$process.StartInfo.RedirectStandardError=$false
$process.StartInfo.CreateNoWindow=$false
try {
    $null=$process.Start()
    $process.WaitForExit()
    Assert-FleetGuard $state.guards
    exit $process.ExitCode
} finally { $process.Dispose() }
