---
name: lightspeed
description: >-
  Red Hat Insights / Lightspeed API integration for aap.lightspeed.patching —
  OAuth2 service-account auth, Insights inventory and vulnerability API calls,
  the CVE→Insights→CMDB→incident linking pattern, insights-client hostname
  requirements, and the console.redhat.com RBAC roles needed. TRIGGER when the
  user mentions Insights API, console.redhat.com API calls, Insights inventory,
  Insights UUID, CVE lookup, vulnerability API, insights-client, display-name,
  service account roles on HCC, or the relate_cmdb_to_incident playbook.
  SKIP for pure EDA/rulebook wiring (use aap-config) and pure ServiceNow ITSM
  logic (use servicenow).
---

# Red Hat Insights / Lightspeed API — aap.lightspeed.patching

Reference for all direct API calls to `console.redhat.com` — auth, endpoints,
RBAC, and the playbook that links Insights data to ServiceNow.

## Authentication — OAuth2 client_credentials

All Insights API calls use a **service account** (client ID + secret) exchanged
for a short-lived bearer token via Red Hat SSO:

```
POST https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded
Body: grant_type=client_credentials&client_id=<id>&client_secret=<secret>
```

Response: `{"access_token": "...", "expires_in": 900, ...}`

**In playbooks** (see `relate_cmdb_to_incident.yml`):
```yaml
- name: Obtain Insights bearer token
  ansible.builtin.uri:
    url: "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
    method: POST
    body_format: form-urlencoded
    body:
      grant_type: client_credentials
      client_id: "{{ lookup('ansible.builtin.env', 'INSIGHTS_CLIENT_ID') }}"
      client_secret: "{{ lookup('ansible.builtin.env', 'INSIGHTS_CLIENT_SECRET') }}"
    status_code: 200
  register: insights_token_resp
  no_log: true
```

## Env vars

| Var | Purpose |
|-----|---------|
| `INSIGHTS_BASE_URL` | Base URL (default `https://console.redhat.com`) |
| `INSIGHTS_CLIENT_ID` | Service account client ID |
| `INSIGHTS_CLIENT_SECRET` | Service account client secret |

These are currently set to the **same credentials** as
`REDHAT_SUBSCRIPTIONS_CLIENT_ID` / `REDHAT_SUBSCRIPTIONS_CLIENT_SECRET` — one
service account serves both Automation Analytics uploads and direct Insights API
calls. Group vars bindings: `insights_client_id`, `insights_client_secret`,
`insights_base_url` in `aap_config/group_vars/all.yml`.

## console.redhat.com RBAC roles required

Service accounts cannot be added to the default access group. Create a **custom
User Access group** (Settings → User Access → Groups) and assign:

| Role | Permission | Why |
|------|-----------|-----|
| **Inventory Hosts Viewer** | `inventory:hosts:read` | Look up registered hosts by display_name |
| **Vulnerability Viewer** | `vulnerability:*:read` | Query CVEs affecting a system |

Add the service account to the group on the **Service Accounts** tab.

## Insights API endpoints used

### Inventory — look up a host by display_name

```
GET https://console.redhat.com/api/inventory/v1/hosts?display_name=<fqdn>
Authorization: Bearer <access_token>
```

Response: `{"total": 1, "results": [{"id": "<uuid>", "display_name": "...", ...}]}`

- `results[0].id` is the **Insights system UUID** used in all other API calls.
- Returns `total: 0` if the host is not registered — run "Register Insights" JT first.

### Two different "Insights UUIDs" — don't confuse them

There are two UUIDs and they answer different questions:

| UUID | Where | What it is |
|------|-------|-----------|
| **`insights_id`** (machine-id) | on the host: `sudo cat /etc/insights-client/machine-id` | The client's own identity, written at registration. Also exposed as `insights_id` on the inventory record. |
| **inventory record `id`** | API: `results[0].id` from the inventory lookup above | The Insights **inventory** UUID; this is the one the vulnerability/system endpoints take in their path. |

When someone asks for "the Insights UUID" of a provisioned host, the quickest answer is the on-host `insights_id`:

```bash
sudo cat /etc/insights-client/machine-id    # e.g. 1ad8a893-4c28-44d9-87f0-c3a91570fc83
sudo insights-client --status               # confirms registration ("Insights API confirms registration")
```

Notes:
- On EC2 RHEL the `insights_id` often **equals the RHSM system identity**
  (`sudo subscription-manager identity`) — they were the same value on the
  provisioned demo host, which can be mistaken for a coincidence but is normal.
- If you specifically need the inventory record `id` (the one API calls take),
  resolve it from the `insights_id` or the host FQDN via the inventory lookup —
  `GET /api/inventory/v1/hosts?insights_id=<machine-id>` or `?display_name=<fqdn>`.

### Vulnerability — CVEs affecting a specific system

```
GET https://console.redhat.com/api/vulnerability/v1/systems/<uuid>/cves
Authorization: Bearer <access_token>
```

Optional query params:
- `?cve_name=CVE-2025-38352` — filter to a specific CVE
- `?remediation=2` — only CVEs with an Ansible remediation playbook available

## Hostname requirement — always use the public FQDN

**Always pass `--display-name={{ inventory_hostname }}` when registering with
`insights-client`.** The EC2 OS hostname is the private DNS name
(`ip-10-50-0-x.ec2.internal`); without `--display-name`, Insights registers
under the private name, which won't match the AAP inventory hostname or the
CMDB CI name.

`playbooks/register_insights.yml` already implements this:
```yaml
- name: Register with Insights (display-name set to public FQDN)
  ansible.builtin.command:
    cmd: "insights-client --register --display-name={{ inventory_hostname }}"
```

**Any new task that calls `insights-client` must include `--display-name={{ inventory_hostname }}`.**

## CVE → CMDB → Incident linking pattern

`playbooks/servicenow/relate_cmdb_to_incident.yml` — scoped to a single
provisioned host:

1. Exchange service-account creds → Insights bearer token
2. `GET /api/inventory/v1/hosts?display_name=<host_fqdn>` → Insights UUID
3. `servicenow.itsm.api_info` on `cmdb_ci_linux_server` by FQDN → CI sys_id
4. `servicenow.itsm.api` PATCH incident `cmdb_ci` field → links the CI
5. Append work note with Insights UUID + CI details

**Inputs** (via survey or extra_vars):

| Var | Example | Required |
|-----|---------|----------|
| `incident_number` | `INC0011410` | yes |
| `host_fqdn` | `ec2-98-83-144-2.compute-1.amazonaws.com` | yes |
| `cve_id` | `CVE-2025-38352` | no (informational) |

**AAP JT**: `Lightspeed Patching - SNow Relate CMDB CI to Incident`
(CaC var: `jt_snow_relate_cmdb`). Uses the ServiceNow credential only — Insights
creds come from env vars injected via a credential type (future) or extra_vars.

## Insights UUID → CMDB correlation_id

The Insights `machine-id` (from `/etc/insights-client/machine-id` on the host)
is stamped into the CMDB CI's `correlation_id` by
`playbooks/servicenow/update_cmdb_correlation_id.yml` (CaC var:
`jt_snow_correlation_id`), so the CI durably links back to its Insights record —
not just into the incident work note. The playbook reads the UUID via SSH
(slurp), so it needs the Linux Machine credential but **not** the Insights API
credentials. It runs in the Provision-and-Onboard workflow after Register RHEL
(parallel to Patch RHEL, terminal leaf).

> The host's OS hostname is set to the public FQDN (`inventory_hostname`) in
> `register_rhel.yml` **before** registration, so the Insights display-name, the
> canonical `fqdn` fact, the AAP inventory name, and the CMDB CI name all agree.

## Key files

| File | Purpose |
|------|---------|
| `playbooks/register_insights.yml` | Installs insights-client, registers with `--display-name` |
| `playbooks/servicenow/relate_cmdb_to_incident.yml` | OAuth2 → inventory lookup → CMDB → incident cmdb_ci |
| `playbooks/servicenow/update_cmdb_correlation_id.yml` | SSH → read machine-id → CMDB CI `correlation_id` |
| `aap_config/group_vars/all.yml` | `insights_client_id`, `insights_client_secret`, `insights_base_url` |
| `aap_config/files/controller_job_templates.yml` | `jt_snow_relate_cmdb` JT definition |
| `docs/dev-environment.sh` | `INSIGHTS_CLIENT_ID`, `INSIGHTS_CLIENT_SECRET` (gitignored) |
| `docs/dev-environment.sh.example` | Template with blank Insights vars |

## Gotchas

- **`no_log: true` on the token task** — the client secret is in the request body;
  suppress logging or it appears in AAP job output.
- **Bearer token expires in ~15 minutes** — don't store it across plays; mint a
  fresh one per playbook run.
- **`display_name` filter is case-sensitive and exact-match** — pass the FQDN
  exactly as registered. An EC2 hostname is always lowercase.
- **Host not found (total: 0)** — the host hasn't been registered with Insights
  yet, or was registered under a different display_name (private hostname). Check
  console.redhat.com → Inventory → Systems.
