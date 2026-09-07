# Compatibility and verification scope

This records local verification as of 2026-09-07. Behavior can vary with CLI updates, the models available to an account, and higher-level configuration.

| Item | Verified scope |
|---|---|
| OS / PowerShell | Windows 10.0.26200 / PowerShell 7.6.5; scripts require 7.4 or later |
| Codex CLI | 0.153.4 using normal `exec --approve-for-me` |
| Root | gpt-6-astra / medium |
| Explorer / Researcher / Verifier / Worker Fast | gpt-5.6-terra / medium |
| Implementer | gpt-5.6-terra / high |
| Reviewer / Reviewer Critical | gpt-5.6-sol / high |
| Skill | Read and used all three definitions; verified specialist Skills independently |
| Agent | Named execution and task completion for seven roles; verified the original five and added two on separate tasks |

The model mapping is an example based on these observations. A FAST-tier candidate was not used for every role. Do not infer speed, cost, or quality advantages from model or role names.

## Verified tasks

- Investigated a defect in a total calculation and completed a bounded fix, existing tests, independent review, and Root acceptance.
- Reproduced, in an independent review, a boundary change that violated a "five years or more" requirement.
- Measured two candidates that produce identical totals for the same integer input over seven repetitions each after warmup.
- Performed a routine conversion of three JSON values and checked keys and values with real tests.
- Independently reproduced, in critical review, a public-contract violation that treated `completed` as terminal.

Personal-environment logs and account information are not distributed. This page summarizes verification; it is not a certificate guaranteeing reproduction in third-party environments.

## Unverified and separate determinations

The public instruction set was translated to English after the recorded practical normal-CLI verification. This release has static validation of the translation only; repeat practical runtime verification before treating the translated instructions as runtime-verified.

Child task completion and thread release are distinct. Thread release, permission enforcement independent of the parent, all boundary cases, all models, and implicit invocation remain unverified. This Kit uses Windows ACLs, DPAPI, and junctions, so Linux and macOS are not supported.

Treat preview generation, static verify, normal-CLI practical work, and isolated app-server diagnostics separately. Leave automated diagnostic gates `false` in `runtime-readiness.json`; normal-CLI use alone does not enable automated deployment.
