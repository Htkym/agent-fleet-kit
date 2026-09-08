# Fleet Kit plugins

These instructions apply to the self-contained plugin distribution, either extracted from the release ZIP or generated at `.local/build/plugins`. Run installation commands from its root, where `plugins/` and `package-manifest.json` are located, not from the source repository root. Publish or archive the entire distribution directory, including hidden `.agents` and `.github` marketplace catalogs, without
depending on the source Kit or its `.local` directory. Do not publish local
authentication homes, test fixtures, raw logs, or runtime session records.

| Plugin | Components |
|---|---|
| `fleet-copilot` | Three Skills and seven native Markdown Agent profiles |
| `fleet-codex` | Three Skills and seven role contracts bundled as Skill resources |

Codex's plugin manifest does not register named TOML Agents. Its orchestrator reads
the bundled role contract and passes it to a supported native child launcher.
It never pretends that the seven `fleet_*` roles were automatically registered.
Both editions preserve single-writer ownership, no recursive child delegation,
real verification, independent review, and Root acceptance.

## Copilot CLI

From this distribution directory, install the local plugin:

```powershell
copilot plugin install .\plugins\fleet-copilot
copilot plugin list
```

Alternatively, register the catalog and install by name:

```powershell
copilot plugin marketplace add .
copilot plugin install fleet-copilot@fleet-kit-copilot
```

Start a fresh session and inspect `/skills` and `/agent`. Request the
`fleet-orchestrator` Skill from `fleet-copilot`; resolve any same-name project or
personal Skill before using it. Named profiles may appear as
`fleet-copilot:fleet_explorer`, for example. Use the names actually discovered.
Plugin models inherit Copilot configuration; no Codex model map is applied.

For a session-only local load without installing the plugin:

```powershell
copilot --plugin-dir .\plugins\fleet-copilot
```

Use absolute paths when launching from another working directory. Reinstall a
copied local plugin after changing its files, then start a new session. Remove it
with `copilot plugin uninstall fleet-copilot` (use the registered identity shown
by `plugin list` for marketplace installations).

## Codex CLI

From this distribution directory:

```powershell
codex plugin marketplace add .
codex plugin add fleet-codex@fleet-kit-codex
codex plugin list --json
```

Start a new session and request `$fleet-orchestrator` from `fleet-codex`, or use
`$evidence-review` and `$benchmark-lab` independently. Confirm the effective Skill
path and resolve same-name Skills from other installations.
Remove with `codex plugin remove fleet-codex@fleet-kit-codex`.

For isolated registration/loading checks, set `CODEX_HOME` only in the test process
to a dedicated directory. Native plugin commands persist state in that directory.
Authentication is separate; never copy a personal credential cache into a fixture.
Successful installation does not by itself prove inference or child execution.

## Producing this distribution from source

In the Fleet Kit source directory:

```powershell
pwsh -NoProfile -File .\scripts\package.ps1
pwsh -NoProfile -File .\scripts\package.ps1 -VerifyOnly
```

The default output is `.local\build\plugins`. `-OutputDirectory` selects a different
directory. Existing hand edits and unexpected generated files are refused. Edit
the Kit's source, not this output. After source changes, regenerate and verify again.
If the generated file set changes, use a fresh output directory.

`package-manifest.json` and its digest describe package integrity, not a signature
or a guarantee of runtime behavior. Packaging does not enable the old preview
installer or change runtime-readiness gates. Installation uses each CLI's native
Plugin mechanism. No plugin is uploaded or installed into personal settings by
the packaging script.

## Local runtime observations (2026-09-07)

On Windows, Copilot CLI `1.0.84-1` accepted the marketplace, installed the plugin,
listed seven Agents and three Skills, and removed the test installation.
A separate session-only load from an unrelated fixture directory exercised all
seven registered `fleet-copilot:<role>` Agents with `gpt-5.6-luna`. Native events
recorded distinct child launches and actual read/edit/execute tools. Implementer
fixed a threshold boundary, Worker Fast changed only fixed label values, Verifier
ran three passing tests, and the independent Reviewer inspected the final revision.
Reviewer Critical read the bundled `evidence-review` procedure and reproduced the
baseline defects before implementation. Source/test and plugin bytes were retained
for comparison; no named-Agent fallback was needed.

An earlier `gpt-5.6-terra` attempt hit the test's 30-credit limit before verification
and review. That attempt is not accepted as a complete orchestration result.
The successful run used a 60-credit limit; this is a diagnostic budget, not a
model performance or cost comparison.

The standalone `benchmark-lab` Skill also ran through native Copilot with
`gpt-5.6-luna`, without child Agents. Actual Node execution checked both candidates
against the same expected sum and retained 14 finite, nonnegative measurements:
seven per candidate, alternating order, after three warmups. The accepted command
exited zero. These small shared-host measurements do not establish general
performance advantages.

Codex CLI `0.153.4` accepted and installed its marketplace plugin under a dedicated
`CODEX_HOME`. Native app-server `skills/list` discovered three enabled namespaced
Skills with zero plugin errors. Its installed files included seven role resources.
No Codex login or inference was performed, as requested. Plugin and marketplace
removal completed in that isolated home.

Isolated CLI homes avoid modifying personal plugin settings, but do not guarantee
that every ancestor or personal Skill directory is excluded. Codex also reported
three unrelated pre-existing Skill frontmatter errors; none belonged to this plugin.
No OS-level permission isolation, thread release, other model, or other OS is claimed.
Raw events and authentication-free native installation evidence remain local to
the source Kit's `.local\runs` and are not part of this distribution.
