# Roadmap — aap.lightspeed.patching

> **Audience:** SVP of Sales + peers  
> **Demo deadline:** June 18, 2026 · 9:00 AM  
> **Public release:** June 23, 2026

---

## Owners

| Person | GitHub | Role |
|--------|--------|------|
| Tony Harris | @toharris-rh | Repo owner, Insights payload research, CVE playbook, AAP infra |
| Eric Ames | @ericcames | ServiceNow patterns, CaC, Business Rule, EDA integration |

---

## Two-Act Demo Flow

```
ACT 1 — Order → Provision → Onboard
  Customer orders RHEL VM from ServiceNow catalog
    └─► AAP provisions VM on AWS (Terraform)
    └─► RHEL registered to Red Hat CDN + fully patched
    └─► RHEL registered with Red Hat Insights
    └─► ServiceNow INC updated with status at each step (snow_log)

ACT 2 — CVE Detected → Remediate Instantly
  Tony's playbook introduces a known CVE (downrev a package)
    └─► Red Hat Insights detects advisory on registered host
    └─► Insights → ServiceNow INC created (native integration — already tested)
    └─► ServiceNow Business Rule fires → posts to AAP EDA event stream
    └─► EDA rulebook detects INC → launches remediation workflow
    └─► AAP patches the CVE on the affected host
    └─► ServiceNow INC updated in real-time per task (snow_log)
    └─► INC closed — fully automated, zero human ITSM interaction
```

---

## Phases

### Phase 1 — Environment Bootstrap (Due: Jun 13)

**Owner: Both**

| Task | Owner | Status |
|------|-------|--------|
| Order APD environment (Ansible Product Demo) | Tony | `[ ]` |
| Capture AAP credentials from APD into `docs/dev-environment.sh` | Tony | `[ ]` |
| Confirm RHDP AAP instance URL + admin creds reachable | Tony | `[ ]` |
| Confirm shared ServiceNow instance reachable + `rh_insights_tharris` user active | Tony | `[ ]` |
| Run `aap_config/load.yml` — bootstrap AAP object namespacing | Eric | `[ ]` |

---

### Phase 2 — AWS Linux VM Provisioning (Due: Jun 14)

**Owner: Tony** (infrastructure), **Eric** (CaC patterns review)

| Task | Owner | Status |
|------|-------|--------|
| Port Terraform from Azure to AWS (EC2 + VPC + SG + key pair) | Tony | `[ ]` |
| Implement 3 t-shirt sizes (small/medium/large → t3.medium/large/xlarge) | Tony | `[ ]` |
| Configure SSH key injection from `LINUX_SSH_PUBLIC_KEY` env var | Tony | `[ ]` |
| `playbooks/provision_vm_aws.yml` — Terraform wrapper playbook | Tony | `[ ]` |
| Verify EC2 instance launches and is SSHable | Tony | `[ ]` |
| S3 bucket for Terraform remote state created in default region | Tony | `[ ]` |

---

### Phase 3 — RHEL Onboarding (Due: Jun 14)

**Owner: Tony**

| Task | Owner | Status |
|------|-------|--------|
| `playbooks/register_rhel.yml` — register to Red Hat CDN via activation key | Tony | `[ ]` |
| `playbooks/patch_rhel.yml` — full patch run on new VM | Tony | `[ ]` |
| `playbooks/register_insights.yml` — install insights-client + register | Tony | `[ ]` |
| Verify host appears in console.redhat.com after registration | Tony | `[ ]` |
| Add RH_ORG_ID + RH_ACTIVATION_KEY to `docs/dev-environment.sh` | Tony | `[ ]` |

---

### Phase 4 — ServiceNow Catalog Item (Due: Jun 14)

**Owner: Eric**

| Task | Owner | Status |
|------|-------|--------|
| Create ServiceNow catalog item "Lightspeed Patching - Request RHEL VM" | Eric | `[ ]` |
| Add t-shirt size variable (small / medium / large) | Eric | `[ ]` |
| ServiceNow Business Rule: on catalog order → POST to EDA event stream | Eric | `[ ]` |
| EDA rulebook: `rulebooks/servicenow_events.yml` — catalog order → provision workflow | Eric | `[ ]` |
| Test end-to-end: SNow order → EDA fires → AAP workflow launches | Eric | `[ ]` |

---

### Phase 5 — Introduce CVE + Insights Detection (Due: Jun 15)

**Owner: Tony**

| Task | Owner | Status |
|------|-------|--------|
| Research Red Hat Insights advisory webhook payload structure | Tony | `[ ]` |
| `playbooks/introduce_cve.yml` — downrev a package to expose a known CVE | Tony | `[ ]` |
| Trigger Insights scan on affected host (insights-client --check-results) | Tony | `[ ]` |
| Validate Insights → ServiceNow creates an INC ticket | Tony | `[ ]` |
| Document exact INC payload fields (source, category, short_description) | Tony | `[ ]` |

---

### Phase 6 — EDA Incident Response (Due: Jun 16)

**Owner: Eric** (SNow BR + EDA), **Tony** (remediation playbook)

| Task | Owner | Status |
|------|-------|--------|
| ServiceNow Business Rule: watch INC table for Insights-originated tickets | Eric | `[ ]` |
| BR filter: source = Red Hat Insights (validate exact field name from Phase 5) | Eric | `[ ]` |
| BR action: POST INC number + sys_id to AAP EDA event stream | Eric | `[ ]` |
| EDA rulebook: `rulebooks/servicenow_incident_events.yml` — INC → remediate workflow | Eric | `[ ]` |
| `playbooks/remediate_cve.yml` — apply advisory patch to affected host | Tony | `[ ]` |
| snow_log: per-task INC work notes (service.ansible account) | Tony | `[ ]` |
| Close INC on success / escalate on failure | Tony | `[ ]` |
| End-to-end test: downrev → Insights detects → SNow INC → EDA → AAP patches → INC closed | Both | `[ ]` |

---

### Phase 7 — AAP Config as Code (Due: Jun 15)

**Owner: Eric**

| Task | Owner | Status |
|------|-------|--------|
| `aap_config/load.yml` — bootstrap all AAP objects from CaC | Eric | `[ ]` |
| `aap_config/files/controller_credentials.yml` — AWS, SSH, SNow, RH CDN, Controller | Eric | `[ ]` |
| `aap_config/files/controller_job_templates.yml` — all JTs with surveys | Eric | `[ ]` |
| `aap_config/files/controller_workflow_job_templates.yml` — provision + remediate workflows | Eric | `[ ]` |
| `aap_config/files/eda_rulebook_activations.yml` — both activations | Eric | `[ ]` |
| Validate: `ansible-playbook aap_config/validate.yml` passes | Eric | `[ ]` |

---

### Phase 8 — Demo Dress Rehearsal (Due: Jun 17)

**Owner: Both**

| Task | Owner | Status |
|------|-------|--------|
| Complete dry run — both acts, full story | Both | `[ ]` |
| Verify ServiceNow INC real-time updates look good (snow_log cadence) | Tony | `[ ]` |
| Time the demo (target: under 12 minutes for SVP audience) | Both | `[ ]` |
| Write demo talk track (`docs/demo-talk-track.md`) | Tony | `[ ]` |
| Finalize slide / architecture diagram if needed | Eric | `[ ]` |
| Identify and resolve any blockers | Both | `[ ]` |

---

### Phase 9 — SVP Demo (Jun 18, 9:00 AM)

**Owner: Both**

| Task | Owner | Status |
|------|-------|--------|
| Pre-flight: APD env running, SNow reachable, EDA activation green | Tony | `[ ]` |
| Pre-flight: downrev the package on the VM so CVE is live | Tony | `[ ]` |
| Demo Act 1 and Act 2 | Both | `[ ]` |
| Capture feedback | Both | `[ ]` |

---

### Phase 10 — Public Release Hardening (Due: Jun 23)

**Owner: Both**

| Task | Owner | Status |
|------|-------|--------|
| README final pass — architecture diagram, quick-start, prerequisites | Tony | `[ ]` |
| `docs/demo-talk-track.md` polished for community use | Tony | `[ ]` |
| `aap_config/` fully tested + documented | Eric | `[ ]` |
| ServiceNow setup guide complete (`servicenow/README.md`) | Eric | `[ ]` |
| `CHANGELOG.md` updated | Tony | `[ ]` |
| Tag `v1.0.0` release | Tony | `[ ]` |

---

### Phase 11 — Auditable Automated CVE Remediation (Insights → EDA → ServiceNow)

**Owner: Eric** · **Tracking: [#84](https://github.com/toharris-rh/aap.lightspeed.patching/issues/84)**

Evolves **ACT 2** into a fully **auditable** flow using the **native Insights → EDA**
push path (certified `redhat.insights_eda` integration), rather than the
Insights → SNow INC → Business Rule → EDA path in the demo above. When Insights
detects a new CVE that **has an automated remediation**, AAP opens an Incident and
a pre-approved **Standard Change** (from the "Ames - AAP Daily Demo" template /
"Control01"), runs the **Insights-authored** remediation playbook, proves the fix,
and leaves an auditor-verifiable trail. **Phase 1 = automated-solution happy path
only**; the no-solution → Problem-ticket branch is a later phase.

| Slice | Task | Status |
|-------|------|--------|
| 1 | Native Insights→EDA trigger: rulebook + event stream + `X-Insight-Token` credential (live-verified) | `[x]` |
| 2 | `insights_fetch_remediation.yml`: Insights UUID → confirm `remediation==2` → fetch playbook | `[ ]` |
| 3 | Incident + bidirectional CI link (`cmdb_ci` + `task_ci`) + `snow_log` + `snow_attach` role | `[ ]` |
| 4 | Standard Change from template (`sn_chg_rest`) + INC↔CHG (`incident.rfc`) + template alignment | `[ ]` |
| 5 | Run the Insights playbook (dedicated git project: commit → sync → JT run) | `[ ]` |
| 6 | Proof of fix (staged: local now + Insights "CVE cleared" async) + close-out | `[ ]` |
| 7 | Auditor `sys_report` + `docs/cve-remediation-audit.md` + skills/CHANGELOG | `[ ]` |

> En-route fixes already landed on the Slice 1 branch: EDA CaC `401` (minted
> Controller token cleared → basic auth, `load.yml` `failed=0`), ASCII-only CaC
> descriptions (Python 3.14 latin-1 header crash), and the `X-Insight-Token`
> event-stream header. Run `load.yml` from a Python 3.11–3.13 venv (not 3.14).

---

## Open Questions (need answers before Jun 14)

| # | Question | Owner to answer |
|---|----------|----------------|
| ~~Q1~~ | ~~Which SSH key from `~/.ssh`?~~ **Resolved: `~/.ssh/id_rsa`** | Tony ✓ |
| Q2 | What APD catalog item name / RHDP offer is being ordered for AAP? | Tony |
| Q3 | ServiceNow catalog item short_description (exact string — must match EDA rulebook byte-for-byte) | Eric |
| Q4 | Does the Insights→SNow native integration create an **INC** or something else? | Tony (Phase 5) |
| Q5 | Exact field on the SNow INC that identifies it as Insights-originated (for BR filter) | Tony (Phase 5) |
| Q6 | Which package/CVE to downrev for the demo? (something with a known RHSA that Insights detects fast) | Tony |
| Q7 | AAP object namespace prefix — using "Lightspeed Patching -"? Confirm or change | Both |

---

## Key Files

| File | Purpose |
|------|---------|
| `aap_config/load.yml` | Bootstrap all AAP objects in one command |
| `aap_config/group_vars/all.yml` | All CaC variables |
| `docs/dev-environment.sh` | Local secrets (gitignored) |
| `docs/dev-environment.sh.example` | Template — commit this |
| `docs/demo-talk-track.md` | SVP demo script |
| `terraform/` | AWS EC2 provisioning |
| `playbooks/provision_vm_aws.yml` | Terraform wrapper |
| `playbooks/register_rhel.yml` | CDN registration |
| `playbooks/patch_rhel.yml` | Full patch run |
| `playbooks/register_insights.yml` | Insights registration |
| `playbooks/introduce_cve.yml` | Demo CVE setup |
| `playbooks/remediate_cve.yml` | CVE remediation |
| `rulebooks/servicenow_events.yml` | EDA: catalog order → provision |
| `rulebooks/servicenow_incident_events.yml` | EDA: SNow INC → remediate |
