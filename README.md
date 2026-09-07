# Codex Fleet Kit

[Japanese](README.ja.md)

Three Skills and seven Agents for dividing research, implementation, verification, and independent review in Codex CLI. Root decomposes requests and accepts results; only one person edits source in a worktree at a time.

The prior Japanese instruction set underwent normal-CLI practical verification in a specific Windows environment. The current English instruction set has static validation only and requires renewed practical runtime verification. This does not guarantee behavior in every environment or a speed, cost, or quality advantage. This is not an official OpenAI distribution.

## Skills and Agents

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

## Generate and verify

Run from the repository root:

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
```

Generated output is stored in `.local/build/preview/`, test results in `.local/artifacts/tests.json`, and temporary work in `.local/runs/`. The entire `.local/` directory is excluded from Git.

The model example is [config/model-tiers.example.yaml](config/model-tiers.example.yaml), and role mapping is [config/routing.yaml](config/routing.yaml). Example model IDs may not be available unchanged. Confirm a usable configuration for the target CLI and account. YAML files use JSON-compatible syntax.

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Preview -ModelTiers config/model-tiers.example.yaml
```

`-Preview` output has `installable=false`. A static verification pass does not prove effective models, permissions, or automated deployment.

## Use in a project

Place the required assets from generated `payload/` in the corresponding locations of the target project. Check for conflicts with existing files first. Do not edit generated output directly; change this repository's source of truth and regenerate.

| Generated location | Target project location |
|---|---|
| `payload/.agents/skills/<Skill-name>/` | `.agents/skills/<Skill-name>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

Orchestration and Critical depend on specialist Skills existing under the project's `.agents/skills/`. See [config.fragment.toml.template](templates/codex/config.fragment.toml.template) for a project-configuration example. Do not replace existing configuration wholesale; inspect and add only the required entries.

Invoke explicitly from the target project's root. Replace the following requests with concrete content including the target, requirements, and allowed changes.

```powershell
codex exec --approve-for-me '$fleet-orchestrator: implement the specified task, run real tests, obtain independent review, and collect results. Allow only one implementation writer at a time.'
codex exec --approve-for-me '$evidence-review: independently review the specified diff and requirements. Do not change source.'
codex exec --approve-for-me '$benchmark-lab: independently compare the two specified candidates with the same inputs and record raw data and measurement conditions.'
```

For updates, rollback, and optional diagnostics, see [operations](docs/operations.md).

## Verification scope

The prior Japanese instruction set was locally verified for work that reads and uses all three Skill definitions, named execution of seven Agents, one writer, real tests, independent review, result collection by Root, and task completion. The current English instructions have static validation only. Regression tests cover schemas, ownership, paths, generation, deployment, rollback, preservation, and failure handling. GitHub Actions runs unauthenticated regression, generation, and static verification.

Thread release, per-role OS-enforced read-only access, all boundary tests, implicit invocation, and comprehensive automated-deployment verification are incomplete. Because the parent's `workspace-write` applied to children, reviewer non-editing was checked through role contract and diff comparison. The twelve-condition comparison has not run; [the comparative protocol](docs/benchmark-protocol.md) distinguishes its plan from measurements.

Public source excludes evidence containing run logs, personal-configuration research records, or local-environment paths. [Compatibility](docs/compatibility.md) summarizes verification that can be published.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

## License

[MIT License](LICENSE). See the license text at the [Open Source Initiative](https://opensource.org/license/mit).
