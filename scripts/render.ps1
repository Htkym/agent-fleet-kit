#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$ModelTiers = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/model-tiers.example.yaml'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.local/build/preview'),
    [switch]$Preview
)
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path $PSScriptRoot -Parent
$map = Read-FleetJson $ModelTiers
$routing = Read-FleetJson (Join-Path $kitRoot 'config/routing.yaml')
$roles = @('fleet_explorer','fleet_researcher','fleet_implementer','fleet_verifier','fleet_reviewer','fleet_worker_fast','fleet_reviewer_critical')
if ($map.format_version -ne 1 -or (($routing.Keys | Sort-Object) -join ',') -cne (($roles | Sort-Object) -join ',')) { throw 'Invalid model map or agent names' }
$resolved = @{}
$runtimeEvidence = @()
foreach ($tierName in @('ROOT','STRONG','BALANCED','FAST')) {
    if (-not $map.tiers.ContainsKey($tierName)) { throw "Unresolved tier: $tierName" }
    $tier = $map.tiers[$tierName]
    if ($tier.model -notmatch '^gpt-[a-zA-Z0-9.-]+$' -or -not $tier.reasoning.Count) { throw "Unresolved model: $tierName" }
    $evidence = Resolve-FleetPath $kitRoot $tier.evidence
    if (-not (Test-Path -LiteralPath $evidence -PathType Leaf)) { throw 'Model evidence does not exist' }
    if ($tier.status -ne 'runtime-verified' -and -not $Preview) { throw "Unverified model tier: $tierName; use -Preview for non-installable output" }
    if ($tier.status -eq 'runtime-verified') {
        $record = Read-FleetJson $evidence
        if ($record.model -cne $tier.model -or $record.cli_version -cne $map.cli_version -or $record.exit_code -ne 0 -or $record.metadata_source -ne 'runtime' -or -not $record.reasoning) { throw 'Invalid runtime model evidence' }
        foreach ($effort in $tier.reasoning) { if ($effort -notin $record.reasoning) { throw 'Unverified reasoning effort' } }
    }
}
foreach ($role in $roles) {
    $route = $routing[$role]
    if (-not $map.tiers.ContainsKey($route.tier)) { throw "Unresolved route: $role" }
    $tier = $map.tiers[$route.tier]
    if ($route.reasoning -notin $tier.reasoning -or $route.reasoning -notin @('medium','high')) { throw "Unsupported reasoning: $role" }
    if ($route.sandbox -notin @('read-only','workspace-write')) { throw 'Unsafe sandbox mode' }
    $resolved[$role] = @{model=$tier.model;reasoning=$route.reasoning;sandbox=$route.sandbox;status=$tier.status}
}
$out = Assert-FleetPlainPath $OutputDirectory
if (Test-Path -LiteralPath $out) {
    $existing = Get-FleetManifest $out
    # Existing generated files must still match; never silently overwrite hand edits.
}
$stage = Join-Path $kitRoot ('.local/runs/render/' + [guid]::NewGuid().ToString('N'))
$null = Assert-FleetPlainPath $stage
[IO.Directory]::CreateDirectory($stage) | Out-Null
$common = [IO.File]::ReadAllText((Join-Path $kitRoot 'policies/common.md'))
$template = [IO.File]::ReadAllText((Join-Path $kitRoot 'templates/codex/agent.toml.template'))
$manifestFiles = @()
foreach ($role in $roles) {
    $instructions = $common + "`n" + [IO.File]::ReadAllText((Join-Path $kitRoot "agent-src/$role.md"))
    $values = @{name=$role;description=($role.Replace('fleet_','Fleet ') + ' — bounded task owner');model=$resolved[$role].model;reasoning=$resolved[$role].reasoning;sandbox=$resolved[$role].sandbox;instructions=$instructions}
    $toml = $template
    foreach ($key in $values.Keys) {
        # JSON basic strings are valid TOML basic strings for these Unicode/control characters.
        $encoded = ConvertTo-Json -InputObject ([string]$values[$key]) -Compress -EscapeHandling Default
        $toml = $toml.Replace('{{' + $key + '}}', $encoded)
    }
    if ($toml.Contains('{{')) { throw 'Unresolved template placeholder' }
    $relative = ".codex/agents/$role.toml"
    $target = Resolve-FleetPath $stage ("payload/$relative")
    Write-FleetText $target $toml
    $manifestFiles += @{path=$relative;sha256=(Get-FleetHash $target)}
}
foreach ($skillName in @('fleet-orchestrator','evidence-review','benchmark-lab')) {
$skillRoot = Join-Path $kitRoot "skills/$skillName"
foreach ($file in Get-FleetFiles $skillRoot | Sort-Object FullName) {
    $relative = ".agents/skills/$skillName/" + [IO.Path]::GetRelativePath($skillRoot, $file.FullName).Replace('\','/')
    $target = Resolve-FleetPath $stage ("payload/$relative")
    [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
    [IO.File]::Copy($file.FullName, $target, $false)
    $manifestFiles += @{path=$relative;sha256=(Get-FleetHash $target)}
}
}
$sources = @()
foreach ($folder in @('policies','agent-src','config','templates','skills','scripts')) {
    foreach ($file in Get-FleetFiles (Join-Path $kitRoot $folder) | Sort-Object FullName) {
        $sources += [ordered]@{path=[IO.Path]::GetRelativePath($kitRoot,$file.FullName).Replace('\','/');sha256=(Get-FleetHash $file.FullName)}
    }
}
$manifest = [ordered]@{
    format_version=1;kit_version=[IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION')).Trim();renderer_version=2
    cli_version=$map.cli_version;installable=(-not $Preview);validation=$(if ($Preview) {'preview-catalog-only'} else {'runtime-verified'})
    model_map_sha256=(Get-FleetHash $ModelTiers);resolved=$resolved;sources=$sources;files=@($manifestFiles | Sort-Object path)
    runtime_evidence=@()
}
if (-not $Preview) {
    foreach ($tierName in @('ROOT','STRONG','BALANCED','FAST')) {
        $source = Resolve-FleetPath $kitRoot $map.tiers[$tierName].evidence
        $relative = "evidence/$tierName.json"
        Write-FleetText (Resolve-FleetPath $stage $relative) ([IO.File]::ReadAllText($source))
        $manifest.runtime_evidence += @{path=$relative;sha256=(Get-FleetHash $source)}
    }
}
Write-FleetJson (Join-Path $stage 'manifest.json') $manifest
Write-FleetText (Join-Path $stage 'manifest.sha256') ((Get-FleetHash (Join-Path $stage 'manifest.json')) + "`n")
$null = Get-FleetManifest $stage
if (Test-Path -LiteralPath $out) {
    $oldPaths = @($existing.files.path | Sort-Object)
    $newPaths = @($manifest.files.path | Sort-Object)
    if (($oldPaths -join "`n") -cne ($newPaths -join "`n")) { throw 'Generated file set changed; choose a fresh output directory' }
}
foreach ($file in Get-FleetFiles $stage) {
    $relative = [IO.Path]::GetRelativePath($stage,$file.FullName).Replace('\','/')
    $target = Resolve-FleetPath $out $relative
    if ((Get-FleetHash $target) -ceq (Get-FleetHash $file.FullName)) { continue }
    [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
    [IO.File]::Copy($file.FullName, $target, $true)
}
@{status='rendered';bundle=$out;installable=$manifest.installable;agents=$roles.Count;manifest_sha256=(Get-FleetHash (Join-Path $out 'manifest.json'))} | ConvertTo-Json
