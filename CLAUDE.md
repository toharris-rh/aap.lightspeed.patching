# aap.lightspeed.patching — Claude Guidelines

Automated, AI-assisted RHEL patching that combines **Red Hat Lightspeed**,
**Ansible Automation Platform (AAP)**, and **Event-Driven Ansible (EDA)** with
full **ServiceNow ITSM** integration. Read [`README.md`](README.md) and
[`docs/servicenow-integration.md`](docs/servicenow-integration.md) first — they
hold the architecture and the as-built record.

## Skills in this repo

Repo-local Claude skills live under [`.claude/skills/`](.claude/skills/) and
ship with the repo (`.claude/*` is gitignored **except** `!.claude/skills/`).
Load the relevant skill before working in its area:

| Skill | Use when |
|-------|----------|
| [`.claude/skills/servicenow/SKILL.md`](.claude/skills/servicenow/SKILL.md) | ServiceNow / SNow, change requests, incidents, CMDB, work notes, the Insights→EDA→AAP→ServiceNow flow |
| [`.claude/skills/environment/SKILL.md`](.claude/skills/environment/SKILL.md) | Environment setup, credentials, dev-environment.sh, auth testing, env-var flow |
| [`.claude/skills/repo-workflow/SKILL.md`](.claude/skills/repo-workflow/SKILL.md) | Git/GitHub procedures — commit, push, open a PR, merge; `main` is protected so everything goes through a PR |
| [`.claude/skills/aap-config/SKILL.md`](.claude/skills/aap-config/SKILL.md) | CaC pipeline — `load.yml`, `aap_config/files/` objects, the dispatch role, and EDA wiring gotchas (rulebook activations, event streams, RH AAP credential) |
| [`.claude/skills/automation-hub/SKILL.md`](.claude/skills/automation-hub/SKILL.md) | Red Hat Automation Hub — certified vs community collections, resolving certified versions via the Hub API, EE builds pulling certified content, Private Automation Hub |
| [`.claude/skills/execution-environment/SKILL.md`](.claude/skills/execution-environment/SKILL.md) | Build / version / update the custom EE (terraform + certified collections) and ship it quay→PAH→Controller; build gotchas and the immutable-semver update model |
| [`.claude/skills/terraform/SKILL.md`](.claude/skills/terraform/SKILL.md) | The `terraform/` AWS provisioning (VPC + RHEL9 EC2, S3 state, t-shirt sizing), how `provision_vm_aws.yml` runs it from AAP, and the region/cred/EE gotchas |
| [`.claude/skills/lightspeed/SKILL.md`](.claude/skills/lightspeed/SKILL.md) | Red Hat Insights / Lightspeed API — OAuth2 service-account auth, Insights inventory + vulnerability endpoints, the `--display-name` hostname requirement, console.redhat.com RBAC roles, and the CVE→Insights→CMDB→incident linking pattern |
| [`.claude/skills/lightspeed-snow-setup/SKILL.md`](.claude/skills/lightspeed-snow-setup/SKILL.md) | SE setup guide for the native Lightspeed / Insights → ServiceNow integration (Flow Templates for Red Hat Insights app) — shared-instance model, the one fixed integration user, console.redhat.com wizard, and test/verify steps |
| [`.claude/skills/vm-access/SKILL.md`](.claude/skills/vm-access/SKILL.md) | SSH into provisioned VMs — AAP inventory lookup (gateway API path), host record parsing, SSH credentials and common health checks |

When you add a new skill, add a row here so future sessions discover it.

## Credentials & environment

- Real credentials live in `docs/dev-environment.sh` (**gitignored** — never
  commit, never paste into chat). The committed template is
  `docs/dev-environment.sh.example`; copy it and fill in values.
- Load everything in one shell invocation — env vars do **not** persist across
  separate Bash tool calls:
  ```bash
  source docs/dev-environment.sh && ansible-playbook playbooks/servicenow/<play>.yml
  ```
- **Use the exact `SN_USERNAME` from `docs/dev-environment.sh`** — a
  plausible-but-wrong username variant returns HTTP 401 `User Not
  Authenticated`, not a clear error.
- **Never print `SN_PASSWORD` / `EDA_EVENT_STREAM_TOKEN`** — check by name:
  `printenv SN_PASSWORD >/dev/null && echo set`.

## Shared ServiceNow instance

The ServiceNow instance (`SN_HOST` in `docs/dev-environment.sh`) is **shared**
with ~33 other SEs. Scope every write
by `sys_id`, never by name alone. Do not create or alter global/instance-wide
objects (users, store apps, system properties) without explicit confirmation —
they affect everyone on the instance.

## Project conventions

- **No project-local `ansible.cfg`** — the user's `~/.ansible.cfg` holds the
  Automation Hub `galaxy_server` token shared across repos and teammates. A
  project-local cfg shadows it and breaks `ansible-galaxy collection install`
  for Red Hat certified content. Set inventory/options via CLI flags or env vars.
- **`ansible.platform` over `ansible.controller`** — `ansible.controller` is
  legacy; never use it in new code.
- **Always delete AAP tokens** — any playbook that creates a token must delete
  it in an `always:` block so stale tokens don't accumulate.
- **CHANGELOG.md** — every change adds an entry under Added / Changed / Fixed /
  Removed.
- **Additive only** — don't remove old capabilities until replacements are proven.
- **One concern per PR** — group changes by shared root cause.
- **Never put customer info in tracked files** — no customer names, RHDP URLs,
  cluster/instance IDs, passwords, or tokens in any committed file, commit
  message, PR, or issue. Use generic placeholders. The live host and any creds
  belong only in the gitignored `docs/dev-environment.sh`.
- **Images go in `docs/images/`** (committed, not gitignored).
  `docs/dev-environment.sh` is the only gitignored file under `docs/`.

## Issue tracking (GitHub)

This repo lives on GitHub (`toharris-rh/aap.lightspeed.patching`). Follow
**document-before-fixing**: open a GitHub Issue describing the problem before
making code changes, and **label every new issue** with all labels that fit
(`gh label list --repo toharris-rh/aap.lightspeed.patching`).

## Two integration paths — keep them straight

This repo implements the **EDA path** (Insights webhook → AAP EDA event stream →
AAP workflow → ServiceNow via `playbooks/servicenow/*`). It is distinct from the
**native HCC→ServiceNow** integration (the "Flow Templates for Red Hat Insights"
ServiceNow store app, `x_rhtpp_rh_webhook`), which routes Insights events
straight into ServiceNow without AAP. See the servicenow skill for the full
comparison and the current install state of the shared instance.

## Repo status (as of 2026-06-12)

Full CaC pipeline in place: `aap_config/load.yml` entrypoint,
`aap_config/requirements.yml` for collections, controller + EDA object
definitions under `aap_config/files/`, playbooks for patching / CVE remediation /
VM provisioning / registration, and EDA rulebooks. ServiceNow callback playbooks
and the native HCC→ServiceNow integration docs are also present.
