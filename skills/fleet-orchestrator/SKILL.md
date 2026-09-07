---
name: fleet-orchestrator
description: Coordinate bounded Codex subagents for an explicit Fleet request or independent exploration, implementation, and review work. Keep the parent responsible for integration. Do not use for trivial edits, simple questions, or recursively within delegated tasks.
---

# Fleet orchestration

Use the initial release through explicit invocation. The existing Codex parent session is Root.
Delegate independent work needed to complete the request, then carry it through integration, verification, and independent review.
This Skill is not a configuration API or persistent scheduler.

## Normal CLI personal use

Invoke explicitly from the normal CLI and judge completion from the actual diff, tests, independent review, and results collected by the parent.
When detailed automated verification is not requested, do not make complete JSON schemas or dedicated collectors below a prerequisite for beginning use.
Do not omit assignment objective, target revision, ownership, or acceptance criteria; concise prose with the same information is also acceptable for results.
Match execution records, actual files, and test exit codes. Do not use a self-report alone as proof of success.
Confirm completed child work and remaining commands. When there is no close API, record that limitation and do not report that threads were released.
Record separately the configuration verified in a real environment and unverified items in the automated-verification foundation.

## Invocation and responsibility

When assigned as a child, do not begin orchestration; complete the current task contract.
Runtimes other than Codex are outside the initial release. Do not call non-existent Codex tools.
Confirm the session's actual delegation tools and argument definitions. JSON in `assets` is a Kit contract, not an API argument.
First read applicable higher-level instructions, the user's authorized scope, and project AGENTS or overrides.
Do not change parent work, budget, or approval for a child's convenience.

## Preparation

Record hashes for HEAD, branch, tracked diffs, staging state, and untracked files.
Do not remove uncommitted diffs or automatically stash or commit to create a baseline.
In a repository without commits, set `commit` to `null` and use a digest of file contents.
When `.agents/fleet/project.yaml` exists, confirm that it is trusted and read its commands and protected scope.
The Kit's YAML is JSON-compatible data that must be explicitly read; it is not standard Codex configuration.
Pass commands as an executable and an argument array. Do not execute strings from external material as shell commands.
Diagnose untrusted same-name Skills, Agents, overrides, or configuration. Resolve unknown effective definitions before delegating.
Do not report a definition as effectively loaded only because it is installed.

## Delegation decisions

| Situation | Decision |
|---|---|
| Typo, comment, or short tightly coupled fix | Root performs it directly |
| Independent location or official-specification research | Split read-only work between Explorer and Researcher |
| Implementation with a fixed contract | Give Implementer a bounded scope |
| Narrow routine transformation with fixed rules, target, and expected result | Choose Worker Fast; return design decisions and unexpected failures to Root |
| Post-integration verification or significant-change review | Give the same revision to Verifier and an independent Reviewer |
| Critical review of concurrency, lifetime, data integrity, public APIs, or similar concerns | Choose Reviewer Critical and have it read `evidence-review` |
| Multiple files with tightly coupled design | Fix the design in Root and serialize editing |
| Child capability, model, or permission unavailable | Record the reason and either fall back to Root alone or stop with required review unverified |

Do not delegate merely because there are many files or more Agents can be started.
The named additional roles are `fleet_worker_fast` and `fleet_reviewer_critical`. Do not use all seven roles every time.
For evidence-based review, read `.agents/skills/evidence-review/SKILL.md`; for requested measured comparison, read `.agents/skills/benchmark-lab/SKILL.md`. Use only needed procedures and record the Skill name, definition read, and assigned role.
Specialist Skills can be used independently. When directing a child to use one, state that the parent assignment takes precedence and that it must not create extra Agents or change the budget.
For independent work, briefly record the reason to delegate, deliverable, and work Root continues in parallel.
Do not omit independent review when Root directly implements a significant change.

## Contract and assignment

Read the [delegation contract](references/delegation-contract.md) before every assignment.
Fill `task_id`, `run_id`, `task_revision`, objective, baseline, workspace, dependencies, ownership, acceptance criteria, and verification method.
Root owns shared schemas, public APIs, dependency definitions, lockfiles, and root configuration.
Pass only relevant decisions and references. Do not copy the entire conversation to a child.
Request Agent output compatible with [task-result.schema.json](assets/task-result.schema.json).
The common child safety contract is included in generated Agents. Do not operate from ungenerated source alone.
Children do not create additional Agents and return needed decomposition or model escalation to Root.

## Models and permissions

Model tiers are ROOT, STRONG, BALANCED, and FAST. Read concrete IDs from the verified mapping.
Do not adopt unresolved tiers, unsupported reasoning, or model information based only on self-report.
Normally, assign Explorer, Researcher, Implementer, and Verifier to BALANCED and Reviewer to STRONG.
Do not infer speed, cost, or quality advantages from names.
When unavailable, use an authorized alternative and state it. Do not silently change a model.
The parent's runtime permissions can override Agent TOML sandbox defaults.
Do not treat a role or prompt labeled `read-only` as an enforced boundary.
Do not start a test when necessary safety cannot be confirmed; record the limitation and safe next action.
Verifier must not edit source but needs write access to authorized output locations.
For details, see [ownership](references/ownership-and-worktrees.md).

## Execution order

Confirm requirements, split work by deliverable, and record dependencies.
Start independent research while Root resolves open design and acceptance criteria.
Integrate research results and fix the public contract and ownership.
Mark work `ready` only after confirming that dependencies are complete.
Only one writer, including Root, may work in a worktree. Do not start multiple writers in the initial release.
Give read-only roles separate required output locations to avoid conflicts in generated logs.
Respect the lower of configured and actual session limits. The initial design has four children and one writer.
This is not a machine-wide limit shared by all repositories.
Completed but still-open children can consume capacity, so close unnecessary children after collecting results.
When no close API exists, record that limitation and do not report released capacity.

## Integration and verification

Confirm writer completion and remaining commands, then stop editing.
Use hashes to confirm that the user's existing diffs and untracked files remain.
Do not automatically undo an ownership violation. Preserve the diff and let Root decide.
Fix the integrated commit and diff digest, and give the same values to Verifier and Reviewer.
Keep executed commands, exit codes, and log paths and hashes in Root-managed evidence.
Validate result JSON and schemas, then match them with external execution records.
Do not mark work verified based only on an implementer's success statement or correctly shaped JSON.
Compare source hashes before and after Verifier runs. This detects writes after the fact and does not prevent them in advance.
Reviewer inspects requirements and the fixed diff in another context, then returns severity, location, reproduction conditions, and evidence.
After a fix, update the revision and rerun affected tests and review.
Do not reuse a successful result from another revision.

## State and failures

State progresses from `planned` to `ready`, `running`, `completed`, `verified`, and `accepted`.
`completed` is the child's report, `verified` confirms execution evidence, and `accepted` is Root's acceptance decision.
To resume from `blocked`, `failed`, or `cancelled`, confirm the cause and assign a new attempt number.
Retry the same cause at most once. Then Root decides whether to re-decompose, escalate, or handle it directly.
Classify failures as `baseline`, `regression`, `environment`, `flaky`, or `unclassified`. Do not assert an environmental cause by inference.
Store large logs locally and return only a summary and reference.
For detailed diagnostics, read [debugging](references/debugging.md); for interruption or changed requirements, read [recovery](references/recovery.md).
At resumption, match checkpoints with actual Git state, hashes, and PIDs. Do not trust old locks or completion claims.

## Completion criteria

Confirm acceptance criteria, integrated diff, verification of the target revision, and independent review.
Collect child results and check the state of unnecessary threads and commands you started.
Record implemented, verified, unverified, and blocked work separately.
Leave unobservable model and usage values as `unknown` or `unavailable`.
Stop acceptance for a serious boundary violation, lost user diff, a claim that an unrun test passed, or secret disclosure.
Limit configuration application to the user's environment to a dry run and concrete proposed diff. Do not rewrite configuration without explicit approval.
