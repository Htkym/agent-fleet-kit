# Interruption and resumption

Root stores the run and task revision, baseline, decisions, state, Agent and PID, changed files, evidence, unresolved items, and safe next action in run state.
Update it when a child completes, design is fixed, requirements change, and integration completes. Do not store internal reasoning or secrets.
After interruption, check the actual Git state and hashes, and whether PIDs you started still exist.
Do not run the same operation again until confirming side effects from unfinished commands. Do not stop another process by name alone.
When requirements change, update `task_revision`, stop affected children, and assign them again.
Keep stale artifacts as evidence, but do not reuse them as success under current requirements.
When availability is exhausted, stop new launches and retain recoverable results and the next required action.
`/btw` conversations and lockfiles are not the source of truth for work state.
