# Copilot CLI edition

The Copilot edition supplies the same three Skills and seven bounded roles without
changing the default Codex output. Root remains responsible for integration and
acceptance, with one source writer per worktree and no recursive child delegation.
This is a Skill procedure, not an implementation of Copilot's built-in `/fleet`.

## Generate

From this Kit's root on Windows with PowerShell 7.4 or later:

```powershell
pwsh -NoProfile -File .\scripts\render.ps1 -Target Copilot -Preview
pwsh -NoProfile -File .\scripts\verify.ps1 -Bundle .\.local\build\copilot-preview
```

Output defaults to `.local\build\copilot-preview`, separate from the Codex preview.
`-OutputDirectory` can select another directory; changing an existing bundle's
target or overwriting hand-edited generated files is refused.
Generation and static verification need no Copilot login or API key.

## Add to a project

Inspect collisions before copying only these assets from the generated `payload`:

| Bundle path | Target project path |
|---|---|
| `payload\.github\skills\fleet-orchestrator\` | `.github\skills\fleet-orchestrator\` |
| `payload\.github\skills\evidence-review\` | `.github\skills\evidence-review\` |
| `payload\.github\skills\benchmark-lab\` | `.github\skills\benchmark-lab\` |
| `payload\.github\agents\fleet_*.agent.md` | `.github\agents\fleet_*.agent.md` |

Copy the whole orchestration Skill directory, including `references` and `assets`,
not only `SKILL.md`. Do not overwrite unrelated `.github` content or personal
settings. The Kit does not automatically copy anything into a target project.
The optional `.agents\fleet\project.yaml` remains shared Kit data, not CLI config.

Copilot also discovers `.agents\skills`. If the Codex edition is already present,
do not assume which same-name definition wins. Use a separate target project for
the Copilot edition or explicitly resolve the competing definitions before use.
Do not blindly delete the Codex assets.

Start Copilot in the target project. Use `/skills reload`, then
`/skills info fleet-orchestrator` to inspect the effective path. Use `/agent` to
confirm discovery of the seven `fleet_*` profiles; start a fresh CLI session if
new Agent definitions are not visible. Installing files is not proof of loading.

Example prompts in the interactive CLI (replace placeholders with real scope):

```text
Use /fleet-orchestrator to implement <requirement> in <allowed files>, run <existing verification command>, obtain independent review, and collect results. Use one source writer at a time.
Use /evidence-review to review <fixed diff> against <requirements>. Do not edit source.
Use /benchmark-lab to compare <two candidates> with <fixed input> and retain raw measurements.
```

## Runtime differences and limits

Agents use Markdown/YAML profiles, not Codex TOML. `model` is omitted, so Copilot's
configured model is inherited. Codex `-ModelTiers`, reasoning, and sandbox values
are not imported. Change models through authorized Copilot settings or actual
launcher arguments; the Kit makes no account/model availability claims.

The orchestration Skill describes `task`, `read_agent`, and `write_agent` only when
exposed by the running CLI. It requires inspecting the actual schema and supports
an explicitly recorded built-in Agent fallback with the generated role contract.
That fallback does not inherit the custom profile's tool allowlist. If the required
capability or safety is unavailable, stop or report that step as unverified.
There is no assumed `close_agent` API or automatic capacity-release claim.

Custom profiles use explicit tool aliases without `agent` or wildcard access.
Read-only roles have no shell/edit tools; Verifier can execute authorized commands
but must not change source. Execute access is not a sandbox. Root supplies fixed
diffs or performs needed shell-based inspection for read-only roles.

Bundles remain `installable=false`: the existing installer refuses normal apply.
Manual project placement is available after inspecting conflicts, as for the Codex
preview. Runtime discovery, effective model, tool enforcement, and authenticated
end-to-end execution must be confirmed in the target environment. Codex runtime
evidence cannot establish Copilot compatibility, and `verify.ps1 -Smoke` is rejected
for a Copilot bundle. No diagnostic readiness flags are enabled by this edition.

For native Plugin distribution instead of project-file placement, use
[`package.ps1` and the Plugin instructions](plugins.md). That edition has separate
local runtime observations for all seven native Agents; this does not turn the
legacy preview bundle into an automatically installable bundle.

The opt-in `tests\integration\plugin-smoke.ps1 -Execute -Model <authorized-model>`
uses a dedicated CLI home and disposable fixture, records native JSON events and
external test results, and refuses budget-limited or missing-child execution.
It uses `--allow-all-tools` for the fixture's authorized operations, which is not
an OS sandbox and remains subject to host policy. The default credit cap is 60;
the installed CLI requires at least 30. Without `-Execute`, it only prepares the
fixture and invocation. Authentication uses the native CLI environment, never a
copied credential cache. Inspect actual child evidence before accepting review.

## Maintaining the edition

Edit `skills-copilot\fleet-orchestrator\SKILL.md` for the Copilot procedure and
`templates\copilot\agent.agent.md.template` for profile formatting. Common child
contracts, role bodies, specialist Skills, references, and schemas remain shared
under `policies`, `agent-src`, and `skills`; the renderer adapts specialist paths
and omits OpenAI discovery metadata. Regenerate instead of editing the payload.

Run the existing `tests\run.ps1`, then render and verify both targets. The regression
suite covers Copilot output, tool lists, resource links, deterministic regeneration,
target isolation, preview restrictions, collision preservation, and rollback.

Format references: [Copilot CLI Skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills)
and [custom Agent configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration).
