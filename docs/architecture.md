# Responsibilities and boundaries

Root owns requirements, decomposition, ownership, budget, integration, and acceptance. Only one source writer, including Root, may work in a worktree at a time. Independent research and review can run in parallel.

| Location | Responsibility |
|---|---|
| `skills/` | Source of truth for orchestration and specialist procedures |
| `skills-copilot/` | Copilot orchestration adapter; reuses shared references, schemas, and specialist procedures |
| `agent-src/` | Ownership, prohibitions, and completion criteria for seven roles |
| `policies/` | Common contract embedded in generated Agents |
| `config/` | Model examples, role mappings, and budgets |
| `templates/` | Codex TOML, Copilot Markdown Agent profiles, and project-configuration templates |
| `scripts/` | Diagnostics, deterministic generation, manifest verification, deployment, and recovery |
| `tests/` | Contract, preservation, failure-handling, and optional runtime-diagnostic checks |
| `.local/` | Non-public work, generated output, and run records |

JSON Schema defines the Kit's work contract; it is not a Codex API argument. Normal CLI work can collect results as concise prose that retains the objective, revision, ownership, and acceptance criteria. A self-report alone is not proof of completion.

The manifest records hashes for source and generated output. Integrity checking is not a digital signature; it detects corruption or manual edits to trusted local assets. Legacy five-role manifests remain readable.

`render.ps1` defaults to Codex. `-Target Copilot -Preview` emits only `.github/skills` and `.github/agents` payloads into a separate default output directory. A Copilot target marker selects a strict manifest path allowlist and cannot unlock runtime installation. Existing manifests without a target remain Codex bundles. See [the Copilot edition](copilot-cli.md).

The role-level non-editing contract and OS-enforced read-only access are distinct. The parent's effective permissions can override a child's TOML default. Do not treat task completion as thread release; mark unobservable behavior as unverified.
