---
name: automation-hub
description: >-
  Talk to Red Hat Automation Hub (console.redhat.com certified/validated content)
  and Private Automation Hub — resolve certified collection versions, exchange
  the offline token for an API access token, and configure ansible-builder / CaC
  to pull certified collections.
  TRIGGER when the user mentions Automation Hub, AH, certified collections,
  rh_certified / rh_validated, console.redhat.com content, galaxy_server, pinning
  collection versions, "latest certified", offline token, Private Automation Hub
  (PAH), or pulling certified content for an EE build.
  SKIP for pure community Galaxy questions with no certified angle, and for AAP
  controller/EDA object CaC (use the aap-config skill).
---

# Red Hat Automation Hub — aap.lightspeed.patching

How to query and pull from Red Hat **certified** / **validated** content on
console.redhat.com, and from a **Private Automation Hub (PAH)**.

## Prefer certified over community

When choosing/pinning collections, **use the Red Hat certified build from
Automation Hub whenever one exists**; fall back to community Galaxy only for
collections with no certified build (e.g. `community.general`). Certified version
numbers differ from Galaxy "latest". (Repo memory: prefer-certified-collections.)

## The galaxy servers (from `~/.ansible.cfg`)

`~/.ansible.cfg` defines three servers and holds the **shared Automation Hub
offline token** (used across all of Eric's repos and by teammates — do **not**
rotate or print it casually):

| Server name | URL |
|-------------|-----|
| `rh_certified` | `https://console.redhat.com/api/automation-hub/content/published/` |
| `rh_validated` | `https://console.redhat.com/api/automation-hub/content/validated/` |
| `community` | `https://galaxy.ansible.com/` |

The `token=` under `[galaxy_server.rh_certified]` is an **offline refresh
token**, not a usable bearer. It must be exchanged at SSO for an access token
(`auth_url`: `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`).

## Guardrails

- **Never print the offline token or any access token.** Read it programmatically;
  don't echo it. Check presence only.
- This `ansible.cfg` is the authoritative one — **never create a project-local
  `ansible.cfg`** (it shadows `~/.ansible.cfg` and breaks certified installs).
- `ansible-galaxy collection info` does **not** exist in the installed
  ansible-core — query the Hub API directly (recipe below).

## Resolve the latest CERTIFIED version of a collection

This is the verified recipe (used to pin EE collections). It never prints the
token:

```python
import configparser, os, json, urllib.request, urllib.parse, ssl
cfg = configparser.ConfigParser(); cfg.read(os.path.expanduser('~/.ansible.cfg'))
tok = cfg.get('galaxy_server.rh_certified', 'token')          # offline token
ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
# 1. exchange offline token -> access token
data = urllib.parse.urlencode({'grant_type':'refresh_token',
        'client_id':'cloud-services','refresh_token':tok}).encode()
req = urllib.request.Request(
  'https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token', data=data)
at = json.load(urllib.request.urlopen(req, context=ctx))['access_token']
# 2. query the collection index -> highest_version (do NOT add order_by — it 400s)
base = ('https://console.redhat.com/api/automation-hub/content/published'
        '/v3/plugin/ansible/content/published/collections/index')
for ns, name in [('amazon','aws'), ('redhat','rhel_system_roles')]:
    r = urllib.request.Request(f'{base}/{ns}/{name}/'); r.add_header('Authorization','Bearer '+at)
    d = json.load(urllib.request.urlopen(r, context=ctx))
    print(ns+'.'+name, '=', d['highest_version']['version'])
```

Gotchas learned: the `/versions/?order_by=-version` query returns **HTTP 400** —
use the collection **index** endpoint (`.../index/{ns}/{name}/`) and read
`highest_version.version`. For validated content swap `content/published` →
`content/validated` in both the base URL path segments.

Known certified versions (2026-06): `amazon.aws` 11.3.0, `servicenow.itsm`
2.15.1, `ansible.platform` 2.7.20260604, `redhat.rhel_system_roles` 1.120.5.

## Pulling certified collections in an EE build (ansible-builder)

ansible-builder needs the certified galaxy server config + token at build time.
Do **not** commit the token. Either:

- export it for the build, e.g.
  `ANSIBLE_GALAXY_SERVER_RH_CERTIFIED_TOKEN=<offline token>` plus
  `ANSIBLE_GALAXY_SERVER_LIST=rh_certified,community`, or
- copy `~/.ansible.cfg` into the build context (gitignored) so ansible-builder's
  galaxy step authenticates.

In the EE `requirements.yml`, pin each certified collection and (optionally) set
`source:` to the certified hub so it isn't fetched from community Galaxy.

## Publishing EE images to quay.io (then PAH syncs from quay)

The EE is pushed to `quay.io/zigfreed/lightspeed-patching-ee`, then Private
Automation Hub syncs it. Gotchas learned the hard way:

- **quay robot tokens can authenticate but not create/push to a new repo.** A
  `zigfreed+<name>_cli` robot logs in fine yet `podman push` fails with
  `authentication required` when the repo doesn't exist — robots can't
  auto-create repos. Fix: push as the **user account** (`podman login -u zigfreed
  quay.io`), which creates the repo on first push; or pre-create the repo in the
  quay UI and grant the robot **Write**.
- **podman reads `~/.docker/config.json` too.** A stale cred set via an old
  `docker login` lives there and shadows your intent; `podman logout` punts to
  `docker logout`. If docker isn't installed, clear the `quay.io` entry from both
  `~/.config/containers/auth.json` and `~/.docker/config.json` directly (JSON
  edit — never print the token), then `podman login -u zigfreed quay.io`.
- **The `!` Claude prompt has no TTY** — `podman login` (hidden password prompt)
  fails there with `inappropriate ioctl for device`. Run interactive logins in a
  real terminal, or use `--password-stdin`. Never type a password as a chat
  message (it lands in the transcript — rotate it if that happens).
- **Make the quay repo public** so PAH can sync it without registry creds
  (matches `hub_ee_registries.yml`, which carries no credentials).

## Private Automation Hub (PAH)

PAH is a separate, self-hosted hub (its hostname is `AH_HOSTNAME` /
`ah_hostname`; on the AAP 2.5/2.6 unified platform it's the same host as AAP). It
serves a **container registry** that AAP pulls EE images from. The CaC
(`hub_ee_registries.yml` + `hub_ee_repositories.yml`) makes PAH **sync** the
image from quay; a **Container Registry** credential (`cred_hub_registry`) lets
Controller pull it. See the **aap-config** skill for wiring the EE object, and
the **environment** skill for `auth.json` / registry-login details.
