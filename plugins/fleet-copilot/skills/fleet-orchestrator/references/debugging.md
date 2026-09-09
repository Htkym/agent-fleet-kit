# Diagnostics

For startup failures, investigate evidence in this order: CLI version, configuration layers, model and reasoning, effective permissions, and availability limits.
Do not silently ignore unknown configuration keys. Check them with the target CLI's strict parser.
Do not use a model's self-report as evidence of its availability. Without runtime metadata, record `unverified`.
Match the log's command, exit code, and revision, then compare it to a baseline under the same conditions.
When the baseline did not run, use `unclassified` rather than asserting an existing failure.
Retry the same cause once at most; if that does not resolve it, replan.
Do not record unobservable usage or failed model runs as zero tokens or success.
