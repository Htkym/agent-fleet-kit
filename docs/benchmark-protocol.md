# Comparative evaluation protocol

The initial evaluation has four fixed cases and three conditions, for twelve one-time runs. The cases are a typo, a change requiring independent research, a local calculation, and a coupled change. `tests/evals/cases.json` defines the request, baseline, allowed paths, and invariant verification command. This is a small behavior check, not a study that estimates general performance differences.

| Condition | Configuration |
|---|---|
| A | Root only: gpt-6-astra / high |
| B | Fleet with the Root model assigned to every tier |
| C | Fleet using the tier mapping |

Execute each case sequentially in ABC, BCA, CAB, and ACB order. Each condition has a separate fixture with the same input, tests, and allowed scope. During comparison, manually stop other benchmarks and heavy builds, and record the starting OS, CLI version, configuration, time, and external load. Invalidate a trial with a known load conflict. This release does not implement machine-wide load exclusion, so do not start comparison when the operator cannot verify that condition.

The default run writes only a plan. `-Execute` stops with exit code 2 without calling a model until the four runtime-readiness gates are met. This file is a ledger Root checks against demonstrated evidence; changing a value to `true` does not prove runtime compatibility.

Reject a run before executing the verification command if the input verification script or protected files have changed. Check for source changes after execution as well. Compare baseline and final failures in logs, and classify existing failures, regressions, and environmental causes. A final test pass alone does not prove child startup, independent review, close, or permissions.

Record CLI wall-clock time, exit code, changed paths, external test results, and public JSONL turn usage as primary values. Assess Root integration time, rework, all-child usage, and total time to correct acceptance only when separate evidence exists. Use `null` or `unavailable` for unobservable values, and do not treat turn usage as the total across all threads. Do not calculate speed, cost, or context-reduction rates until complete measurements exist.

Stop subsequent trials after a crash or timeout. Record the reason and a separate attempt for retries. Do not retain only favorable trials; include failures and missing measurements in the report. Evaluate implicit invocation, increase repetitions, or tune model allocation only after baseline runtime verification.
