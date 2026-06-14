# Security Policy

## Scope

This is a public repository for automated, AI-assisted RHEL patching that combines Red Hat Lightspeed, Ansible Automation Platform (AAP), and Event-Driven Ansible (EDA) with ServiceNow ITSM integration. It contains **patterns, playbooks, CaC object definitions, and docs only** — no live credentials, tokens, or environment-specific values.

## What Should Never Be Committed

- AAP tokens, ServiceNow credentials, Red Hat Insights/Lightspeed service-account secrets, or AWS keys
- Customer or company names, RHDP deployment URLs, cluster/instance IDs, or other identifying details (committed files use generic placeholders; real values live only in the gitignored `docs/dev-environment.sh`)
- EDA event-stream shared secrets or OAuth credentials
- Passwords, private keys, or session cookies

Per-developer secrets belong in `docs/dev-environment.sh` (gitignored). Commit only `docs/dev-environment.sh.example` with placeholder values. CI fails the build if the secrets file is ever committed.

If any of the above is committed by mistake, rotate the affected credential immediately and open an issue so it can be removed from history.

## Supported Versions

Only the latest commit on `main` is maintained.

## Reporting a Vulnerability

Open a public GitHub issue for general security concerns. If you believe disclosure would cause active harm, contact the maintainer directly.
