# Fleet Kit development

Read the request and existing code before making changes. Prefer existing implementations and standard features, and keep changes to the necessary minimum.
Root owns shared schemas, configuration, generation, and deployment code. Only one writer may edit a worktree at a time.
Children do not recursively delegate. Independent read-only research and reviews may be delegated with an explicit scope and ownership.
Preserve existing diffs, staging state, and untracked files. Do not discard diffs or rewrite history without a request.
Default to dry runs for changes to a user's environment. Confirm the authorized scope before changing anything other than fixtures.
Required checks: `pwsh -NoProfile -File tests/run.ps1` and `pwsh -NoProfile -File scripts/verify.ps1`.
Before verify, generate from the current source with `scripts/render.ps1 -Preview`.
Keep local output in `.local/`; do not commit credentials, personal configuration, or raw logs.
Distinguish implementation, static verification, and runtime verification. Do not report an unverified result as adopted.
