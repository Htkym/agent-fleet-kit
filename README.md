# Codex Fleet Kit

[Japanese](README.ja.md)

## What this is

Codex Fleet Kit is a source kit for coordinating bounded work in Codex CLI. It supplies three reusable Skills and seven named Agent roles for research, implementation, verification, and independent review. Root decomposes the request, assigns bounded work, integrates the result, and decides acceptance.

It is designed for work that benefits from separating investigation, a focused implementation, real verification, and review. It is not a background scheduler, a sandbox, or an official OpenAI distribution. Only one source writer may edit a worktree at a time.

## When to use it

Use `fleet-orchestrator` for a non-trivial request with independent research, a bounded implementation, verification, or independent review. Use the specialist Skills by themselves when only an evidence-based review or a measured comparison is needed.

Do not use Fleet for a simple question, a typo, or a short tightly coupled edit that Root can complete directly. Child Agents must not recursively delegate work.

## Included Skills and Agents

| Skill | Purpose |
|---|---|
| fleet-orchestrator | Role selection, ownership assignment, verification, independent review, and result collection |
| evidence-review | Review diffs and requirements, returning location, severity, reproduction conditions, and unchecked scope |
| benchmark-lab | Compare measured results under fixed conditions, recording correctness, repetitions, raw data, and measurement limits |

Specialist Skills do not start Fleet and can be used independently.

| Agent | Responsibility |
|---|---|
| fleet_explorer | Investigate implementation and call sites |
| fleet_researcher | Independently research specifications and existing tests |
| fleet_implementer | General implementation with a fixed contract |
| fleet_verifier | Run real tests and verify results |
| fleet_reviewer | Normal independent review |
| fleet_worker_fast | Narrow routine transformation with fixed rules and target |
| fleet_reviewer_critical | Critical review of public contracts, state transitions, lifetime, data integrity, and similar concerns |

Do not start all seven Agents every time. Return design decisions and unexpected failures to Root, and do not recursively delegate from children.

## Requirements

- Windows, PowerShell 7.4 or later, and Git.
- To run Agents, Codex CLI that supports named Agents, plus access to authorized models and authentication.

Local regression tests and preview generation require neither Codex CLI, sign-in, nor an API key. [Compatibility](docs/compatibility.md) records the verified CLI and limitations.

## Quick start

Clone the repository and run the following commands from its root:

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

These commands run the regression suite, generate a non-installable preview bundle, and statically verify that bundle. Generated output is stored in `.local/build/preview/`, test results in `.local/artifacts/tests.json`, and temporary work in `.local/runs/`. The entire `.local/` directory is excluded from Git.

The model example is [config/model-tiers.example.yaml](config/model-tiers.example.yaml), and role mapping is [config/routing.yaml](config/routing.yaml). Example model IDs may not be available unchanged. Confirm a usable configuration for the target CLI and account. These YAML files use JSON-compatible syntax.

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Preview -ModelTiers config/model-tiers.example.yaml
```

`-Preview` output has `installable=false`. A static verification pass does not prove effective models, permissions, runtime behavior, or automated deployment.

## Add Fleet to a project

Generate a preview, then copy only the required assets from its `payload/` directory into the corresponding locations in the target project. Inspect conflicts before copying. Do not edit generated output directly; update this repository's source of truth and regenerate.

| Generated location | Target project location |
|---|---|
| `payload/.agents/skills/<Skill-name>/` | `.agents/skills/<Skill-name>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

`fleet-orchestrator` and `fleet_reviewer_critical` expect the specialist Skills to exist under the project's `.agents/skills/`. See [config.fragment.toml.template](templates/codex/config.fragment.toml.template) for a configuration fragment. Do not replace existing configuration wholesale; inspect and add only the required entries.

Invoke a Skill explicitly from the target project's root. Replace the following example requests with concrete details: the target, required behavior, permitted files, and verification command.

```powershell
codex exec --approve-for-me '$fleet-orchestrator: implement the specified task, run real tests, obtain independent review, and collect results. Allow only one implementation writer at a time.'
codex exec --approve-for-me '$evidence-review: independently review the specified diff and requirements. Do not change source.'
codex exec --approve-for-me '$benchmark-lab: independently compare the two specified candidates with the same inputs and record raw data and measurement conditions.'
```

For updates, rollback, and optional diagnostics, see [operations](docs/operations.md).

## Operating safely

- Preserve existing diffs, staged files, and untracked files. Never discard or rewrite them without explicit authorization.
- Treat role prompts and TOML configuration as operating conventions, not OS-enforced security boundaries.
- Use dry runs for user-environment changes. Inspect proposed differences before an explicit apply operation.
- Keep credentials, personal configuration, raw logs, and local evidence outside Git. `.local/` is the intended local-only location.
- Do not treat child completion as acceptance or thread release. Root must check evidence, actual changes, and remaining commands.

## Verify changes

After changing the Kit's source of truth, run the following commands from the repository root in this order:

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

The test command exercises the Kit's regression suite. Preview generation creates a non-installable bundle, and `verify.ps1` checks that bundle. For a project using Fleet, also run that project's standard verification commands after copying assets. A static pass does not prove effective models, permissions, runtime behavior, or automated deployment.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

## License

[MIT License](LICENSE). See the license text at the [Open Source Initiative](https://opensource.org/license/mit).
