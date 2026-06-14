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

Then confirm a corresponding record appears in ServiceNow.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Basic authentication failed for user: rh_insights_integration` in the ServiceNow system log | Password mismatch — the Secret token in the console doesn't match the actual password | Admin resets via **Set Password** in the UI (not the REST API); redistribute the new password |
| Test fires but no record in ServiceNow | App installed but not active, or wrong Endpoint URL | Confirm app is active; check the URL path exactly — GET returns 405 (POST only) |
| Console test returns an error immediately | Wrong Endpoint URL or SSL issue | Double-check the instance hostname; confirm SSL cert is valid |
| Records land but can't distinguish SE orgs | All SEs share `rh_insights_integration` — no automatic isolation | Filter by Red Hat org/account ID in the inbound payload; use a per-SE assignment group |

---

## Shared-instance caveat

This ServiceNow instance is shared by ~33 SEs. All events land in the **same**
tables with no automatic per-org separation. The inbound payload includes the
Red Hat org/account ID — use that to segregate records if needed before live
demos get busy.

Do **not** delete `rh_insights_integration` — it is the only account the app
accepts and deleting it breaks every SE's integration.
