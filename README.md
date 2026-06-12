# aap.lightspeed.patching

> **Instantaneous Patching — Patching in the Mythos era**

Automated, AI-assisted patching workflow combining **Red Hat Lightspeed**, **Ansible Automation Platform (AAP)**, and **Event-Driven Ansible (EDA)** to identify, remediate, and report on CVEs and advisories — all with full ITSM and notification integration.

---

## Architecture

```
1. RHEL systems register to Red Hat Lightspeed
2. CVE / Advisor identified by Lightspeed
3. AAP triggers patch job template against affected hosts
4. ITSM ticket created/updated (ServiceNow | Jira)
5. Operational status notifications sent (Slack | Microsoft Teams | Email)
```

![Instantaneous Patching Architecture](docs/images/instantaneous-patching-architecture.png)

---

## Integrations

| Category | Tools |
|----------|-------|
| AI / Advisory | Red Hat Lightspeed |
| Automation | Ansible Automation Platform (AAP), Event-Driven Ansible |
| Patching Target | Red Hat Enterprise Linux (RHEL) |
| ITSM | ServiceNow, Jira |
| Notifications | Slack, Microsoft Teams, Email |

---

## Prerequisites

- Ansible Automation Platform 2.4+
- Red Hat Lightspeed subscription
- RHEL hosts registered to Red Hat Insights
- `ansible.cfg` configured (see `ansible.cfg.example`)

---

## Quick Start

```bash
git clone https://github.com/toharris-rh/aap.lightspeed.patching.git
cd aap.lightspeed.patching
cp ansible.cfg.example ansible.cfg
# Edit ansible.cfg with your AAP controller URL and credentials
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and [docs/](docs/) for full documentation.

---

## License

[MIT](LICENSE)
