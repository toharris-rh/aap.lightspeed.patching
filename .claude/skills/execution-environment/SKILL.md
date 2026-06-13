---
name: execution-environment
description: >-
  Build, version, and update the custom Lightspeed Patching Execution Environment
  (terraform + certified collections) and ship it through quay.io → Private
  Automation Hub → AAP Controller. Covers the ansible-builder build, the
  immutable-semver deliberate-update model, and the hard-won build gotchas.
  TRIGGER when the user wants to build / rebuild / bump / update the EE, add or
  pin a collection in the EE, change the terraform version, bump ee_version, or
  hits EE errors (ImagePullBackOff, "No module named pip" in assemble, "couldn't
  resolve module/action", a collection missing at runtime).
  SKIP for AAP object CaC unrelated to the EE (use aap-config), pure Automation
  Hub/collection-version questions (use automation-hub), or credential/auth.json
  setup (use environment).
---

# Execution Environment — build & update

The custom EE (`execution-environment.yml` + `collections/requirements.yml` at
the repo root) bakes the **terraform CLI** + **certified collections** into
`ee-minimal-rhel9` so the Provision VM job template can shell out to terraform
and register hosts. Full runbook: [`docs/execution-environment.md`](../../../docs/execution-environment.md).

## The update lifecycle (deliberate-update model)

Images carry an **immutable semver tag**; Controller pins to `ee_version` with
`pull: missing`. To ship a change:

1. Edit the build context (collection pin, terraform version, base image) **and**
   the manifest `description:` in `aap_config/files/controller_execution_environments.yml`.
2. **Build** (the `PYCMD` arg is mandatory — see gotchas):
   ```bash
   ansible-builder build -f execution-environment.yml -t lightspeed-patching-ee:latest \
     --prune-images --build-arg PYCMD=/usr/bin/python3.11
   ```
3. **Tag + push** the next semver AND move `latest`:
   ```bash
   podman tag lightspeed-patching-ee:latest quay.io/zigfreed/lightspeed-patching-ee:vX.Y.Z
   podman tag lightspeed-patching-ee:latest quay.io/zigfreed/lightspeed-patching-ee:latest
   podman push quay.io/zigfreed/lightspeed-patching-ee:vX.Y.Z
   podman push quay.io/zigfreed/lightspeed-patching-ee:latest
   ```
4. **Bump `ee_version`** in `aap_config/group_vars/all.yml` (the single source of
   truth — the dev-environment EE-version export is commented out).
5. **`load.yml`** — PAH re-syncs the new tag (`hub_ee_repositories.yml`, `sync:
   true`/`wait: true`) and Controller re-registers the EE pointing at the PAH copy.
6. Relaunch the job template that uses it.

**Bump rule:** CVE-only rebuild → **patch** · +collection → **minor** · new base
image → **major**. (`v1.0.0` = initial; `v1.1.0` added `ansible.controller`.)

**Manifest convention:** the EE `description:` enumerates base image · terraform ·
each pinned collection — it IS the manifest. Keep it in sync on every bump.

## Collections

Certified (Automation Hub) preferred; pin to the **newest certified** version
(resolve via the **automation-hub** skill's Hub-API recipe). Current set:
`amazon.aws`, `redhat.rhel_system_roles`, `servicenow.itsm`, `ansible.platform`,
`ansible.controller`. RHEL registration uses the certified
`redhat.rhel_system_roles.rhc` role (no `community.general`).

## Build gotchas (all learned the hard way — do not "simplify" these away)

1. **`--build-arg PYCMD=/usr/bin/python3.11` is REQUIRED.** `redhat.rhel_system_roles`
   declares a `dnf` bindep; installing `dnf` pulls the Python 3.9 RPM, which
   repoints `/usr/bin/python3` → 3.9 (no pip). ansible-builder's `assemble` then
   dies with **`No module named pip`**. Pinning `PYCMD` to python3.11 keeps the
   build on the interpreter that has pip. (ARG reaches `assemble` via the RUN env.)
2. **terraform install must be a SINGLE-LINE `RUN`.** ansible-builder flattens
   multiline YAML to one line, turning `\` continuations into `backslash-space`
   that bash mis-parses. Keep the curl/unzip/mv on one line.
3. **`python3.11-devel` + `wheel` in `prepend_builder`** to compile systemd-python
   (transitive dep: ansible.platform → ansible.eda). Use `python3.11-devel`, NOT
   `python3-devel` (the latter installs Python 3.9 and shadows /usr/bin/python3).
4. **`ansible.platform` has NO host/group module.** Inventory host/group
   registration uses `ansible.controller.host` / `.group` (with `controller_host`
   / `controller_oauthtoken`). A playbook using `ansible.platform.group` fails
   with *"couldn't resolve module/action 'ansible.platform.group'"* AND needs
   `ansible.controller` baked into the EE.
5. **`microdnf upgrade` first** in `prepend_base` for OS-errata hygiene (cuts the
   Quay CVE count). Fully-entitled fixes need a subscribed RHEL build host.
6. **Base image is pinned** (`ee-minimal-rhel9:2.17.14`) for reproducibility — the
   manifest description states it.

## Where the pieces live

- Build context: `execution-environment.yml`, `collections/requirements.yml`
- Galaxy auth at build: your real `~/.ansible.cfg` (Hub token) — see **automation-hub**
- Registry logins (`podman login`, `auth.json`) — see **environment**
- quay → PAH sync + EE registration CaC: `aap_config/files/hub_ee_registries.yml`,
  `hub_ee_repositories.yml`, `controller_execution_environments.yml` — see **aap-config**
- Runbook with full commands: `docs/execution-environment.md`
