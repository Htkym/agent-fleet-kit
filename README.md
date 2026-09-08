# Fleet Kit

[日本語](README.ja.md)

Fleet Kit provides three Skills and seven roles for coordinating research, implementation, verification, and independent review in Codex CLI and GitHub Copilot CLI. The parent Agent, called Root, assigns bounded tasks, integrates changes, and decides whether the result meets the requirements.

Only one source writer may edit a worktree at a time, and children must not delegate recursively. Fleet Kit is a set of instructions and tools, not a scheduler or an OS sandbox. It is not an official OpenAI or GitHub product.

## Install a plugin

Download `fleet-kit-plugins-0.1.0.zip` from the [v0.1.0 release](https://github.com/Htkym/agent-fleet-kit/releases/tag/v0.1.0) and extract the entire archive, including the hidden `.agents` and `.github` directories. GitHub's **Source code** archives contain development source; use the attached plugin ZIP for installation. The release also includes `SHA256SUMS`.

Run the commands for your CLI from the extracted directory containing `plugins/` and `package-manifest.json`.

### Copilot CLI

```powershell
copilot plugin install .\plugins\fleet-copilot
copilot plugin list
```

### Codex CLI

```powershell
codex plugin marketplace add .
codex plugin add fleet-codex@fleet-kit-codex
codex plugin list --json
```

| Edition | Included components | Model selection |
|---|---|---|
| `fleet-copilot` | Three Skills and seven native Markdown Agent profiles | Inherits Copilot configuration |
| `fleet-codex` | Three Skills and seven role contracts bundled as Skill resources | Uses authorized session models; installs no model map |

The Codex plugin does not register named TOML Agents. Its orchestrator reads the bundled role contracts and passes them to the supported child launcher. Copilot profiles may appear under names such as `fleet-copilot:fleet_explorer`; use the names actually discovered.

Start a new CLI session in your target project. Confirm the effective Skills and, for Copilot, Agent profiles. Resolve same-name project or personal Skills before use. See [plugin installation, updates, removal, and runtime observations](docs/plugins.md).

## Use the Skills

In Codex, request `$fleet-orchestrator` from `fleet-codex`. In Copilot, request the `fleet-orchestrator` Skill from `fleet-copilot`. Include the requirement, permitted files, and verification command. Replace the paths and command in this example with your project's actual values:

```text
Use the fleet-orchestrator Skill from the installed Fleet plugin.
Fix the five-years-or-more eligibility boundary in src/eligibility.cjs.
Only that source file may be edited. Preserve existing input validation.
Run node --test tests/eligibility.test.cjs, obtain independent review,
and report the actual test result and remaining limitations.
```

## When to use it

Use `fleet-orchestrator` for a non-trivial request with independent research, a bounded implementation, verification, or independent review. Use the specialist Skills by themselves when only an evidence-based review or a measured comparison is needed.

Do not use Fleet for a simple question, a typo, or a short tightly coupled edit that Root can complete directly. Child Agents must not recursively delegate work.

## Skills and roles

| Skill | Purpose |
|---|---|
| fleet-orchestrator | Role selection, ownership assignment, verification, independent review, and result collection |
| evidence-review | Review diffs and requirements, returning location, severity, reproduction conditions, and unchecked scope |
| benchmark-lab | Compare measured results under fixed conditions, recording correctness, repetitions, raw data, and measurement limits |

Specialist Skills do not start Fleet and can be used independently.

| Role | Responsibility |
|---|---|
| fleet_explorer | Investigate implementation and call sites |
| fleet_researcher | Independently research specifications and existing tests |
| fleet_implementer | General implementation with a fixed contract |
| fleet_verifier | Run real tests and verify results |
| fleet_reviewer | Normal independent review |
| fleet_worker_fast | Narrow routine transformation with fixed rules and target |
| fleet_reviewer_critical | Critical review of public contracts, state transitions, lifetime, data integrity, and similar concerns |

Do not start all seven Agents every time. Return design decisions and unexpected failures to Root, and do not recursively delegate from children.

## Requirements and verified scope

Using a plugin requires the corresponding CLI with native Plugin support, authentication, and access to authorized models. Local observations used Codex CLI `0.153.4` and Copilot CLI `1.0.84-1` on Windows. These are observed versions, not guaranteed minimum versions.

The September 7 records cover all seven Copilot roles and standalone measurement. Codex plugin installation and Skill discovery were checked without inference. The original Codex project edition has separate runtime records. See [compatibility](docs/compatibility.md) and [plugin observations](docs/plugins.md#local-runtime-observations-2026-09-07) for the exact scope.

Building and testing this source Kit requires Windows, PowerShell 7.4 or later, and Git. Standard checks require neither CLI sign-in nor an API key. Authenticated runtime checks are opt-in.

## Build plugins from source

Run from the source repository root:

```powershell
pwsh -NoProfile -File scripts/package.ps1
pwsh -NoProfile -File scripts/package.ps1 -VerifyOnly
```

The complete distribution is generated under `.local/build/plugins/`. Change into that directory before running the plugin installation commands above. Packaging does not install plugins or change personal settings. Edit the source and regenerate rather than editing generated files.

## Generate project files

The following sections describe project-file placement as an alternative to plugins.

### Codex project edition

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

### Copy Codex project files

Generate a preview, then copy only the required assets from its `payload/` directory into the corresponding locations in the target project. Inspect conflicts before copying. Do not edit generated output directly; update this repository's source of truth and regenerate.

| Generated location | Target project location |
|---|---|
| `payload/.agents/skills/<Skill-name>/` | `.agents/skills/<Skill-name>/` |
| `payload/.codex/agents/fleet_*.toml` | `.codex/agents/fleet_*.toml` |

`fleet-orchestrator` and `fleet_reviewer_critical` expect the specialist Skills to exist under the project's `.agents/skills/`. See [config.fragment.toml.template](templates/codex/config.fragment.toml.template) for a configuration fragment. Do not replace existing configuration wholesale; inspect and add only the required entries.

Start a new Codex session in the target project and explicitly request the project Skill. Include the requirement, permitted files, and verification command as in the usage example above. The model map and TOML configuration apply to this project edition; neither plugin installs them. See [operations](docs/operations.md) for updates and optional diagnostics.

### Copilot project edition

```powershell
pwsh -NoProfile -File scripts/render.ps1 -Target Copilot -Preview
pwsh -NoProfile -File scripts/verify.ps1 -Bundle .local/build/copilot-preview
```

Copy the required `skills` and `agents` directories from `.local/build/copilot-preview/payload/.github/` into the project's `.github/`, including Skill references and assets. Inspect collisions first. Copilot can also discover `.agents/skills`, so resolve any competing same-name Codex definitions before use. Models inherit Copilot settings. See [Copilot setup and discovery checks](docs/copilot-cli.md).

Both preview editions have `installable=false`: the legacy Kit installer refuses normal apply. This is separate from native plugin installation.

## Operating safely

- Preserve existing diffs, staged files, and untracked files. Never discard or rewrite them without explicit authorization.
- Treat role prompts and TOML configuration as operating conventions, not OS-enforced security boundaries.
- Use dry runs for user-environment changes. Inspect proposed differences before an explicit apply operation.
- Keep credentials, personal configuration, raw logs, and local evidence outside Git. `.local/` is the intended local-only location.
- Do not treat child completion as acceptance or thread release. Root must check evidence, actual changes, and remaining commands.

## Verify changes

Run all [contributor checks](CONTRIBUTING.md#changes-and-checks) after source changes. They cover regression tests, both preview targets, and plugin packaging, and also run in Windows CI. For a project using Fleet, also run that project's standard verification commands after updating assets. Static checks do not establish runtime behavior or OS-enforced permissions.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

## License

[MIT License](LICENSE). See the license text at the [Open Source Initiative](https://opensource.org/license/mit).
