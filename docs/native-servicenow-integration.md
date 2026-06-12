# Native Red Hat Insights → ServiceNow Integration (as-built)

This documents the **native** integration path: Red Hat Insights / Lightspeed
sends events **directly** into ServiceNow via the certified
[*Flow Templates for Red Hat Insights*](https://store.servicenow.com/store/app/0ddea32e1b646a50a85b16db234bcb58)
ServiceNow app — **no AAP/EDA in the middle**.

> This is distinct from the **EDA path** in
> [`docs/servicenow-integration.md`](servicenow-integration.md), where Insights
> events flow through AAP EDA and ServiceNow is written by playbooks. The two
> can coexist. Pick the path that matches what you're demoing.

```
Red Hat Insights / Lightspeed (per SE's own org)
  → console.redhat.com "ServiceNow" integration (Endpoint URL + Secret token)
  → ServiceNow scripted REST endpoint (Flow Templates for Red Hat Insights app)
  → ServiceNow records (incidents / flows)
```

---

## What is already in place (instance-wide)

Done once per ServiceNow instance — verified 2026-06-12:

| Item | State |
|------|-------|
| App: **Flow Templates for Red Hat Insights** (`x_rhtpp_rh_webhook` v1.0.9) | Installed & active |
| Roles provided by the app | `x_rhtpp_rh_webhook.rest` (integration), `x_rhtpp_rh_webhook.support` |
| REST endpoint | `…/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights` (POST-only) |

The instance hostname and API credentials live only in the gitignored
`docs/dev-environment.sh` (`SN_HOST`, `SN_USERNAME`, `SN_PASSWORD`).

### Per-SE integration users

Each SE gets their **own** ServiceNow integration user so secrets are
independently rotatable and inbound events are attributable. Created so far:

| ServiceNow user | Role |
|-----------------|------|
| `rh_insights_eames` | `x_rhtpp_rh_webhook.rest` |
| `rh_insights_tharris` | `x_rhtpp_rh_webhook.rest` |

> A shared single user works technically but is discouraged — one rotation
> breaks everyone and events aren't attributable.

---

## ⚠️ Manual steps each SE must take

Two things **cannot** be automated from this repo and must be done by hand.

### 1. Set the integration user's password (ServiceNow UI)

`user_password` writes over the ServiceNow REST API are **silently ignored on
this instance** (the call returns HTTP 200 but the password is not set). So the
password must be set in the UI:

1. Sign in to `https://<instance>.service-now.com` as an admin.
2. **User Administration → Users** → open your user (e.g. `rh_insights_<handle>`).
3. Use the **Set Password** related link → set a strong password → save.
4. Ideally **you** (the SE who owns the account) set it, so the secret never
   passes through anyone else.

This password becomes the **Secret token** in the console wizard below.

### 2. Add the integration in your own Hybrid Cloud Console

Done in **each SE's own** `console.redhat.com` (your Red Hat org):

1. **Settings → Integrations → Add integration → ServiceNow**.
2. Fill in:

   | Field | Value |
   |-------|-------|
   | Integration name | e.g. `ServiceNow – Patching` |
   | Endpoint URL | `https://<instance>.service-now.com/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights` |
   | Secret token | the integration-user password you set in step 1 |

   (SSL verification stays enabled.)
3. **Associate event types** — select the advisory / vulnerability events you
   want pushed into ServiceNow.
4. **Review → Submit.**

### 3. Test

Trigger a test advisory event (or wait for a real one) and confirm a record
lands in ServiceNow.

---

## Adding a new SE later

The only automatable part is creating the user + assigning the role (run as an
admin account; creds from `docs/dev-environment.sh`). The role name is
`x_rhtpp_rh_webhook.rest`. After creating the user, that SE still does the two
manual steps above (set password in UI, add the console integration).

Create the user with `web_service_access_only=true` and
`internal_integration_user=true`, then grant `x_rhtpp_rh_webhook.rest`. See
`.claude/skills/servicenow/SKILL.md` ("Native HCC→ServiceNow integration —
as-built / how-to") for the exact REST pattern.

---

## ⚠️ Shared-instance caveat — no per-org isolation

This ServiceNow instance is shared by ~33 SEs. **All** SEs' events land in the
**same** ServiceNow tables; there is no automatic separation by Red Hat org.
The inbound payload carries the Red Hat org/account ID, so segregate with a
custom field, a per-SE assignment group, or a filter **before** this gets busy.

---

## Rollback / cleanup

- Remove an SE: delete their `rh_insights_<handle>` user (and its
  `sys_user_has_role` row) in ServiceNow, and delete the integration in that
  SE's console.
- Removing the app instance-wide affects everyone — coordinate first.
