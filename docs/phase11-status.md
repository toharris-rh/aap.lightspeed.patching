# Phase 11 Status -- Auditable Automated CVE Remediation

**As of:** 2026-06-15
**Tracking issue:** [#84](https://github.com/toharris-rh/aap.lightspeed.patching/issues/84)
**Owners:** Eric Ames (ServiceNow patterns, CaC, EDA), Tony Harris (repo owner, Insights payload, CVE playbook)

---

## What we built

A fully automated pipeline that detects a CVE on a RHEL host, fires an EDA
event, creates a ServiceNow Incident with audit artifacts, and leaves a
verifiable trail -- with zero human ITSM interaction.

```
Introduce CVE (downgrade package)
  --> insights-client upload --> Insights detects CVE (~1 min)
  --> self-POST event to EDA event stream (workaround for daily sweep)
  --> rulebook matches application=vulnerability + new-cve-*
  --> workflow "Automated CVE Remediation" launches
        |
        +--> Fetch Insights Remediation
        |      Query Insights vulnerability API
        |      Confirm remediation==2 (automated fix exists)
        |      Create named Insights remediation plan
        |      Download remediation playbook YAML
        |
        +--> Create CVE Incident (on success)
               Create ServiceNow INC with cmdb_ci linked at creation
               Attempt task_ci (Affected CIs) link -- best-effort
               Post remediation playbook YAML as work note
               Post summary work note with CVE/CVSS/host/UUID metadata
```

**Validated end-to-end:** INC0011424 created with CI linked + remediation
playbook work note. Demo host: ec2-54-226-151-29.compute-1.amazonaws.com.

---

## What we shipped (PRs merged to main)

| PR | What it did |
|----|-------------|
| #85 | Slice 1: native Insights-->EDA event stream + Token credential + rulebook |
| #86 | Refresh Insights after patching so baseline reads clean |
| #87 | Demo talk track + Mermaid architecture diagram |
| #88 | ansible-lint name[template] fixes (unblocked all PRs) |
| #89 | Slice 2: `insights_fetch_remediation.yml` -- UUID --> CVE check --> create plan --> download playbook |
| #90 | Slice 3: `create_cve_incident.yml` -- INC + cmdb_ci + task_ci + playbook work note |
| #92 | Self-POST: introduce_cve.yml fires the event immediately (issue #91) |
| #93 | Fix CVSS field: real field is cvss3_score, not cvss_score |
| #95 | CMDB correlation_id = Insights inventory UUID (not machine-id) |
| #99 | Wire rulebook activation + Automated CVE Remediation workflow |
| #101 | Custom Insights API credential type (kind=cloud, fixes #78) |
| #104 | Remediation plan idempotency -- reuse existing plan on re-run |
| #106 | task_ci (Affected CIs) link best-effort -- tolerate 403 |
| #108 | snow_log role symlink for playbooks/servicenow/ resolution |

---

## Key discoveries and gotchas

### Insights notification sweep is daily, not real-time

Insights **detects** CVEs on upload (~1 min) but only **emits** the `new-cve-*`
webhook notification on a server-side **daily sweep** (~03:30 UTC). There is
no customer API to trigger it on demand. Inventory delete/re-register resets
the per-system "new CVE" baseline, so the sweep may never fire for a staged
demo.

**Workaround:** `introduce_cve.yml` polls the vulnerability API and self-POSTs
the event directly to the EDA event stream. In production, the native sweep is
fine (fires daily). For demos, the self-POST gives instant triggering.

### Built-in Insights credential can't attach to JTs

The built-in `Insights` credential type (kind=`insights`) only works on
inventories and projects -- the controller refuses to attach it to a job
template (*"Cannot assign a Credential of kind insights"*). We created a
custom `Lightspeed Patching - Insights API` credential type (kind=`cloud`)
that injects `INSIGHTS_CLIENT_ID/SECRET/BASE_URL` as env vars. The built-in
type is kept for the future `scm_type: insights` project (Slice 5).

### task_ci (Affected CIs) is ACL-blocked on some ServiceNow instances

The `task_ci` junction table insert returns 403 on our shared instance.
The primary `cmdb_ci` link (set at incident creation) is sufficient for audit.
The task_ci attempt is best-effort (`failed_when: false`).

### Remediation plan names must be unique per org

The Insights Remediations API returns `400 SequelizeUniqueConstraintError` on
duplicate plan names. Our playbook tolerates that 400 and looks up the existing
plan by name, making the demo repeatable.

### Vulnerability API has no CVE name filter

`systems/{uuid}/cves` doesn't support `?cve_name=`. We list up to 100 CVEs and
match client-side. A host with >100 CVEs would need pagination.

### Event envelope is flat

Confirmed: `event.payload.application`, not `event.payload.data.application`.
The rulebook conditions and self-POST payload use the flat structure.

### CMDB correlation_id is the inventory UUID

Changed from the on-host machine-id to the Insights inventory UUID so incoming
EDA events (which carry `context.inventory_id`) join directly to the CI.

### Project sync after merge

`scm_update_on_launch` is OFF (saves ~25s per workflow node). After merging
playbook changes, manually sync the controller project or the JTs run stale
code.

---

## Open gap

**Introduce CVE JT self-POST from AAP doesn't work yet.** The JT has
`cred_linux` + `cred_insights_api`, but neither injects
`INSIGHTS_EDA_EVENT_STREAM_URL` or `X-Insight-Token`. Works from a local shell
(where `dev-environment.sh` sets both). Fix = a small custom credential type
injecting those two env vars, attached to the JT.

---

## What's next -- Slices 4-7

| Slice | What | Notes |
|-------|------|-------|
| 4 | **Standard Change from template** | `sn_chg_rest` or `std_change_record_producer` from "Ames - AAP Daily Demo" template (Control01). Link INC<-->CHG via `incident.rfc`. |
| 5 | **Run the Insights remediation playbook** | Dedicated AAP Insights project (`scm_type: insights`) syncs the saved plan. JT runs it against the host. |
| 6 | **Proof of fix + close-out** | Re-run `insights-client`, confirm CVE cleared, post evidence to CHG/INC, close both. |
| 7 | **Auditor report + docs** | ServiceNow `sys_report` for Control01 evidence. Finalize skills/CHANGELOG. |

---

## Discussion topics for the meeting

1. **Slice 4 approach:** Standard Change from template -- do we use the
   `sn_chg_rest` module or the `std_change_record_producer` API? The template
   "Ames - AAP Daily Demo" / "Control01" exists on the instance.

2. **Slice 5 approach:** AAP Insights project mount (`scm_type: insights`)
   vs. committing the downloaded playbook to a git project. The native mount
   is cleaner (no git glue), but we need to confirm it works with the service
   account + remediation plan we create.

3. **The self-POST credential gap:** small custom cred type for
   `INSIGHTS_EDA_EVENT_STREAM_URL` + `INSIGHTS_EDA_TOKEN`, or extend the
   existing Insights API credential type with those fields?

4. **Demo timeline:** The talk track (docs/cve-remediation-talk-track.md)
   targets 8-12 minutes. Beats 1-4 work today. Beats 5-6 (fix + proof +
   auditor view) need Slices 4-6.

5. **Forwarding toggle:** Currently manual (must flip ON before demo). Should
   we default it to ON and just accept that staging a CVE triggers the
   workflow?

6. **Division of work on remaining slices** -- who takes what?

---

## Environment quick reference

- **Run load.yml** from `~/.venvs/lsp` (Python 3.13 + ansible-core 2.18;
  laptop Python 3.14 breaks it)
- **Sync the controller project** after merging playbook changes:
  `POST /api/controller/v2/projects/20/update/`
- **Trigger an event:** POST the vuln payload to the event stream URL with
  header `X-Insight-Token` (= `EDA_EVENT_STREAM_TOKEN` from dev-environment.sh)
- **Secrets:** `docs/dev-environment.sh` (gitignored)
