# snow_log — Real-Time ServiceNow Ticket Logging

## Executive Summary

The `snow_log` role gives any Ansible playbook the ability to post work notes
to a ServiceNow **Change Request** in real-time, as each host is patched.
Instead of waiting until the end of the workflow to summarize what happened,
every meaningful step — pre-patch snapshot, patch applied, reboot, verify —
writes its result directly to the CHG ticket the moment it finishes. Each host
posts its own note, giving auditors a per-host, timestamped record of exactly
what happened and when.

**Key capability:** task-level, per-host logging to any ServiceNow ticket type
(Change Request, Incident) from any playbook — with zero boilerplate.

### Why It Matters for Patching

| Before | After |
|--------|-------|
| One summary note posted at the end of the patch run | Individual notes posted as each host is patched |
| If a host failed mid-run, the CHG showed nothing until the end | Every step is recorded — failures are visible immediately |
| No audit trail for which host was patched when | Per-host, per-task notes with timestamps in the Change Record |
| Manual ITSM updates after patching | Fully automated — zero human ITSM interaction |

### Live Example (CHG record during a patch run)

```
09:12:03  host1.prod.example.com: Pre-patch snapshot complete. Kernel: 5.14.0-362.el9.x86_64
09:12:18  host2.prod.example.com: Pre-patch snapshot complete. Kernel: 5.14.0-362.el9.x86_64
09:13:41  host1.prod.example.com: RHSA-2025:1234 applied (23 packages updated).
09:14:02  host2.prod.example.com: RHSA-2025:1234 applied (23 packages updated).
09:15:17  host1.prod.example.com: Reboot complete. Kernel: 5.14.0-427.el9.x86_64
09:15:44  host2.prod.example.com: Reboot complete. Kernel: 5.14.0-427.el9.x86_64
09:16:01  host1.prod.example.com: Post-patch verify — all services healthy. CVE-2025-12345: FIXED
09:16:09  host2.prod.example.com: Post-patch verify — all services healthy. CVE-2025-12345: FIXED
```

Each note is posted by `AAP ServiceAccount` with a ServiceNow timestamp.
The change manager watching the CHG sees progress unfold in real-time.

---

## Usage

One `include_role` call with a message — works from any play targeting RHEL hosts:

```yaml
- name: Log patch result to ServiceNow
  ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: >-
      {{ inventory_hostname }}: {{ advisory_id }} applied
      ({{ updated_packages | default('n/a') }} packages updated).
```

### Defaults (override any of these)

| Variable | Default | Purpose |
|----------|---------|---------|
| `snow_log_message` | `""` | Text to post (required — empty = no-op) |
| `snow_log_resource` | `change_request` | SNow table (`incident`, `sc_req_item`, etc.) |
| `snow_log_field` | `work_notes` | `work_notes` (IT-internal) or `comments` (customer-visible) |
| `snow_log_ticket_number` | `{{ change_request_number }}` | Auto-inherited from workflow |
| `snow_log_ticket_sys_id` | `{{ change_request_sys_id }}` | Skips lookup when available |

### Log to an Incident instead

```yaml
- ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: "Patch failed on {{ inventory_hostname }}: {{ patch_error }}"
    snow_log_resource: incident
    snow_log_ticket_number: "{{ create_incident_number }}"
    snow_log_field: work_notes
```

---

## Design

### Guard pattern

The role no-ops when `change_request_number` (or `snow_log_ticket_number`) is
empty. Non-ServiceNow launches (AAP UI, manual runs, CI testing) produce zero
SNow calls and zero errors.

### Non-breaking

If ServiceNow is unreachable or returns an error, a `rescue` block logs the
failure as a debug message and the playbook continues. Audit logging never
interrupts the patch run.

### Per-host logging

The role does NOT use `run_once`. When a play targets multiple RHEL hosts,
each host posts its own work note with its specific hostname, package count,
and kernel version. This gives auditors a per-host record.

### Credential requirement

Any job template whose playbook calls `snow_log` must include the
`Lightspeed Patching - ServiceNow` credential in its credential list.
This injects `SN_HOST`, `SN_USERNAME`, `SN_PASSWORD` as environment
variables. The role delegates to localhost, so it works from plays targeting
remote RHEL hosts.

---

## Source Code

| File | Purpose |
|------|---------|
| [`playbooks/roles/snow_log/defaults/main.yml`](../playbooks/roles/snow_log/defaults/main.yml) | Role API — variables and defaults |
| [`playbooks/roles/snow_log/tasks/main.yml`](../playbooks/roles/snow_log/tasks/main.yml) | Guard → resolve sys_id → patch → rescue |
| [`playbooks/roles/snow_log/meta/main.yml`](../playbooks/roles/snow_log/meta/main.yml) | Galaxy metadata |

### Where snow_log is used in this repo

| Playbook | snow_log calls | Ticket type |
|----------|---------------|-------------|
| `playbooks/patch_rhel.yml` | pre-patch, patch applied, reboot, post-verify | Change Request |
| `playbooks/servicenow/create_incident.yml` | (n/a — incident created, not logged to) | — |
| `playbooks/servicenow/update_change_request.yml` | (n/a — final CHG close) | — |

---

## Related

- [ServiceNow Integration](servicenow-integration.md) — full SNow architecture
- [`servicenow/README.md`](../servicenow/README.md) — ServiceNow-side setup guide
- [`playbooks/servicenow/`](../playbooks/servicenow/) — callback playbooks
- Adapted from [`ericcames/dc1.azure`](https://github.com/ericcames/dc1.azure) `snow_log` role
