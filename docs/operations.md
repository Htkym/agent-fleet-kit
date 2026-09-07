# Generation, deployment, and rollback

General usage instructions are in the [README](../README.md). This page explains management scripts and optional diagnostics.

## Local files

Store temporary work in `.local/runs/`, generated output in `.local/build/`, and results in `.local/artifacts/`. When setting `-OutputPath` or `-OutputDirectory` manually, use `.local/` for non-public output. Dedicated diagnostic state that includes authentication is an exception kept outside Git and must not be moved or copied into the repository.

If `.local/archive/` exists locally, it holds historical records. Do not rewrite absolute paths, manifests, or logs in moved records because they preserve evidence from the time. Do not resume an old diagnostic session directly; prepare a new one from the current definition when needed.

## Dry runs and managed assets

Run from the Kit root. Set `$destination` to the home directory or project to inspect.

```powershell
$destination = (Resolve-Path .).Path
pwsh -NoProfile -File scripts/install.ps1 -DestinationHome $destination -OutputPath .local/artifacts/install-plan.json
pwsh -NoProfile -File scripts/rollback.ps1 -DestinationHome $destination
```

Both commands default to dry runs. They propose changes to `config.toml` and `AGENTS.md` but do not edit them automatically. Managed assets are generated Skills and Agents. Unmanaged files are never overwritten, even when identical, and manual edits to managed assets are detected.

A preview bundle rejects normal `-Apply`. `-Fixture` is only for marked disposable fixtures under `.local/runs/tests/`; it is not a deployment path for normal environments. For normal use, deploy project assets only within the scope described in the README.

## Updates and recovery

Change the source of truth, regenerate, and inspect the diff and verify result. Do not change the manifest to ignore manual edits to generated files.

To remove a managed deployment, inspect the dry run and then run `rollback.ps1 -Apply`. An interrupted operation retains pending state and backups. After confirming that the destination has no later edits, recover with `rollback.ps1 -Apply -RecoverPending`. Links, paths outside ownership, and hash mismatches stop processing.

## Optional diagnostics

`doctor.ps1` lists deployment candidates, conflicts, overrides, and model candidates. It is not runtime verification involving authentication. Its output includes local paths and must not be published.

```powershell
pwsh -NoProfile -File scripts/doctor.ps1 -OutputPath .local/artifacts/doctor.json
pwsh -NoProfile -File tests/evals/run.ps1
```

The evaluation writes only a twelve-condition plan by default. `-Execute` stops with exit code 2 until the four automated-verification gates are met.

`tests/integration/smoke.ps1` and `scripts/validation-session.ps1` are experimental paths for the legacy isolated app-server diagnostic. They are not required for normal CLI Skill use. Setup needs a real `-CodexPath` and `-UserHome` and creates new dedicated state outside Git. The user signs in personally; personal credentials are not duplicated. Processing stops when protected assets change. The diagnostic can stop incomplete where thread release cannot be observed.
