# Security Policy

## Scope

This is a public repository for setting up a Dynatrace → AAP Event-Driven Ansible integration (push model). It contains **patterns, docs, and rulebook scaffolding only** — no live credentials, tokens, or tenant-specific values.

## What Should Never Be Committed

- Dynatrace API tokens or AAP tokens of any kind
- The real Dynatrace tenant id / URL (committed files use the `<env-id>` placeholder; the real value lives only in the gitignored `docs/dev-environment.sh`)
- Event Stream shared secrets or dtctl OAuth credentials
- Passwords, private keys, or session cookies
- Customer or prospect names, company names, or identifying details

Per-developer secrets belong in `docs/dev-environment.sh` (gitignored). Commit only `docs/dev-environment.sh.example` with `REPLACE_ME_*` placeholders. CI fails the build if the real tenant id or the secrets file is ever committed.

If any of the above is committed by mistake, rotate the affected credential immediately and open an issue so it can be removed from history.

## Supported Versions

Only the latest commit on `main` is maintained.

## Reporting a Vulnerability

Open a public GitHub issue for general security concerns. If you believe disclosure would cause active harm, contact the maintainer directly.
