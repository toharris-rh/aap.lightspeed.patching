# Demo Talk Track — Instantaneous Patching

**Audience:** SVP of Sales + peers  
**Date:** June 18, 2026 · 9:00 AM  
**Presenters:** Tony Harris, Eric Ames  
**Target runtime:** 10–12 minutes

---

## Pre-Flight Checklist (30 min before)

- [ ] APD environment running — AAP Controller accessible
- [ ] ServiceNow instance accessible — `rh_insights_tharris` user active
- [ ] EDA activation "Lightspeed Patching - Catch SNow Catalog Orders" is **Running** (green)
- [ ] EDA activation "Lightspeed Patching - Catch SNow Incidents" is **Running** (green)
- [ ] RHEL demo VM is running and registered with Insights
- [ ] Run `introduce_cve.yml` on the demo VM (downrev the package)
- [ ] Confirm the CVE INC has NOT yet been created in ServiceNow (reset state)
- [ ] Browser tabs open: ServiceNow, AAP, Red Hat Insights

---

## Opening (1 min) — The Problem

> "Every day, Red Hat publishes new security advisories for RHEL.
> The old way: your security team finds it, files a ticket, ops schedules a
> maintenance window, patches get applied days or weeks later.
> Every hour between detection and patch is exposure.
>
> What we're about to show you is instantaneous patching — from advisory
> detected to system patched, with a full audit trail in ServiceNow, zero
> human intervention."

---

## Act 1 — Order → Provision → Onboard (4–5 min)

### Step 1 · ServiceNow Catalog Order

> "Let's start from the customer's perspective. An engineer needs a new
> RHEL server. They go to the ServiceNow catalog — no Ansible expertise required."

- Open ServiceNow → Service Catalog → "Lightspeed Patching - Request RHEL VM"
- Select size: **medium**
- Click **Order Now**

> "That's it. No tickets to write, no ops team to ping."

### Step 2 · Watch AAP Fire

- Switch to AAP → Jobs
- Show the **Lightspeed Patching - Provision and Onboard** workflow launching

> "The ServiceNow catalog order fired a Business Rule that sent an event to
> Ansible's Event-Driven Ansible engine. EDA matched it and launched this workflow
> automatically."

### Step 3 · Watch ServiceNow Update in Real-Time

- Switch to ServiceNow → open the INC ticket

> "Notice the ServiceNow ticket is updating itself — in real-time, as each
> step completes. Provision VM started. RHEL registered to Red Hat CDN.
> Fully patched. Registered with Red Hat Insights.
> This is the snow_log role — task-level audit proof, posted by the automation
> itself, no human touch."

> "The new RHEL server is now visible to Red Hat Insights and being monitored
> for advisories."

---

## Act 2 — CVE Detected → Remediated (4–5 min)

### Step 4 · Insights Detects a Vulnerability

- Switch to console.redhat.com → Insights → Advisor

> "Red Hat Lightspeed and Insights are continuously scanning this host.
> We've intentionally installed a vulnerable version of [package] to simulate
> a CVE that was just published."

- Show the advisory in Insights (the downrev package)

> "Insights has already detected it. And because we have the native
> Insights → ServiceNow integration configured, watch what happens next."

### Step 5 · ServiceNow INC Created Automatically

- Switch to ServiceNow → Incidents
- Show the new INC created by Insights

> "ServiceNow just received an incident ticket from Red Hat Insights —
> automatically. No human filed that ticket."

### Step 6 · EDA Detects the INC and Fires

- Switch to AAP → Jobs
- Show **Lightspeed Patching - Remediate CVE** workflow launching

> "A ServiceNow Business Rule is watching the INC table. The moment that
> Insights-originated ticket appeared, it fired an event to EDA.
> EDA matched it and launched the remediation workflow — automatically."

### Step 7 · Watch the INC Update in Real-Time

- Switch to ServiceNow → open the INC ticket

> "Same real-time work note pattern. 'Remediation started. Package updated.
> Reboot complete. CVE resolved. Incident ready to close.'
> And now — the incident closes itself."

> "From advisory detected to system patched and ticket closed: fully automated.
> Zero human ITSM interaction. Complete audit trail."

---

## Closing (1–2 min) — What They Just Saw

> "What you just saw was:
>
> 1. **Self-service infrastructure** — engineers order what they need from
>    ServiceNow. No tickets to ops.
>
> 2. **Instant onboarding** — every new RHEL server is automatically registered
>    to Red Hat, fully patched, and enrolled in continuous monitoring.
>
> 3. **Instantaneous patching** — the moment Red Hat Lightspeed identifies a CVE,
>    it's patched. Not in the next maintenance window. Not after someone files a
>    ticket. Instantly.
>
> 4. **Full audit trail** — every step is documented in ServiceNow by the
>    automation itself, using the service.ansible account.
>
> This is what the Mythos era of patching looks like."

---

## Q&A Prep

| Question | Answer |
|----------|--------|
| How does it know which hosts to patch? | Insights identifies affected hosts by hostname. EDA passes them to AAP as the job limit. |
| What if the patch breaks something? | You can gate automatic patching on severity (Critical/Important auto-patch; Moderate goes to review queue). |
| What about change windows? | The workflow can create a Change Request in ServiceNow for approval-gated patching — not shown today but in the roadmap. |
| Is the ServiceNow integration supported by Red Hat? | Yes — the Flow Templates for Red Hat Insights app is fully supported by Red Hat. ServiceNow will not provide troubleshooting. |
| Can this work with Jira instead? | AAP can call any REST API. The pattern is the same — different EDA rulebook and callback playbooks. |
| Who supports this repo? | Tony Harris and Eric Ames. It's public on GitHub: github.com/toharris-rh/aap.lightspeed.patching |
