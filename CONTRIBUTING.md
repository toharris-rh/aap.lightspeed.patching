# Contributing

Contributions to `aap.lightspeed.patching` are welcome — playbook and rulebook
improvements, CaC object definitions, ServiceNow integration fixes, docs, and
roadmap items. This repo implements automated, AI-assisted RHEL patching that
combines **Red Hat Lightspeed**, **Ansible Automation Platform (AAP)**, and
**Event-Driven Ansible (EDA)** with **ServiceNow ITSM** integration. Read
[`README.md`](README.md), [`docs/servicenow-integration.md`](docs/servicenow-integration.md),
[`ROADMAP.md`](ROADMAP.md), and [`CLAUDE.md`](CLAUDE.md) first.

## Content & secret policy

**Never commit:**

- AAP tokens, ServiceNow credentials, Red Hat Insights/Lightspeed service-account
  secrets, or AWS keys
- Customer or company names, RHDP deployment URLs, cluster/instance IDs, or other
  identifying details — use generic placeholders (e.g.
  `controller-<id>.apps.<cluster>.rhdp.net`)
- EDA event-stream shared secrets, SSH private keys, passwords, or session cookies

Per-developer values go in `docs/dev-environment.sh` (copied from
`docs/dev-environment.sh.example` and **gitignored**). Commit only the
`.example` template with placeholder values. Audit every diff for credentials or
customer data before pushing.

## Workflow

1. Branch off `main` (`main` is protected — all changes land via PR).
2. Make one focused change. Keep YAML and Ansible clean:
   - `yamllint .` against [`.yamllint`](.yamllint)
   - `ansible-lint --offline` against [`.ansible-lint`](.ansible-lint)

   Both run in CI on every PR. When you add a certified module that isn't
   installed locally in CI (e.g. a new `servicenow.itsm.*` or
   `ansible.controller.*` module), add it to `mock_modules` in `.ansible-lint`
   or `ansible-lint --offline` will fail the unskippable `syntax-check` rule.
3. Update [`CHANGELOG.md`](CHANGELOG.md) under `[Unreleased]`
   (Added / Changed / Fixed / Removed).
4. Update [`ROADMAP.md`](ROADMAP.md) phase status or the Decisions Log if the
   plan changes.
5. Open a PR using the template; fill in Summary, Test plan, and Risk/rollback.

## Pull requests

- One concern per PR — group by shared root cause, not item count. The test:
  would you revert these changes together?
- Descriptive title, e.g. `Fix teardown 401: rename aap_token fact`.
- Behavior changes and anything risky stay isolated.
- Additive only — don't remove old capabilities until replacements are proven.
