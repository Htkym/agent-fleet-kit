# Contributing

Report defects in an issue with reproduction conditions, expected and actual behavior, and your Windows, PowerShell, and Codex CLI versions. Do not attach credentials, personal configuration contents, or raw run logs. Follow [SECURITY.md](SECURITY.md) to report vulnerabilities.

## Changes and checks

Edit the source of truth in `skills/`, `agent-src/`, `policies/`, and `config/`, not generated TOML. Prefer standard features and existing code, keep changes limited to what is necessary, preserve existing diffs, and allow only one editor in a worktree at a time.

The Copilot-specific procedure is in `skills-copilot/`; its Agent template is in `templates/copilot/`. Shared contracts and specialist procedures are not duplicated. Do not edit generated Markdown profiles.

Install Windows, PowerShell 7.4 or later, and Git, then run these commands from the repository root:

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/render.ps1 -Preview
pwsh -NoProfile -File scripts/verify.ps1
pwsh -NoProfile -File .\scripts\render.ps1 -Target Copilot -Preview
pwsh -NoProfile -File .\scripts\verify.ps1 -Bundle .\.local\build\copilot-preview
pwsh -NoProfile -File .\scripts\package.ps1
pwsh -NoProfile -File .\scripts\package.ps1 -VerifyOnly
```

These checks require neither sign-in nor an API key. Do not commit `.local/`. Tests create disposable fixtures and never access personal credentials. Because the Kit uses Windows ACLs and DPAPI, successful execution on other operating systems is not currently required.

In pull requests, describe changed behavior, rationale, checks performed, and unverified scope. Add dependencies, configuration, or abstractions only when necessary.

CI pins [actions/checkout](https://github.com/actions/checkout) to a commit SHA and runs the three commands above with read-only permissions. It does not run authenticated inference or publish raw logs as artifacts.
