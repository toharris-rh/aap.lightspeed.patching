---
name: vm-access
description: >-
  Access provisioned RHEL VMs — look up hosts from the AAP controller inventory
  (not local Terraform state), SSH in, and run commands. Covers the gateway API
  path, inventory structure, SSH credentials, and common checks.
  TRIGGER when the user mentions SSH, logging into a VM, checking a VM, running
  a command on the host, host connectivity, "can you reach", the provisioned
  instance, or the lightspeed-patching inventory hosts.
  SKIP for provisioning new VMs (terraform skill), AAP object CaC (aap-config
  skill), or credential setup (environment skill).
---

# VM Access — aap.lightspeed.patching

How to find and connect to VMs provisioned by this repo's Terraform + AAP
pipeline.

## Finding the VM

There is **no usable local Terraform state** — state lives in S3 and
`terraform output` requires `terraform init` against the remote backend.
Always look up hosts from the **AAP controller inventory** instead.

### AAP inventory lookup

The AAP gateway uses `/api/controller/v2/`, **not** `/api/v2/` (which returns
404 on AAP 2.5+).

```bash
source docs/dev-environment.sh && \
curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  "${AAP_HOSTNAME%/}/api/controller/v2/inventories/?search=lightspeed" \
  | python3 -m json.tool
```

The inventory name is **`lightspeed-patching`** (org: IT Service Automation).
Get its hosts:

```bash
source docs/dev-environment.sh && \
curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  "${AAP_HOSTNAME%/}/api/controller/v2/inventories/5/hosts/" \
  | python3 -m json.tool
```

> **Note:** The inventory ID (5 above) can change across AAP rebuilds. If it
> 404s, re-query the inventories list first.

### Host record structure

Each host entry has:
- `name` — AWS public DNS FQDN (e.g. `ec2-X-X-X-X.compute-1.amazonaws.com`)
- `variables` — JSON string containing:
  - `ansible_host` — **public IP** (use this for SSH)
  - `vm_name` — e.g. `lsp-rhel-medium-pn4ec`
  - `instance_id` — EC2 instance ID
  - `vm_size_chosen` — e.g. `t3.large`

Parse the IP:
```bash
echo '<variables_json>' | python3 -c "import sys,json; print(json.load(sys.stdin)['ansible_host'])"
```

## SSH access

```bash
ssh -i ~/.ssh/id_rsa ec2-user@<ansible_host>
```

- **User:** `ec2-user` (RHEL EC2 default, set by `linux_admin_username`)
- **Key:** `~/.ssh/id_rsa` (the matching public key was injected at provision
  time via `TF_VAR_linux_ssh_public_key`)
- **Port:** 22 (open in the security group along with 80, 443, 9090/Cockpit)

## Common checks

Quick health check after connecting:
```bash
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
  ec2-user@<ip> 'hostname && uptime && cat /etc/redhat-release'
```

Check subscription / Insights registration:
```bash
ssh -i ~/.ssh/id_rsa ec2-user@<ip> \
  'sudo subscription-manager status && sudo insights-client --status'
```

## Relationship to other skills

- **terraform** — covers provisioning the VM (Terraform apply, S3 state, t-shirt sizing)
- **environment** — covers credential setup (`LINUX_SSH_PRIVATE_KEY`, `LINUX_SSH_PUBLIC_KEY` in `dev-environment.sh`)
- **aap-config** — covers the AAP inventory object definition in CaC
- **servicenow** — covers CMDB registration of the provisioned VM
