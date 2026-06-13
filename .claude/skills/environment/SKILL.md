---
name: environment
description: >-
  Credential and environment management for aap.lightspeed.patching — setting up
  docs/dev-environment.sh, testing AAP/AWS/ServiceNow/SSH/CDN connectivity,
  diagnosing auth failures, and understanding the env-var→Ansible→CaC flow.
  TRIGGER when the user mentions environment, credentials, creds, dev-environment,
  env vars, AAP auth, AWS auth, SSH key, token, new RHDP env, bootstrap creds,
  source dev-environment, activation key, Insights client secret, EE version,
  or auth failure / 401 / connectivity.
  SKIP when the question is purely about ServiceNow ITSM workflow logic (change
  request lifecycle, incidents, CMDB updates, work notes, EDA rulebook content) —
  use the servicenow skill instead.
---

# Environment & Credentials — aap.lightspeed.patching

Reference for credential setup, environment configuration, and the
env-var→Ansible variable→CaC pipeline. Use this skill when setting up a new dev
environment, testing connectivity, or diagnosing auth failures.

## Env-var flow

```
Shell (source docs/dev-environment.sh)
  → lookup('ansible.builtin.env', 'VAR') in aap_config/group_vars/all.yml
  → Jinja2 templates in aap_config/files/*.yml (controller_credentials.yml, etc.)
  → infra.aap_configuration.dispatch role (aap_config/load.yml)
  → AAP objects created/updated on the target controller
```

Every sensitive value is resolved at runtime from an environment variable. No
secrets in version control — ever.

## Guardrails

- **Never print passwords/secrets** — check by name only:
  `printenv AAP_CONTROLLER_PASSWORD >/dev/null && echo set`.
- **`docs/dev-environment.sh` is gitignored** — NEVER commit it, never paste its
  contents into chat, PRs, or commit messages.
- **Env vars do NOT persist across Bash tool calls** — Claude Code runs each
  Bash invocation in a fresh shell. Always `source docs/dev-environment.sh` in
  the same invocation as the command that needs the vars:
  ```bash
  source docs/dev-environment.sh && ansible-playbook aap_config/load.yml
  ```
- **No project-local `ansible.cfg`** — the user's `~/.ansible.cfg` holds the
  Automation Hub `galaxy_server` token shared across repos. A project-local cfg
  shadows it and breaks `ansible-galaxy collection install` for certified
  content.
- **Always delete AAP tokens** — any playbook that mints a token must delete it
  in an `always:` block (see token handling pattern below).
- **Never put customer info in tracked files** — no customer names, RHDP URLs,
  cluster IDs, passwords, or tokens in committed files.

## Credential groups

### 1. AAP (from Red Hat Demo Platform)

| Env var | Purpose | Default |
|---------|---------|---------|
| `AAP_HOSTNAME` | Controller URL, e.g. `https://controller.XXXXXXX.rhdemos.com` | *(required)* |
| `AAP_CONTROLLER_USERNAME` | API user | `admin` |
| `AAP_CONTROLLER_PASSWORD` | API password | *(required)* |
| `AAP_VALIDATE_CERTS` | TLS verification | `false` |
| `AH_HOSTNAME` | Private Automation Hub (if separate from controller) | *(optional)* |

**AAP 2.5 gateway note**: The ping endpoint is `/api/gateway/v1/ping/`, NOT the
legacy `/api/v2/ping/`. Using the wrong path returns 404 and looks like a
connectivity failure.

### 2. AWS

| Env var | Purpose | Default |
|---------|---------|---------|
| `AWS_ACCESS_KEY_ID` | IAM access key | *(required)* |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key | *(required)* |
| `AWS_DEFAULT_REGION` | EC2 region | `us-east-1` |
| `AWS_TF_STATE_BUCKET` | S3 bucket for Terraform remote state | *(required)* |

The S3 bucket name must be globally unique. Suggested naming:
`lightspeed-patching-tfstate-<your-initials>`. Create once per RHDP environment
before running `load.yml`.

### 3. SSH / Linux machine

| Env var | Purpose | Default |
|---------|---------|---------|
| `LINUX_ADMIN_USERNAME` | SSH user on EC2 instances | `ec2-user` |
| `LINUX_SSH_PRIVATE_KEY` | Private key content (via `$(cat ~/.ssh/id_rsa)`) | *(required)* |
| `LINUX_SSH_PUBLIC_KEY` | Public key content (via `$(cat ~/.ssh/id_rsa.pub)`) | *(required)* |

These are read by `cat` at source time — the key file must exist at the path
in `dev-environment.sh`. The private key is injected into the AAP Machine
credential `Lightspeed Patching - Linux Machine`.

### 4. Red Hat CDN

| Env var | Purpose | Default |
|---------|---------|---------|
| `RH_ORG_ID` | Red Hat org ID (from console.redhat.com → Subscriptions) | *(required)* |
| `RH_ACTIVATION_KEY` | Activation key name | *(required)* |

Used by the AAP credential `Lightspeed Patching - Red Hat CDN` (type
`Red Hat CDN Registration`) to register new RHEL VMs.

### 5. ServiceNow

| Env var | Purpose | Default |
|---------|---------|---------|
| `SN_HOST` | Instance URL (`https://<instance>.service-now.com`) | *(required)* |
| `SN_USERNAME` | API user (needs `itil` + REST roles) | *(required)* |
| `SN_PASSWORD` | API password | *(required)* |
| `EDA_EVENT_STREAM_TOKEN` | Bearer token for SNow→EDA webhook | *(required)* |

**Use the exact `SN_USERNAME`** from `docs/dev-environment.sh` — a plausible
variant returns HTTP 401 `User Not Authenticated`, not a clear error.

The EDA bearer token is a **matched pair**: same value in the AAP EDA
event-stream credential AND in the inbound webhook Authorization header.
Generate with: `openssl rand -hex 32`.

### 6. Red Hat Insights / Hybrid Cloud Console

| Env var | Purpose | Default |
|---------|---------|---------|
| `INSIGHTS_BASE_URL` | Console URL | `https://console.redhat.com` |
| `INSIGHTS_CLIENT_ID` | Service account client ID | *(optional)* |
| `INSIGHTS_CLIENT_SECRET` | Service account client secret | *(optional)* |

**Note**: These vars are defined in the template but are not yet consumed by
any playbook in `aap_config/group_vars/all.yml`. They exist for future direct
Insights API calls (e.g. triggering scans).

### 7. Automation Analytics / Subscriptions

| Env var | Purpose | Default |
|---------|---------|---------|
| `REDHAT_SUBSCRIPTIONS_CLIENT_ID` | console.redhat.com **service-account** client ID for Automation Analytics uploads | *(optional)* |
| `REDHAT_SUBSCRIPTIONS_CLIENT_SECRET` | service-account client secret (write-only; AAP reads back `$encrypted$`) | *(optional)* |

These feed the **Automation Calculator** (Analytics → Automation Calculator).
`aap_config/files/controller_settings.yml` consumes them via
`group_vars/all.yml` (`redhat_subscriptions_client_id` /
`redhat_subscriptions_client_secret`) and sets `INSIGHTS_TRACKING_STATE: true`
plus `SUBSCRIPTIONS_CLIENT_ID` / `SUBSCRIPTIONS_CLIENT_SECRET`. Without them the
UI shows *"Missing Gather data for Automation Analytics."*

These are a **service account** (client ID + secret from console.redhat.com →
Service Accounts), NOT a portal username/password. Leave unset to skip analytics
auth — `INSIGHTS_TRACKING_STATE` still flips on but uploads won't authenticate.
Distinct from the Insights vars in group 6 (`INSIGHTS_CLIENT_ID`/`_SECRET`),
which are a different, not-yet-consumed service account.

**Operational**: enabling tracking is necessary but not sufficient — the
calculator only shows data after an upload runs (default gather interval ~4h;
force one from Settings → Subscription) AND job templates have actually run.

### 8. Execution Environment

| Env var | Purpose | Default |
|---------|---------|---------|
| `LIGHTSPEED_PATCHING_EE_VERSION` | EE image tag | `v1.0.0` |
| `LIGHTSPEED_PATCHING_EE_IMAGE` | Full EE image URI (optional override) | built-in RHEL9 EE |

## Token handling pattern

`aap_config/tasks/aap_token_acquire.yml` mints a short-lived token from
username/password (or reuses `AAP_TOKEN` if already set).
`aap_config/tasks/aap_token_release.yml` deletes the minted token in an
`always:` block, so stale tokens never accumulate.

```yaml
# Pattern used in aap_config/load.yml:
tasks:
  - include_tasks: tasks/aap_token_acquire.yml
  - include_role:
      name: infra.aap_configuration.dispatch
always:
  - include_tasks: tasks/aap_token_release.yml
```

Any new playbook that mints tokens MUST follow this pattern.

## Key files

| File | Purpose |
|------|---------|
| `docs/dev-environment.sh.example` | Committed template — copy to create `dev-environment.sh` |
| `docs/dev-environment.sh` | Gitignored secrets file (the real credentials) |
| `aap_config/group_vars/all.yml` | Env var → Ansible variable bindings |
| `aap_config/load.yml` | CaC entrypoint — applies all AAP objects via dispatch |
| `aap_config/tasks/aap_token_acquire.yml` | Mints short-lived AAP API token |
| `aap_config/tasks/aap_token_release.yml` | Deletes minted token (always block) |
| `aap_config/files/controller_credentials.yml` | AAP credential definitions (AWS, Linux, Controller, SNow, CDN) |
| `aap_config/files/eda_credentials.yml` | EDA credential definitions (Controller, event stream token) |
| `aap_config/requirements.yml` | Collection dependencies — install before `load.yml` |

## AAP credentials created by CaC

| AAP credential name | Type | Inputs sourced from |
|---------------------|------|---------------------|
| `Lightspeed Patching - AWS` | Amazon Web Services | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `Lightspeed Patching - Linux Machine` | Machine | `LINUX_ADMIN_USERNAME`, `LINUX_SSH_PRIVATE_KEY` |
| `Lightspeed Patching - Controller` | Red Hat Ansible Automation Platform | `AAP_HOSTNAME`, `AAP_CONTROLLER_USERNAME`, `AAP_CONTROLLER_PASSWORD` |
| `Lightspeed Patching - ServiceNow` | ServiceNow ITSM | `SN_HOST`, `SN_USERNAME`, `SN_PASSWORD` |
| `Lightspeed Patching - Red Hat CDN` | Red Hat CDN Registration | `RH_ORG_ID`, `RH_ACTIVATION_KEY` |

## Common tasks

### Set up a new environment from scratch

```bash
# 1. Copy the template
cp docs/dev-environment.sh.example docs/dev-environment.sh

# 2. Edit and fill in all credential values
#    (use your editor — never echo secrets into files)

# 3. Verify SSH key exists at the path referenced in dev-environment.sh
ls -la ~/.ssh/id_rsa ~/.ssh/id_rsa.pub

# 4. Install required collections
ansible-galaxy collection install -r aap_config/requirements.yml

# 5. Source and test (see credential testing below)
source docs/dev-environment.sh
```

### Test all credentials

Run in a single invocation (env vars don't persist across Bash tool calls):

```bash
source docs/dev-environment.sh && \
echo "=== AAP ===" && \
curl -sk -o /dev/null -w "HTTP %{http_code}" \
  -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  "${AAP_HOSTNAME%/}/api/gateway/v1/ping/" && echo "" && \
echo "=== AWS ===" && \
aws sts get-caller-identity && \
echo "=== ServiceNow ===" && \
curl -s -u "$SN_USERNAME:$SN_PASSWORD" -o /dev/null \
  -w "HTTP %{http_code}\n" \
  "$SN_HOST/api/now/table/change_request?sysparm_limit=1&sysparm_fields=number" && \
echo "=== SSH key ===" && \
(test -f ~/.ssh/id_rsa && echo "private key exists" || echo "MISSING private key") && \
(test -f ~/.ssh/id_rsa.pub && echo "public key exists" || echo "MISSING public key")
```

Expected: AAP HTTP 200, AWS account JSON, ServiceNow HTTP 200, both keys exist.

### Check which env vars are set (without printing values)

```bash
source docs/dev-environment.sh && \
for var in AAP_HOSTNAME AAP_CONTROLLER_USERNAME AAP_CONTROLLER_PASSWORD \
  AAP_VALIDATE_CERTS AH_HOSTNAME AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
  AWS_DEFAULT_REGION AWS_TF_STATE_BUCKET LINUX_ADMIN_USERNAME \
  RH_ORG_ID RH_ACTIVATION_KEY SN_HOST SN_USERNAME SN_PASSWORD \
  EDA_EVENT_STREAM_TOKEN INSIGHTS_CLIENT_ID INSIGHTS_CLIENT_SECRET \
  LIGHTSPEED_PATCHING_EE_VERSION; do
  printenv "$var" >/dev/null 2>&1 && printf "%-40s SET\n" "$var" \
    || printf "%-40s *** MISSING ***\n" "$var"
done
```

### Run the CaC load

```bash
source docs/dev-environment.sh && \
ansible-playbook aap_config/load.yml 2>&1 | tee /tmp/load-$(date +%Y%m%d-%H%M%S).log
```

### Add a new credential section

1. Add env vars to `docs/dev-environment.sh.example` (committed template) with
   comments explaining where to get the values.
2. Add the same vars to your local `docs/dev-environment.sh` with real values.
3. Add `lookup('ansible.builtin.env', ...)` bindings in
   `aap_config/group_vars/all.yml`.
4. Add a credential entry in `aap_config/files/controller_credentials.yml`
   (or `eda_credentials.yml` for EDA credentials).
5. Update this skill file with the new credential group.

## Diagnosing auth failures

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| AAP curl returns 404 | Using legacy `/api/v2/` path | Use `/api/gateway/v1/` (AAP 2.5+) |
| AAP curl returns 401 | Wrong password or username | Verify against RHDP detail page |
| SNow curl returns 401 `User Not Authenticated` | Wrong `SN_USERNAME` variant | Use exact username from `dev-environment.sh` |
| `ansible-galaxy collection install` fails for certified content | Project-local `ansible.cfg` shadowing `~/.ansible.cfg` | Delete the project-local `ansible.cfg` |
| SSH key not found during CaC load | Key path in `dev-environment.sh` doesn't match actual file | Check `~/.ssh/id_rsa` exists; update path if using a `.pem` |
| Token accumulation on AAP | Missing `always:` block in playbook | Add `aap_token_release.yml` in always block |
| AWS `ExpiredToken` / `InvalidClientTokenId` | Stale or rotated IAM keys | Regenerate in AWS console; update `dev-environment.sh` |

## Collections (from aap_config/requirements.yml)

| Collection | Version | Purpose |
|------------|---------|---------|
| `infra.aap_configuration` | 4.4.0 | CaC dispatch role |
| `ansible.platform` | 2.6.20251106 | AAP 2.5 token/resource modules |
| `ansible.controller` | 4.7.8 | Legacy controller modules (avoid in new code) |
| `ansible.eda` | 2.11.0 | EDA objects |
| `servicenow.itsm` | 2.7.0 | ServiceNow Table API / incident |
| `amazon.aws` | 9.0.0 | AWS resource management |
| `community.general` | 10.0.0 | General-purpose modules |

Install: `ansible-galaxy collection install -r aap_config/requirements.yml`
