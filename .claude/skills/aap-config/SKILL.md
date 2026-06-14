---
name: aap-config
description: >-
  Configuration-as-Code for the AAP instance in aap.lightspeed.patching — the
  aap_config/load.yml pipeline, the files/ object definitions, the
  infra.aap_configuration dispatch role, and the EDA wiring (rulebook
  activations, event streams, EDA credentials, decision environments).
  TRIGGER when the user mentions CaC, load.yml, aap_config, configuration as
  code, dispatch role, infra.aap_configuration, controller objects (job
  templates, workflows, projects, inventories, schedules), gateway settings, or
  anything EDA: rulebook activation, decision environment, event stream, EDA
  project, RH AAP credential, "requires a RH AAP credential", "not found for
  project", __SOURCE_1.
  SKIP for credential/env-var setup mechanics (use the environment skill) and
  for ServiceNow ITSM workflow logic (use the servicenow skill).
---

# AAP Configuration-as-Code — aap.lightspeed.patching

How the AAP instance is built declaratively from `aap_config/`. Everything is
applied by one entrypoint and is idempotent — re-running is safe and expected.

## Pipeline

```
source docs/dev-environment.sh
  → ansible-playbook aap_config/load.yml
      → tasks/aap_token_acquire.yml   (mint short-lived write token, or use $AAP_TOKEN)
      → infra.aap_configuration.dispatch role
          → reads every files/*.yml loaded in load.yml's vars_files
          → creates/updates objects on the AAP gateway + controller + EDA
      → always: tasks/aap_token_release.yml  (delete the minted token)
```

Run it (tee a timestamped log):

```bash
source docs/dev-environment.sh && \
ansible-playbook aap_config/load.yml 2>&1 | tee /tmp/load-$(date +%Y%m%d-%H%M%S).log
```

Success = `PLAY RECAP ... failed=0`. The token is always deleted in the `always`
block (per repo convention — no stale tokens).

## `aap_config/files/` — one file per object class

`load.yml` lists these in `vars_files` and the dispatch role applies them in
order: gateway settings/orgs → EDA (credentials, event streams, projects,
rulebook activations) → controller (credential types, credentials, projects,
inventories, EEs, job templates, workflows, schedules).

Each file holds one top-level var (e.g. `eda_rulebook_activations:`,
`controller_job_templates:`). **Never** define the same top-level key in two
files — `include_vars`/`vars_files` overwrites, and only the last wins (this
exact class of bug bit the F5 repo's workflows).

All names and secrets resolve from `aap_config/group_vars/all.yml`, which pulls
secrets from env vars via `lookup('ansible.builtin.env', ...)`. See the
**environment** skill for the env-var→variable flow. No secrets in `files/`.

## EDA wiring — where the landmines are

EDA is stricter and less forgiving than the controller side. The working
patterns below are confirmed against `dc1.azure`, `aap.eda.dynatrace`, and
`aap.eda.dynatrace.push` (sibling repos under `/home/eames/git-repos/`) — when
something EDA-related breaks, **diff against those repos first.**

### Rulebook activations (`files/eda_rulebook_activations.yml`)

```yaml
eda_rulebook_activations:
  - name: "{{ eda_catalog_activation_name }}"
    project: "{{ eda_project_name }}"
    organization: "{{ my_organization }}"
    rulebook: servicenow_events.yml          # bare filename, NOT rulebooks/servicenow_events.yml
    decision_environment: "{{ eda_decision_environment }}"
    extra_vars: |                            # YAML *string*, not a dict (see Gotcha 5)
      my_organization: {{ my_organization }}
      my_snow_catalog_short_description: {{ my_snow_catalog_short_description }}
    event_streams:
      - event_stream: "{{ eda_event_stream_name }}"
        source_name: __SOURCE_1              # EDA names an unnamed rulebook source __SOURCE_1
    eda_credentials:                         # NOT `credentials:` — see gotcha below
      - "{{ eda_controller_credential }}"
    enabled: true
    state: present
```

**Gotcha 1 — rulebook is a bare filename.** EDA indexes rulebooks from the
project's `rulebooks/` directory and references them by filename only. A
repo-relative path (`rulebooks/servicenow_events.yml`) fails with *"<file> not
found for project."* (issue / PR #11.)

**Gotcha 2 — the credential key is `eda_credentials`, not `credentials`.** The
`infra.aap_configuration.eda_rulebook_activations` role reads
`eda_credentials: "{{ __ra_item.eda_credentials | default(omit) }}"`. There is
**no** `credentials` parameter, so a `credentials:` key is silently dropped and
the activation ends up with no RH AAP credential, failing with
*"The rulebook requires a RH AAP credential."* (issue #12). Any rulebook that
uses `run_job_template` / `run_workflow_template` needs a
`credential_type: "Red Hat Ansible Automation Platform"` credential attached via
`eda_credentials`.

**Gotcha 3 — `extra_vars` carry the rulebook's condition vars.** If the rulebook
references `vars.X` or `{{ my_organization }}` in a `run_workflow_template`
action, that var must be injected here or the activation errors at runtime
(`'X' is undefined`) and no workflow launches.

**Gotcha 4 — `__SOURCE_1`.** An unnamed source in a rulebook is auto-named
`__SOURCE_1`; bind the event stream to it via `source_name: __SOURCE_1`.

**Gotcha 5 — `extra_vars` must be a YAML *string*, not a dict** (idempotency).
The `ansible.eda.rulebook_activation` module declares `extra_vars` as
`type: str`, and EDA stores it as block YAML. Passing a dict makes Ansible
coerce it to a Python-repr string (`{'my_organization': ...}`) that never equals
EDA's stored value, so the module perceives a change on **every** re-run and
issues a PATCH — which EDA forbids on a running activation, failing with
*"Activation is not in disabled mode and in stopped status."* Author it as a
literal block scalar matching EDA's stored form so re-runs are a true no-op
(issue #17):

```yaml
extra_vars: |
  my_organization: {{ my_organization }}
  my_snow_catalog_short_description: {{ my_snow_catalog_short_description }}
```

Note `dc1.azure` / `aap.eda.dynatrace*` still use the dict form and carry the
same latent bug — they just haven't been re-run against a running activation.

### EDA credentials (`files/eda_credentials.yml`)

EDA has its **own** credential store, separate from `controller_credentials`.
The controller-launch credential is type `"Red Hat Ansible Automation Platform"`
with `host: "{{ aap_hostname }}/api/controller/"`. The event-stream token
credential is type `"Token Event Stream"` (the event stream's type derives from
this credential's type; there is no separate `event_stream_type` field).

## Conventions for editing CaC

- **Idempotent, additive (but not subtractive)** — re-running `load.yml` is
  safe; it creates or updates objects but **never deletes** them. This means
  orphaned nodes (e.g. workflow nodes removed from `files/` but still in AAP)
  survive across re-runs. When you restructure a workflow and orphaned nodes
  remain, **delete the workflow object in AAP and re-run `load.yml`** to
  recreate it clean. Use the controller API or the AAP UI to delete, then let
  CaC rebuild from the definitions in `files/`.
- **No duplicate top-level keys** across `files/*.yml`.
- **Names live in `group_vars/all.yml`**, referenced by var everywhere — don't
  hard-code object names in `files/`.
- **Push before you load** — the EDA project syncs rulebooks from GitHub `main`,
  so commit + push + (let the EDA project sync) before relying on a *rulebook*
  change being live. Activation *definitions* in `files/` are read locally and
  don't need a merge to test. (`main` is protected — see the repo-workflow skill.)
- **Testing on a feature branch** — the CaC project definition
  (`controller_projects.yml`) hardcodes `scm_branch: main`. To test CaC +
  playbook changes on a feature branch before merging:
  1. Temporarily edit `controller_projects.yml` to set `scm_branch:` to your
     branch name (e.g. `feature/enrich-cmdb-ci`).
  2. Run `load.yml` — this updates the AAP project to point at the branch,
     syncs it, and applies all CaC objects.
  3. Test in AAP (workflow visualizer, launch JTs, etc.).
  4. **Revert** `controller_projects.yml` back to `scm_branch: main` before
     committing — do **not** commit the branch override. After merging the PR,
     run `load.yml` once more from `main` to restore the project pointer.
- **Update `CHANGELOG.md`** for every change.

## Upstream reference

The CaC roles (`dispatch`, `eda_rulebook_activations`,
`controller_settings`, …) come from the **redhat-cop `infra.aap_configuration`**
collection. When a role's behavior is unclear (which key it reads, idempotency
quirks, arg specs), read the role source — locally under
`~/.ansible/collections/ansible_collections/infra/aap_configuration/roles/`, or
upstream:

- Collection (4.6.0 branch): <https://github.com/redhat-cop/infra.aap_configuration/tree/release/4.6.0>

`aap_config/requirements.yml` currently pins `infra.aap_configuration` 4.4.0;
check that pin before assuming a 4.6.0 feature/fix is present.
