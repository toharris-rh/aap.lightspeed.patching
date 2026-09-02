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

**Runtime — needs Python 3.11–3.13 (not 3.14).** The pinned stack
(ansible-core 2.18 + the collections in `aap_config/requirements.yml`) does not
support Python 3.14. On Fedora's system `python3` 3.14 the apply fails with a
`UnicodeEncodeError` (latin-1 header encoding) and then a spurious EDA `401`.
Run `load.yml` from a venv on python3.12/3.13 (the collections in
`~/.ansible/collections` are interpreter-independent and are reused):
`python3.13 -m venv ~/.venvs/lsp && ~/.venvs/lsp/bin/pip install 'ansible-core==2.18.12'`,
then `source ~/.venvs/lsp/bin/activate` before the run.

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

### EDA auth — the minted Controller token does NOT work for EDA (401)

**Symptom:** every `controller_*` role applies (`ok=NNN`) but `eda_credentials`
fails with `AuthError: Failed to authenticate with the instance: 401
Unauthorized` — so event streams and rulebook activations never apply. This is
the classic "EDA is the last failure."

**Cause:** `tasks/aap_token_acquire.yml` mints a token with
`ansible.platform.token`, which **auto-returns `ansible_facts.aap_token`**.
Ansible promotes that to a host fact that **overrides** the empty `aap_token`
group_var, and the dispatch passes `aap_token` as `controller_token` to *every*
module — EDA included. The minted token is a **Controller OAuth token**: the
Controller API accepts it, but the **EDA API rejects Controller tokens** (401).
(The `aap_token_acquire.yml` comment about avoiding the `aap_token` *name* —
issue #61 — is about a different mechanism; the module's `ansible_facts` return
defeats that intent here.)

**Fix (in place):** after minting, `aap_token_acquire.yml` clears the fact
(`set_fact: aap_token: ""`) so the dispatch uses `aap_username` / `aap_password`
**basic auth**, which BOTH the Controller and EDA APIs accept. `cac_token_obj`
still holds the minted token for cleanup. Confirm basic auth reaches EDA with:
`curl -sk -u "$AAP_CONTROLLER_USERNAME:$AAP_CONTROLLER_PASSWORD" "${AAP_HOSTNAME%/}/api/eda/v1/event-streams/"`
(200 = good). An event stream is a standalone object — it creates with no
activation, and AAP then exposes its inbound URL + token for the external
integration (e.g. the console.redhat.com "Event-Driven Ansible" integration).

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

## Phase 11 CaC objects (Automated CVE Remediation)

Phase 11 (issue #84) added these objects, applied by `load.yml`:

| Type | Object Name | CaC file | Purpose |
|------|------------|----------|---------|
| Event stream | Lightspeed Patching - Insights Event Stream | `eda_event_streams.yml` | Receives native Insights vulnerability webhooks (Token type) |
| EDA credential | Lightspeed Patching - Insights Event Stream | `eda_credentials.yml` | Token Event Stream credential; `http_header_key: X-Insight-Token` |
| Activation | Lightspeed Patching - Catch Insights CVE Events | `eda_rulebook_activations.yml` | Runs `insights_vulnerability_events.yml` rulebook |
| Credential type | Lightspeed Patching - Insights API | `controller_credential_types.yml` | Custom kind=cloud; injects `INSIGHTS_CLIENT_ID/SECRET/BASE_URL` |
| Credential | Lightspeed Patching - Insights API | `controller_credentials.yml` | Instance of the custom type (`cred_insights_api`) |
| Credential | Lightspeed Patching - Insights | `controller_credentials.yml` | Built-in Insights type (`cred_insights`); for future `scm_type: insights` project |
| Workflow | Lightspeed Patching - Automated CVE Remediation | `controller_workflow_job_templates.yml` | Fetch Remediation → Create CVE Incident (Slices 4-7 add more nodes) |
| JT | Lightspeed Patching - Introduce CVE (Demo Setup) | `controller_job_templates.yml` | Downgrade package + self-POST to EDA |
| JT | Lightspeed Patching - Fetch Insights Remediation | `controller_job_templates.yml` | Query Insights API, create remediation plan, download playbook |
| JT | Lightspeed Patching - SNow Create CVE Incident | `controller_job_templates.yml` | Create INC with CI link + playbook work note |

### Custom credential type pattern

When AAP's built-in credential types can't attach to job templates (e.g.
kind=`insights` refuses with *"Cannot assign a Credential of kind insights"*),
create a **custom kind=`cloud` credential type** with env-var injectors:

```yaml
- name: "Lightspeed Patching - Insights API"
  inputs:
    fields:
      - id: client_id
        type: string
        label: "Service account client ID"
      - id: client_secret
        type: string
        label: "Service account client secret"
        secret: true
  injectors:
    env:
      INSIGHTS_CLIENT_ID: !unsafe '{{client_id}}'
      INSIGHTS_CLIENT_SECRET: !unsafe '{{client_secret}}'
```

The `!unsafe` on injector values is required — without it, Ansible tries to
template the Jinja delimiters as its own variables. This pattern is confirmed
working (issue #101, fixes #78).

### Event stream forwarding toggle

The **"Forward events to rulebook activation"** toggle on an event stream must
be **ON** for events to reach the bound rulebook activation. It is intentionally
left **manual** for the Insights event stream — staging a CVE shouldn't
auto-launch the remediation workflow. Flip it ON when ready to demo. The toggle
is an AAP UI setting, not managed by CaC.

### Project sync after merge

`scm_update_on_launch` is **OFF** on the Lightspeed Patching project (to avoid
~25s redundant syncs per workflow node). After merging playbook changes to
`main`, **manually sync the controller project** so JTs pick up the new code:

```bash
source docs/dev-environment.sh
curl -sk -X POST -u "$AAP_CONTROLLER_USERNAME:$AAP_CONTROLLER_PASSWORD" \
  "$AAP_HOSTNAME/api/controller/v2/projects/20/update/"
```

Without this, JTs continue running the old playbook version.

### Workflow artifact threading via `set_stats`

Workflow nodes pass data between each other using `set_stats` (Ansible's
artifact publishing mechanism), not extra_vars injection:

- **EDA rulebook** fires `run_workflow_template` with `extra_vars:
  {affected_host, reported_cve, host_fqdn, incident_number, incident_sys_id}`
  from the event payload.
- **`patch_rhel.yml`** (Satellite branch) defaults `advisory_id` to
  `reported_cve` — no intermediate step needed to publish it.
- Each downstream node automatically receives all previously-published
  `set_stats` artifacts plus the workflow-level extra_vars.

The workflow must have **`ask_variables_on_launch: true`** so the event's vars
propagate into the first node.

**`advisory_id` vs `reported_cve`**: The EDA event publishes `reported_cve`.
Previously `insights_fetch_remediation.yml` re-published it as `advisory_id`
via `set_stats`. On the Satellite branch that step is removed; `patch_rhel.yml`
now defaults `advisory_id: "{{ reported_cve | default('') }}"` so it resolves
directly from the EDA event extra_vars.

### SNow CVE Remediation workflow (feature/satellite branch)

The node chain is simplified — `insights_fetch_remediation` removed because
`advisory_id` comes directly from the EDA event:

```
link_ci (SNow Relate CMDB CI to Incident)
  └── patch_host (Patch RHEL)
        ├── [success] close_incident (SNow Close Incident)
        └── [failure] update_inc_failure (SNow Update Incident)
```

### EDA event stream test_mode

The EDA event stream has a **test_mode** flag (set via the "Test" button in the
AAP UI). When `test_mode: true`, events are received and stored in the stream's
`test_content` field but **NOT forwarded** to rulebook activations — EDA never
triggers. This is a common cause of "EDA isn't firing" issues.

Check and disable via API:
```bash
curl -sk "$BASE/api/eda/v1/event-streams/1/" | python3 -c "import sys,json; print(json.load(sys.stdin).get('test_mode'))"
curl -sk -X PATCH -H "Content-Type: application/json" -d '{"test_mode":false}' "$BASE/api/eda/v1/event-streams/1/"
```

### Satellite API integration gotchas (feature/satellite branch)

Confirmed working patterns from `patch_rhel.yml` and `satellite_demo_reset.yml`:

**Built-in Satellite 6 credential type has NO injectors** — `injectors: {}`.
It cannot supply env vars to playbooks. Use a custom credential type instead:
```yaml
- name: "Lightspeed Patching - Satellite API"
  credential_type: "Lightspeed Patching - Satellite API"   # custom type
  inputs: { satellite_url, satellite_username, satellite_password, satellite_org }
  # injectors: SATELLITE_URL, SATELLITE_USERNAME, SATELLITE_PASSWORD, SATELLITE_ORG
```

**`delegate_to: localhost` inherits `become: true`** — EE containers have no
`sudo`. Add `become: false` to every `delegate_to: localhost` task in a play
that has `become: true` at the play level, or all API tasks fail with
`sudo: command not found`.

**Satellite promote API returns 202, not 200** — the Katello promote endpoint
is async. The task ID is in the 202 body. Add `status_code: [200, 202]` to the
`uri` task and poll `/foreman_tasks/api/tasks/{id}` until `state: stopped`.

**Correct errata endpoint for CV version check**:
- ✅ `GET /katello/api/errata?content_view_version_id={id}&search=cve={cve}&per_page=1`
- ❌ `GET /katello/api/content_view_versions/{id}/errata` — **404, does not exist**

**CV version ordering matters for the demo**: the "broken" (filtered) version
must have a LOWER version number than the "good" (unfiltered) version so
`patch_rhel.yml`'s "get latest CV version" query finds the good one.

## Conventions for editing CaC

- **Idempotent, additive (but not subtractive)** — re-running `load.yml` is
  safe; it creates or updates objects but **never deletes** them. This means
  orphaned nodes (e.g. workflow nodes removed from `files/` but still in AAP)
  survive across re-runs. **Critical gotcha**: when you remove a node from
  `simplified_workflow_nodes`, CaC removes its *edges* (no other node references
  it as a success/failure target) but the node object itself stays. An orphaned
  node with no predecessors becomes a **root node** — it fires automatically at
  workflow start, in parallel with the real first step. Delete it explicitly:
  ```bash
  curl -sk -X DELETE -u "$U:$P" "$BASE/api/controller/v2/workflow_job_template_nodes/{id}/"
  ```
  Find orphaned nodes: check which node IDs have no predecessors in the workflow
  node list (`/api/controller/v2/workflow_job_templates/{id}/workflow_nodes/`).
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

## EDA activation `test_mode` — post-load gotcha (verified 2026-06-15)

The `infra.aap_configuration` EDA rulebook activation role does **not** support
a `test_mode` parameter. Every `load.yml` run that touches an activation resets
the event stream's `test_mode` to `true` (the EDA default). In test_mode, events
arrive at the stream but are **not forwarded** to the rulebook — the activation
appears healthy but rules never fire.

**Symptom:** Business Rule posts HTTP 200, event stream `events_received` count
ticks up, but no JTs or workflows launch.

**Fix — run immediately after every `load.yml` that touches an EDA activation:**

```bash
source docs/dev-environment.sh
# Replace <stream-id> with the numeric ID of the event stream
# (visible in AAP → Automation Decisions → Event Streams → Details)
curl -sk -u "$AAP_CONTROLLER_USERNAME:$AAP_CONTROLLER_PASSWORD" \
  -X PATCH "$AAP_HOSTNAME/api/eda/v1/event-streams/<stream-id>/" \
  -H "Content-Type: application/json" \
  -d '{"test_mode": false}'
```

Stream IDs for this deployment:
- `1` — "Lightspeed Patching - ServiceNow Event Stream"
- `2` — "Lightspeed Patching - Insights Event Stream"

**Verify:**
```bash
curl -sk -u "$AAP_CONTROLLER_USERNAME:$AAP_CONTROLLER_PASSWORD" \
  "$AAP_HOSTNAME/api/eda/v1/activations/<activation-id>/" \
  | python3 -c "import sys,json; j=json.load(sys.stdin); s=j.get('event_streams',[]); print('test_mode:', s[0].get('test_mode') if s else '?')"
```

`test_mode: False` = events are forwarded to the rulebook.

## `jt_snow_relate_cmdb` credential requirement

`playbooks/servicenow/relate_cmdb_to_incident.yml` queries the Insights
inventory API to resolve the host's UUID — it needs `cred_insights_api` in
addition to `cred_servicenow`. Missing `cred_insights_api` shows as a censored
`no_log` failure on the Insights bearer token task (the JT fails silently with
no clear error message). Both credentials are now in the CaC definition.
