---
name: terraform
description: >-
  The Terraform AWS provisioning under terraform/ — VPC + RHEL 9 EC2 stack, S3
  remote-state backend, t-shirt sizing — and how playbooks/provision_vm_aws.yml
  wraps it to run from AAP. Covers the auth/region gotchas and the run path.
  TRIGGER when the user mentions terraform, terraform/, provisioning a VM/EC2,
  the Provision VM job template, AWS infra, S3 state backend, vm_size_tier, or
  errors like "invalid AWS Region", terraform init/apply failures, or terraform
  not found in the EE.
  SKIP for AAP object CaC unrelated to provisioning (aap-config), EE build itself
  (execution-environment), or credential env-var setup (environment).
---

# Terraform AWS provisioning — aap.lightspeed.patching

`terraform/` provisions the demo's AWS infra; `playbooks/provision_vm_aws.yml`
wraps it (init → apply → parse outputs → register host in AAP) and runs **from
AAP** as the **"Lightspeed Patching - Provision VM (AWS)"** job template (JT, on
the custom EE that carries the terraform CLI).

## What it builds (`terraform/`)

- `main.tf` — VPC (`10.50.0.0/16`) + public subnet + IGW + route table + security
  group + SSH key pair + a **RHEL 9 EC2 instance**.
- `data.tf` — RHEL 9 AMI lookup. `locals.tf` — `vm_size_tier` → instance type map.
- `variables.tf` — `vm_size_tier` (small|medium|large, default medium),
  `linux_admin_username` (ec2-user), `linux_ssh_public_key`, `vpc_cidr`,
  `subnet_cidr`, `allowed_source_cidrs`, `tags`.
- `outputs.tf` — **`linux_inventory`** (host, ansible_host, instance_id, vm_name,
  vm_size_chosen, ansible_user) — the playbook parses this and registers the host
  in the AAP `lightspeed-patching` inventory via `ansible.controller.host`/`.group`.
- `providers.tf` — AWS + random providers; **region and creds come from env vars**
  (no hardcoding). `backend.tf` — **S3 remote state** (partial; values at init).

**t-shirt sizing:** small → t3.medium · medium → t3.large · large → t3.xlarge
(`vm_size_map` mirrored in `group_vars/all.yml` and the JT survey `vm_size_tier`,
default medium).

## How it runs

Preferred: **launch JT "Lightspeed Patching - Provision VM (AWS)"** in AAP (survey
asks `vm_size_tier`). The job runs on the custom EE; the controller project syncs
the playbook from `main` (`scm_update_on_launch: true` during dev). Local
`ansible-playbook` is for debugging only — the demo path is AAP.

S3 backend init (the playbook does this, values from env):
```
terraform init -backend-config="bucket=$AWS_TF_STATE_BUCKET" \
  -backend-config="key=lightspeed-patching.tfstate" \
  -backend-config="region=$AWS_DEFAULT_REGION"
```
The bucket must exist first (one-time `aws s3 mb`). Current: `AWS_TF_STATE_BUCKET`
in `dev-environment.sh`, region us-east-1.

## Gotchas (hard-won)

1. **The EE must contain the terraform CLI.** The playbook shells out to
   `terraform`; no stock EE has it. Runs on the custom EE — see the
   **execution-environment** skill. Symptom otherwise: `terraform: command not found`.
2. **AWS region must be supplied via `AWS_DEFAULT_REGION`.** `providers.tf` reads
   region + creds from env. The AAP **AWS credential injects the access key/secret
   but NOT a region**, so `terraform apply` fails with *"invalid AWS Region: "*.
   `provision_vm_aws.yml` sets `AWS_DEFAULT_REGION: "{{ aws_region }}"` (default
   us-east-1) in the apply task env. There is **no `aws_region` terraform var** —
   it's purely env-driven.
3. **AWS creds** reach terraform from the JT's AWS credential (injected
   `AWS_ACCESS_KEY_ID`/`SECRET` into the job env; the task `environment:` augments,
   doesn't replace, so they survive).
4. **SSH public key** is passed as `TF_VAR_linux_ssh_public_key` (from
   `LINUX_SSH_PUBLIC_KEY`), not committed.
5. **`apply` uses `no_log: true`** (creds in env) — on failure the playbook has a
   dedicated "Show Terraform error" debug task so the real error is still visible.
6. **Failures route to ServiceNow** — the play's `rescue` captures the error via
   `set_stats` for the workflow's incident node, then re-fails.

## Teardown

State lives in S3; `terraform destroy` (same backend-config init) tears the stack
down. No teardown playbook/JT exists yet — add one before relying on it.
