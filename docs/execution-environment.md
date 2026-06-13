# Execution Environment — build, publish, and load

The Lightspeed Patching demo needs a **custom Execution Environment (EE)**: the
Provision VM job template shells out to the `terraform` CLI, which is not in any
stock Red Hat EE. This EE adds Terraform plus the certified collections the
runtime playbooks need, all version-pinned.

- **Build context:** [`execution-environment.yml`](../execution-environment.yml)
  + [`collections/requirements.yml`](../collections/requirements.yml)
- **Galaxy auth template:** [`ansible.cfg.example`](../ansible.cfg.example)
- **CaC wiring:** `aap_config/files/hub_ee_registries.yml`,
  `hub_ee_repositories.yml`, `controller_execution_environments.yml`

## What's inside (manifest)

The EE description registered in Controller **is** the manifest — keep it in sync
on every bump:

| Component | Pinned version |
|-----------|----------------|
| Base image | `ee-minimal-rhel9:2.17.14` |
| Terraform | `1.15.6` |
| `amazon.aws` | `11.3.0` (certified) |
| `redhat.rhel_system_roles` | `1.120.5` (certified) |
| `servicenow.itsm` | `2.15.1` (certified) |
| `ansible.platform` | `2.7.20260604` (certified) |

Certified (Automation Hub) collections are preferred over community Galaxy. The
build applies OS errata (`microdnf upgrade`) to the base layer for security
hygiene — for fully-entitled patching, build on a **subscribed RHEL host**.

## Image flow

```
ansible-builder build ──► quay.io/zigfreed/lightspeed-patching-ee:vX.Y.Z
                                  │
        Private Automation Hub syncs it (hub_ee_registries + hub_ee_repositories)
                                  │
                          <PAH-host>/lightspeed_patching_ee:vX.Y.Z
                                  │
              Controller pulls it via the "Lightspeed Patching - Hub Registry"
              credential (pull: missing) ──► job templates run on it
```

The image never leaves the platform at job-run time; AAP pulls from PAH, not quay.

## Prerequisites

```bash
pip install ansible-builder            # already present: 3.1.0
podman login registry.redhat.io        # base image pull (interactive)
# ~/.ansible.cfg holds the Automation Hub offline token (see ansible.cfg.example).
# Must be a REAL file, not a symlink — ansible-builder's COPY/ADD ignores symlinks.
```

## 1. Build

```bash
ansible-builder build -f execution-environment.yml \
  -t lightspeed-patching-ee:latest --prune-images
```

## 2. Publish to quay.io (deliberate-update model)

Images carry an **immutable** semver tag; `latest` is moved too as a Hub-less
smoke-test convenience. Bump rule: CVE-only rebuild → patch · +collection →
minor · new base → major.

```bash
podman login quay.io                   # zigfreed account (interactive)
podman tag lightspeed-patching-ee:latest quay.io/zigfreed/lightspeed-patching-ee:v1.0.0
podman tag lightspeed-patching-ee:latest quay.io/zigfreed/lightspeed-patching-ee:latest
podman push quay.io/zigfreed/lightspeed-patching-ee:v1.0.0
podman push quay.io/zigfreed/lightspeed-patching-ee:latest
```

## 3. Sync into Private Automation Hub + register in Controller

This is Config-as-Code — no manual UI steps. Make sure `ee_version` in
`aap_config/group_vars/all.yml` matches the tag you pushed, then:

```bash
source docs/dev-environment.sh && ansible-playbook aap_config/load.yml
```

`load.yml` creates the `quay_io` remote registry, syncs the
`lightspeed_patching_ee` repository into PAH (waits for completion), creates the
`Lightspeed Patching - Hub Registry` pull credential, and registers/updates the
`Lightspeed Patching - EE` in Controller pointing at the PAH copy.

## 4. Ship a new version later

1. Edit the build context (bump a collection / terraform / base) and the manifest
   description in `controller_execution_environments.yml`.
2. Build, tag the **next** semver, push both tags (step 2).
3. Bump `ee_version` in `group_vars/all.yml`.
4. Re-run `load.yml` — PAH re-syncs the new tag and Controller pulls it once
   (`pull: missing` is safe because tags are immutable).

## Hub-less smoke test

To skip PAH and pull straight from public quay (no registry credential):

```bash
export LIGHTSPEED_PATCHING_EE_IMAGE=quay.io/zigfreed/lightspeed-patching-ee:latest
source docs/dev-environment.sh && ansible-playbook aap_config/load.yml
```
