---
name: lightspeed-snow-setup
description: >-
  Step-by-step guide for SEs configuring the native Red Hat Lightspeed /
  Insights → ServiceNow integration (Flow Templates for Red Hat Insights app,
  no AAP/EDA). Covers the shared-instance model, the one fixed integration
  user, the console.redhat.com wizard, and how to verify the connection.
  TRIGGER when the user asks how to set up or configure the Lightspeed /
  Insights → ServiceNow integration, connect Insights to ServiceNow, configure
  the Flow Templates app, add the ServiceNow integration in the console, or
  troubleshoot "Basic authentication failed for user: rh_insights_integration".
  SKIP for the EDA path (Insights → AAP EDA → ServiceNow via playbooks) — use
  the servicenow skill instead.
---

# Native Lightspeed / Insights → ServiceNow Integration Setup

This covers the **native** path: Red Hat Insights sends events **directly** into
ServiceNow via the *Flow Templates for Red Hat Insights* certified app — **no
AAP or EDA involved**.

```
console.redhat.com (each SE's own org)
  → "ServiceNow" integration (Endpoint URL + Secret token)
  → ServiceNow scripted REST endpoint (x_rhtpp_rh_webhook app)
  → ServiceNow incidents / flows
```

Full runbook: `docs/native-servicenow-integration.md`.

---

## ⚠️ Read this before you touch anything

**There is ONE integration user and ONE shared secret for the entire instance.**

The app hard-codes the ServiceNow username as `rh_insights_integration`. Every
SE's console integration authenticates as this same user. The "Secret token" in
the console wizard is simply **that user's password** — not a separate token.

Consequences:
- Every SE uses the **same Endpoint URL** and the **same Secret token**.
- You cannot give each SE a distinct user or secret.
- If anyone changes `rh_insights_integration`'s password without updating every
  SE's console integration, everyone breaks.

---

## What's already done (instance-wide, do not repeat)

Verified 2026-06-12:

| Item | Status |
|------|--------|
| **Flow Templates for Red Hat Insights** app (`x_rhtpp_rh_webhook` v1.0.9) | Installed and active |
| Integration user `rh_insights_integration` | Exists with role `x_rhtpp_rh_webhook.rest` |
| REST endpoint | `…/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights` (POST only) |

Do **not** reinstall the app or recreate the user — these are instance-wide and
affect all ~33 SEs.

---

## Steps for each SE (per-org, in the console)

### Step 1 — Get the shared Secret token

Ask whoever administers the shared ServiceNow instance for the
`rh_insights_integration` password. It is **not** in this repo.

> If it needs to be reset: a ServiceNow admin signs in → User Administration →
> Users → `rh_insights_integration` → **Set Password** related link. **Do not
> use the REST API to set it** — `user_password` writes via the Table API are
> silently ignored on this instance (returns 200 but has no effect).

### Step 2 — Add the integration in the console

In your own `console.redhat.com` org:

1. **Settings → Integrations → Red Hat Enterprise Linux → Add integration**
2. Select **ServiceNow**
3. Fill in:

| Field | Value |
|-------|-------|
| Integration name | e.g. `ServiceNow – Lightspeed Patching` |
| Endpoint URL | `https://<instance>.service-now.com/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights` |
| Secret token | The `rh_insights_integration` password from Step 1 |

4. **Associate event types** — select **Advisories** and/or **Vulnerabilities**
   depending on what you want to demo.
5. Leave SSL verification **enabled**.
6. **Review → Submit.**

### Step 3 — Test the connection

In the console integration list, hit **Test** next to your new integration.

**Success looks like:** Hybrid Cloud Console Event Log shows an
*Integration Test* event with **Action taken: Integration: ServiceNow** and a
green check mark.

![Successful integration test](../../../docs/images/native-servicenow-integration-test-success.png)

**A connectivity Test does NOT create an incident.** It is a ping the app
acknowledges with a 2xx; it persists nothing. Don't wait for a record to appear —
the green check in the console is the success signal. Real incidents only appear
for **real** Advisory/Vulnerability events on a registered host.

## Verifying from the ServiceNow side (admin / API)

A console green check means HCC got a 2xx back, but you can also confirm it
landed and authenticated from ServiceNow. Useful when a test "succeeds" in the
console but you want proof, or when debugging auth.

**Timezone:** the instance UI/`sys_created_on` render in **PDT (UTC−7)**. An HCC
test logged at `19:14 UTC` shows as `12:14` in ServiceNow — convert before you
go hunting.

1. **Inbound POST landed** — the real webhook request (filter on the app path,
   not `urlLIKE`, or you'll also match your own monitoring queries):
   ```
   GET /api/now/table/syslog_transaction
       ?sysparm_query=urlSTARTSWITH/api/x_rhtpp_rh_webhook^ORDERBYDESCsys_created_on
   ```
   A row at your test time = ServiceNow received it.
2. **Auth result** — search the system log:
   ```
   GET /api/now/table/sys_log?sysparm_query=messageLIKErh_insights_integration
   ```
   A `Basic authentication failed for user: rh_insights_integration` entry = wrong
   Secret token. **No such entry + console green = auth succeeded.**

What you will **not** see, and why it matters:
- **No request body is logged.** `syslog_transaction` does not store the POST
  body, and the app has **no tables of its own**. The Red Hat **org/account ID**
  travels in the body, so it is **not searchable** anywhere in ServiceNow after a
  test (searching `sys_log` / incidents / `ecc_queue` for an org id returns
  nothing).
- The inbound transaction shows **empty `user` and `client_ip`** even on success —
  normal for scripted-REST inbound; not a failure indicator.
- On a connectivity Test you **cannot tell one SE's test from another's** — every
  test is an identical bare POST.

### Real incidents: what a working event looks like (and the segregation gap)

A real Advisory/Vulnerability event **does** open an incident. Example
(`INC0011410`, verified 2026-06-13):

| Field | Value |
|-------|-------|
| `sys_created_by` | `rh_insights_integration` (every SE's events look the same) |
| `opened_by` / `caller_id` | `Red Hat Insights Integration` |
| `short_description` | `VULNERABILITY: Reported CVE-2025-38352` |
| `description` | `Account id:` *(empty!)*, `Event type:`, `CVSS score:`, `CVE url:`, … |

**The `Account id:` line in the incident description comes through EMPTY** — the
Red Hat org/account ID is **not populated even on real incidents**. So per-org
attribution by account ID is **not currently possible**, on tests *or* real
events. To tell SEs apart on the shared instance you must use an alternative:
- correlate by **CVE + affected host FQDN + timestamp**, or
- set a **distinct assignment group per SE** in each console integration's config
  (so each SE's incidents route to their own group).

(Minor quirk: description values are prefixed with a zero-width BOM char, e.g.
`Impact id: ﻿5` — harmless, but don't be surprised by it when parsing.)

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Basic authentication failed for user: rh_insights_integration` in the ServiceNow system log | Password mismatch — the Secret token in the console doesn't match the actual password | Admin resets via **Set Password** in the UI (not the REST API); redistribute the new password |
| Test fires but no record in ServiceNow | App installed but not active, or wrong Endpoint URL | Confirm app is active; check the URL path exactly — GET returns 405 (POST only) |
| Console test returns an error immediately | Wrong Endpoint URL or SSL issue | Double-check the instance hostname; confirm SSL cert is valid |
| Records land but can't distinguish SE orgs | All SEs share `rh_insights_integration`, and the incident `Account id:` field arrives empty — no org-id attribution | Correlate by CVE + host FQDN + timestamp, or set a distinct assignment group per SE in each console integration's config |

---

## Shared-instance caveat

This ServiceNow instance is shared by ~33 SEs. All events land in the **same**
`incident` table with no automatic per-org separation, and the incident's
`Account id:` field arrives **empty**, so you **cannot** segregate by Red Hat
org/account ID (see "Real incidents" above). Before live demos get busy,
distinguish your records by **CVE + host FQDN + timestamp**, or configure a
**per-SE assignment group** in your console integration.

Do **not** delete `rh_insights_integration` — it is the only account the app
accepts and deleting it breaks every SE's integration.
