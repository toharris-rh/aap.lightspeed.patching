# ServiceNow Setup Guide — aap.lightspeed.patching

This guide covers the ServiceNow-side configuration required for the
ITSM status sync integration.

---

## Overview

AAP calls back to ServiceNow at each stage of the patch workflow:

```
Red Hat Insights advisory event
  → EDA rulebook (lightspeed_events.yml)
  → AAP Workflow: Lightspeed Patching - Instantaneous Patch
      ├── [parallel] create_change_request.yml  → CHG created
      ├── [parallel] notice_patch_started.yml   → CHG → Implement
      ├── patch RHEL hosts (main patch play)
      │     └── snow_log role → real-time work notes per host
      └── [on success] update_change_request.yml → CHG closed
          [on success] update_cmdb_patch_status.yml → CI patched date updated
          [on failure] create_incident.yml → INC opened
          [on failure] update_change_request.yml → CHG cancelled
```

---

## Prerequisites

- ServiceNow instance with the **ITSM** plugin
- Service account with roles: `itil`, `rest_api_explorer`, `admin` (for REST Message config)
- `servicenow.itsm` Ansible collection installed (see `collections/requirements.yml`)

---

## Credentials

Set these as environment variables (never commit values):

```bash
export SN_HOST="https://your-instance.service-now.com"
export SN_USERNAME="your-service-account"
export SN_PASSWORD="your-password"
```

In AAP: create a **ServiceNow ITSM Credential** named
`Lightspeed Patching - ServiceNow` and attach it to all ServiceNow job templates.

---

## Guardrails (same as dc1.azure — read before making any changes)

- **Never print `SN_PASSWORD`** — check by name only:
  `printenv SN_PASSWORD >/dev/null && echo set`
- **Confirm `SN_HOST`** before any mutation — scope all writes by `sys_id`.
- **The bearer token is a matched pair** — same value in both the AAP EDA
  event-stream credential and the Red Hat Insights webhook configuration.
  Generate: `openssl rand -hex 32`.

---

## Change Request states used

| Integer | State label | When set |
|---------|-------------|----------|
| `-1` | New | `create_change_request.yml` |
| `1` | Implement | `notice_patch_started.yml` |
| `3` | Closed | `update_change_request.yml` (success) |
| `4` | Cancelled | `update_change_request.yml` (failure) |

> **Note:** State integers vary by ServiceNow instance. Validate against your
> instance before running. Override via JT extra_vars if needed.

---

## CMDB CI class

All patched RHEL hosts are expected to be registered as
`cmdb_ci_linux_server` CIs. The `update_cmdb_patch_status.yml` playbook
looks up CIs by FQDN and updates `install_date` (last patched date).

---

## Red Hat Insights webhook configuration

1. In [Red Hat Hybrid Cloud Console](https://console.redhat.com) → **Settings → Integrations**
2. Add a **Webhook** integration pointing to your AAP EDA event stream URL
3. Set the **Authorization header** to `Bearer <your EDA_EVENT_STREAM_TOKEN>`
4. Enable advisory events: **Security advisories** (Critical, Important)

The EDA event stream URL is displayed in AAP → **Automation Decisions → Event Streams**
after creating `Lightspeed Patching - Insights Event Stream`.

---

## Testing the integration locally

```bash
source docs/dev-environment.sh

# Verify SNow credentials
printenv SN_HOST SN_USERNAME && printenv SN_PASSWORD >/dev/null && echo "Password: set"

# Create a test change request
ansible-playbook playbooks/servicenow/create_change_request.yml \
  -e advisory_id="RHSA-2025:TEST" \
  -e advisory_severity="Critical" \
  -e "affected_hosts=host1.example.com,host2.example.com"
```
