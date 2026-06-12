# aap.lightspeed.patching

> **Instantaneous Patching — Patching in the Mythos era**

Automated, AI-assisted patching workflow combining **Red Hat Lightspeed**,
**Ansible Automation Platform (AAP)**, and **Event-Driven Ansible (EDA)** to
identify, remediate, and record CVEs and advisories — with full ITSM integration.

---

## Architecture

![Instantaneous Patching Architecture](docs/images/instantaneous-patching-architecture.png)

```
1. RHEL systems register to Red Hat Lightspeed
2. CVE / Advisor identified by Lightspeed
3. AAP runs patch job template against affected hosts
4. ITSM Change Request created and updated (ServiceNow)
```

---

## Integrations

| Category | Tools |
|----------|-------|
| AI / Advisory | Red Hat Lightspeed |
| Automation | Ansible Automation Platform (AAP), Event-Driven Ansible |
| Patching Target | Red Hat Enterprise Linux (RHEL) |
| ITSM | ServiceNow |

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and
[docs/servicenow-integration.md](docs/servicenow-integration.md) for the
full ITSM integration guide.

---

## License

[MIT](LICENSE)
