#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) '.local\build\plugins'),
    [switch]$VerifyOnly,
    [switch]$Repository
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Fleet.psm1') -Force
$kitRoot = Split-Path $PSScriptRoot -Parent
$out = Assert-FleetPlainPath $OutputDirectory
if ($Repository -and $PSBoundParameters.ContainsKey('OutputDirectory')) { throw 'Repository mode uses isolated staging; omit OutputDirectory' }
if ($VerifyOnly -and -not $Repository) {
    $manifest = Get-FleetPluginPackage $out
    $currentSources = @(Get-FleetPluginSources $kitRoot)
    if ((($currentSources.path | Sort-Object) -join "`n") -cne (($manifest.sources.path | Sort-Object) -join "`n")) { throw 'Source file set changed; repackage' }
    foreach ($entry in $manifest.sources) {
        if ((Get-FleetHash (Resolve-FleetPath $kitRoot $entry.path)) -cne $entry.sha256) { throw "Source changed; repackage: $($entry.path)" }
    }
    @{status='package-verified';directory=$out;files=$manifest.files.Count;runtime='not-implied'} | ConvertTo-Json
    return
}
$existing = if (-not $Repository -and (Test-Path -LiteralPath $out)) { Get-FleetPluginPackage $out } else { $null }
$stage = Join-Path $kitRoot ('.local\runs\plugin-package\' + [guid]::NewGuid().ToString('N'))
$distribution = Join-Path $stage 'distribution'
$version = [IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') { throw 'Plugin version must be semantic' }

foreach ($edition in @('Codex','Copilot')) {
    $bundle = Join-Path $stage $edition
    & (Join-Path $PSScriptRoot 'render.ps1') -Target $edition -Preview -OutputDirectory $bundle | Out-Null
    $bundleManifest = Get-FleetManifest $bundle
    $name = 'fleet-' + $edition.ToLowerInvariant()
    $plugin = Join-Path $distribution "plugins\$name"
    foreach ($entry in $bundleManifest.files) {
        if ($entry.path.EndsWith('/agents/openai.yaml')) { continue }
        if ($entry.path -match '^\.(?:agents|github)/skills/(.+)$') {
            $relative = 'skills/' + $Matches[1]
        } elseif ($edition -eq 'Copilot' -and $entry.path -match '^\.github/agents/(.+)$') {
            $relative = 'agents/' + $Matches[1]
        } else { continue }
        $source = Resolve-FleetPath $bundle ("payload/" + $entry.path)
        $destination = Resolve-FleetPath $plugin $relative
        $text = [IO.File]::ReadAllText($source)
        if ($relative -like 'agents/*.agent.md') {
            $text = $text.Replace('.github/skills/', '../skills/')
            $text += "`nResolve relative Skill paths against this Agent profile's directory, not the workspace.`n"
        }
        if ($relative -eq 'skills/fleet-orchestrator/SKILL.md') {
            if ($edition -eq 'Codex') {
                $replacements = [ordered]@{
                    'The common child safety contract is included in generated Agents. Do not operate from ungenerated source alone.' = 'Read references/agents/<role>.md relative to this Skill and pass its common and role contracts to the actual supported child launcher. Plugin roles are contract resources, not automatically registered named Agents. Never invent an agent_type.'
                    'For evidence-based review, read `.agents/skills/evidence-review/SKILL.md`; for requested measured comparison, read `.agents/skills/benchmark-lab/SKILL.md`.' = 'For evidence-based review, read `../evidence-review/SKILL.md`; for requested measured comparison, read `../benchmark-lab/SKILL.md`. Resolve these paths relative to this Skill, not the workspace.'
                    'Model tiers are ROOT, STRONG, BALANCED, and FAST. Read concrete IDs from the verified mapping.' = 'This plugin does not install a Codex model map or Agent TOML configuration. Inherit authorized session models; use only explicit, supported overrides.'
                    'Normally, assign Explorer, Researcher, Implementer, and Verifier to BALANCED and Reviewer to STRONG.' = 'Do not require unavailable model tiers or claim that a role contract selects a model.'
                    "The parent's runtime permissions can override Agent TOML sandbox defaults." = 'Role contracts do not grant permissions or establish a sandbox; respect the actual parent and child permissions.'
                }
                foreach ($key in $replacements.Keys) {
                    if ([regex]::Matches($text, [regex]::Escape($key)).Count -ne 1) { throw "Codex plugin adaptation anchor changed: $key" }
                    $text = $text.Replace($key, $replacements[$key])
                }
            } else {
                $text += @'

## Plugin deployment

Resolve profiles from `../../agents/<role>.agent.md` relative to this Skill.
The plugin name is `fleet-copilot`; registered profiles may be exposed as
`fleet-copilot:<role>`. Inspect the actual registry and launcher schema before
choosing the name. A plain `fleet_*` name is not assumed to be registered.
The plugin does not require project-local `.github/skills` or `.github/agents`.
'@
            }
        }
        Write-FleetText $destination $text
    }
    if ($edition -eq 'Codex') {
        $common = [IO.File]::ReadAllText((Join-Path $kitRoot 'policies\common.md'))
        foreach ($role in $bundleManifest.resolved.Keys | Sort-Object) {
            $body = [IO.File]::ReadAllText((Join-Path $kitRoot "agent-src\$role.md"))
            $body = $body.Replace('.agents/skills/evidence-review/SKILL.md', '../../../evidence-review/SKILL.md')
            $body += "`nResolve relative Skill paths against this role resource's directory, not the workspace.`n"
            Write-FleetText (Join-Path $plugin "skills\fleet-orchestrator\references\agents\$role.md") ($common + "`n" + $body)
        }
    }
    $pluginManifest = [ordered]@{
        name=$name;version=$version;description="Bounded Fleet orchestration, evidence review, and measured comparisons for $edition CLI."
        license='MIT';skills='./skills/'
    }
    if ($edition -eq 'Copilot') { $pluginManifest.agents = './agents/' }
    $manifestName = if ($edition -eq 'Codex') { '.codex-plugin\plugin.json' } else { 'plugin.json' }
    Write-FleetJson (Join-Path $plugin $manifestName) $pluginManifest
    Write-FleetText (Join-Path $plugin 'LICENSE') ([IO.File]::ReadAllText((Join-Path $kitRoot 'LICENSE')))
}

Write-FleetJson (Join-Path $distribution '.agents\plugins\marketplace.json') @{
    name='fleet-kit-codex';interface=@{displayName='Fleet Kit for Codex'}
    plugins=@(@{name='fleet-codex';source=@{source='local';path='./plugins/fleet-codex'};policy=@{installation='AVAILABLE';authentication='ON_INSTALL'};category='Productivity'})
}
Write-FleetJson (Join-Path $distribution '.github\plugin\marketplace.json') @{
    name='fleet-kit-copilot';owner=@{name='Fleet Kit contributors'}
    plugins=@(@{name='fleet-copilot';source='./plugins/fleet-copilot';description='Bounded orchestration, review, and measurement.';version=$version})
}
Write-FleetText (Join-Path $distribution 'README.md') ([IO.File]::ReadAllText((Join-Path $kitRoot 'docs\plugins.md')))
$files = @(foreach ($file in Get-FleetFiles $distribution | Sort-Object FullName) {
    # Match .gitattributes so generated publishing assets survive a fresh checkout.
    $text = [IO.File]::ReadAllText($file.FullName)
    if ($text.Contains("`r`n")) { Write-FleetText $file.FullName ($text.Replace("`r`n","`n")) }
    @{path=[IO.Path]::GetRelativePath($distribution,$file.FullName).Replace('\','/');sha256=(Get-FleetHash $file.FullName)}
})
$sources = @(Get-FleetPluginSources $kitRoot)
Write-FleetJson (Join-Path $distribution 'package-manifest.json') @{format_version=1;version=$version;files=$files;sources=$sources;runtime_verified=$false}
Write-FleetText (Join-Path $distribution 'package-manifest.sha256') (Get-FleetHash (Join-Path $distribution 'package-manifest.json'))
$manifest = Get-FleetPluginPackage $distribution
if ($Repository) {
    Sync-FleetRepositoryPlugins $distribution $kitRoot -VerifyOnly:$VerifyOnly | ConvertTo-Json
    return
}
if ($existing -and (($existing.files.path | Sort-Object) -join "`n") -cne (($manifest.files.path | Sort-Object) -join "`n")) {
    throw 'Plugin file set changed; choose a fresh output directory'
}
if (-not (Test-Path -LiteralPath $out)) {
    [IO.Directory]::CreateDirectory((Split-Path $out -Parent)) | Out-Null
    Copy-Item -LiteralPath $distribution -Destination $out -Recurse
} else {
    # All adaptations and integrity checks finish before updating owned output.
    foreach ($file in Get-FleetFiles $distribution) {
        $relative = [IO.Path]::GetRelativePath($distribution,$file.FullName).Replace('\','/')
        $destination = Resolve-FleetPath $out $relative
        if ((Get-FleetHash $destination) -cne (Get-FleetHash $file.FullName)) { [IO.File]::Copy($file.FullName,$destination,$true) }
    }
}
$null = Get-FleetPluginPackage $out
@{status='packaged';directory=$out;plugins=@('fleet-codex','fleet-copilot');runtime='not-implied'} | ConvertTo-Json
