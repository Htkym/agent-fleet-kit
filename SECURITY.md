# Security

Do not publish credentials, personal configuration, run logs, or dedicated diagnostic state. `.local/` is excluded from Git, but that does not prevent disclosure through forced additions or moved files.

Report vulnerabilities through GitHub's private reporting feature on the Security tab when it is available. If it is unavailable, do not put secrets or reproduction attack steps in a public issue; use a contact that contains no sensitive information to ask for a private reporting channel.

The current source is the supported remediation target. Fixes for earlier releases are not guaranteed. Do not include personal configuration contents, tokens, authorization URLs, or raw logs in ordinary defect reports.

An Agent's non-editing instructions are not an OS-enforced boundary. Manifest hashes are not signatures. Do not manually change automated deployment gates and treat them as verified.
