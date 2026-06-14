# ServiceNow Integration — aap.lightspeed.patching

## Architecture

```
Red Hat Insights/Lightspeed
  identifies CVE/advisory for registered RHEL hosts
    │
    ▼
Insights webhook → EDA Event Stream (bearer token auth)
  → Rulebook: rulebooks/lightspeed_events.yml
  → matches on advisory_type=Security, severity in [Critical, Important]
    │
    ▼
AAP Workflow: Lightspeed Patching - Instantaneous Patch
  │
  ├── [parallel] playbooks/servicenow/create_change_request.yml
  │     → CHG created (state: New)
  │     → publishes change_request_number, change_request_sys_id
  │
  ├── [parallel] playbooks/servicenow/notice_patch_started.yml
  │     → CHG → Implement state
  │     → work note: "Patching started, live AAP link"
  │
  ├── playbooks/patch_rhel.yml  (main patch play)
  │     → patches affected RHEL hosts
  │     → snow_log role → real-time work note per host
  │
  ├── [success path]
  │     playbooks/servicenow/update_change_request.yml  (patch_outcome=success)
  │       → CHG → Closed Complete
  │     playbooks/servicenow/update_cmdb_patch_status.yml
  │       → cmdb_ci_linux_server CIs updated with install_date
  │
  └── [failure path]
        playbooks/servicenow/create_incident.yml
          → INC created, incident number published
        playbooks/servicenow/update_change_request.yml  (patch_outcome=failure)
          → CHG → Cancelled, INC number cited
```

---

## Key Files

| File | Purpose |
|------|---------|
| `rulebooks/lightspeed_events.yml` | EDA rulebook — matches advisory events, launches workflow |
| `servicenow/README.md` | SNow-side setup guide |
| `playbooks/servicenow/create_change_request.yml` | Create CHG when advisory identified |
| `playbooks/servicenow/notice_patch_started.yml` | Transition CHG to Implement + live AAP link |
| `playbooks/servicenow/update_change_request.yml` | Close CHG (success) or Cancel (failure) |
| `playbooks/servicenow/register_cmdb_and_relate.yml` | Register host CI in CMDB, relate to Business App, link to RITM |
| `playbooks/servicenow/update_cmdb_patch_status.yml` | Update CI last patched date in CMDB |
| `playbooks/servicenow/create_incident.yml` | Open INC on patch failure |
| `playbooks/roles/snow_log/` | Role for real-time per-host work notes during patching |
| `aap_config/files/eda_credentials.yml` | EDA credentials (CaC) |
| `aap_config/files/eda_event_streams.yml` | EDA event stream definition |
| `aap_config/files/eda_rulebook_activations.yml` | Rulebook activation + extra_vars |
| `aap_config/group_vars/all.yml` | Severity filters, SNow defaults |
| `docs/dev-environment.sh.example` | Credential template (never commit the real file) |

---

## Credentials

| Env var | Purpose |
|---------|---------|
| `SN_HOST` | ServiceNow instance URL (`https://….service-now.com`) |
| `SN_USERNAME` | ServiceNow API user (needs `itil` + `rest_api_explorer` roles) |
| `SN_PASSWORD` | ServiceNow API password |
| `CONTROLLER_HOST` | AAP Controller URL (for live job links in work notes) |
| `EDA_EVENT_STREAM_TOKEN` | Bearer token for Insights→EDA webhook (matched pair) |

All are in `docs/dev-environment.sh` (gitignored). Template: `docs/dev-environment.sh.example`.

---

## Guardrails

- **Never print `SN_PASSWORD` or `EDA_EVENT_STREAM_TOKEN`** — check by name:
  `printenv SN_PASSWORD >/dev/null && echo set`
- **The bearer token is a matched pair** — same value in AAP EDA event-stream
  credential and Red Hat Insights webhook Authorization header.
  Generate: `openssl rand -hex 32`
- **CMDB lookups by FQDN** — `update_cmdb_patch_status.yml` queries by
  `fqdn STARTS WITH` then falls back to `name STARTS WITH`. Ensure RHEL hosts
  have matching FQDNs in CMDB before enabling CMDB updates.

---

## Rotate the Bearer Token

1. Generate: `openssl rand -hex 32`
2. Update AAP: `Lightspeed Patching - Insights Event Stream` credential → Token → paste
3. Update Red Hat Insights: Settings → Integrations → your webhook → Authorization header → paste
4. Test: trigger a test advisory event → verify EDA fires

---

## Module Patterns

- **`servicenow.itsm.api`** — generic Table API (POST/PATCH). Used for Change
  Requests and CMDB updates.
- **`servicenow.itsm.api_info`** — read-only query. Used for CI lookups.
- **`servicenow.itsm.incident`** — specialized incident create.

All consume `SN_*` env vars from the `Lightspeed Patching - ServiceNow`
credential (ServiceNow ITSM Credential type) automatically.
