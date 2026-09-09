---
name: benchmark-lab
description: Compare implementations with fixed inputs, correctness checks, repeated measurements, and retained raw data. Use for a requested benchmark or measurement-based decision; do not infer speed or cost advantages from model or algorithm names.
---

# Small measured comparisons

This Skill can be used independently outside Fleet. Fix the work being compared, inputs, expected results, and the metric to decide, then use existing measurement code or the standard library. Do not add a general-purpose measurement framework.
First confirm that every candidate returns the correct result for the same input. Do not adopt a candidate that returns a different result solely because it is faster.

Before measuring, choose the environment, target revision, input size, operations per measurement, warmup count, repetition count, unit, and execution order.
Exclude JIT compilation and first-load work from measurement by warming up first. Repeat overly short work within a measurement so it exceeds clock resolution.
Measure in the same process, with the same input and correctness conditions. Use and record a simple method, such as alternating candidate order, to reduce execution-order bias.
Measure time with a monotonic clock. Do not opportunistically change inputs or correctness conditions during a run.

Save every measured value in CSV or JSON. Record failures, retries, and excluded measurements with their reasons; do not select only successful examples.
Retain the actual commands, exit codes, target hash, raw-data location, and unit, then calculate concise summaries such as median and spread from raw data.
Do not substitute example values, model predictions, or extrapolation for measured results. Calculate cost only when applicable usage and pricing are known.

Limit conclusions to the measured inputs, environment, and metrics. State limitations such as few repetitions, other processes, caches, and work outside the measurement scope.
Keep output locations and execution budget within the request. Do not change compared implementations or tests without authorization.
When used as a child, do not create additional Agents; return any need for a budget change or further comparison to Root.
