#!/usr/bin/env bash
# docs/check-env.sh — pre-demo environment health check
# Usage: source docs/dev-environment.sh && bash docs/check-env.sh

set -euo pipefail

PASS="  OK"
FAIL="  FAIL"
ok=true

check() {
    local label="$1" result="$2"
    if [[ "$result" == *FAIL* ]]; then
        echo "$FAIL  $label: $result"
        ok=false
    else
        echo "$PASS  $label: $result"
    fi
}

require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "$FAIL  $var is not set — run: source docs/dev-environment.sh"
        ok=false
        return 1
    fi
}

echo "=== Lightspeed Patching — environment check ==="
echo

# Require env vars
for v in AAP_HOSTNAME AAP_CONTROLLER_USERNAME AAP_CONTROLLER_PASSWORD \
          SATELLITE_URL SATELLITE_USERNAME SATELLITE_PASSWORD \
          SN_HOST SN_USERNAME SN_PASSWORD; do
    require_env "$v" || true
done
echo

# AAP gateway
result=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
    "${AAP_HOSTNAME}/api/gateway/v1/ping/" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"v{d['version']} status={d['status']}\")" 2>/dev/null || echo "FAIL")
check "AAP gateway" "$result"

# AAP controller
result=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
    "${AAP_HOSTNAME}/api/controller/v2/ping/" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"v{d['version']} instances={len(d.get('instances',[]))}\")" 2>/dev/null || echo "FAIL")
check "AAP controller" "$result"

# EDA activations (running)
result=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
    "${AAP_HOSTNAME}/api/eda/v1/activations/?status=running&page_size=20" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
names = [a['name'] for a in d.get('results', [])]
print(f\"{len(names)} running: {', '.join(names) if names else 'none'}\")
" 2>/dev/null || echo "FAIL")
check "EDA activations" "$result"

# Satellite
result=$(curl -sk -u "${SATELLITE_USERNAME}:${SATELLITE_PASSWORD}" \
    "${SATELLITE_URL}/api/v2/status" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"v{d['version']} result={d['result']}\")" 2>/dev/null || echo "FAIL")
check "Satellite" "$result"

# ServiceNow
result=$(curl -sk -u "${SN_USERNAME}:${SN_PASSWORD}" \
    "${SN_HOST}/api/now/table/incident?sysparm_limit=1&sysparm_fields=number" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('reachable' if d.get('result') is not None else 'FAIL')" 2>/dev/null || echo "FAIL")
check "ServiceNow" "$result"

# Provisioned hosts
result=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
    "${AAP_HOSTNAME}/api/controller/v2/hosts/?page_size=20" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
hosts = [h['name'] for h in d.get('results', []) if h.get('enabled') and h['name'] != 'localhost']
print(f\"{len(hosts)} host(s): {', '.join(hosts) if hosts else 'none provisioned'}\")
" 2>/dev/null || echo "FAIL")
check "Provisioned hosts" "$result"

# Satellite: CV lifecycle state — Development must be behind the latest version
result=$(curl -sk -u "${SATELLITE_USERNAME}:${SATELLITE_PASSWORD}" \
    "${SATELLITE_URL}/katello/api/content_view_versions?content_view_name=RHEL9&order=version+desc&per_page=10" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
versions = d.get('results', [])
if not versions:
    print('FAIL: no CV versions found')
    sys.exit()
latest = versions[0]
latest_ver = latest['version']
latest_envs = [e['name'] for e in latest.get('environments', [])]
dev_version = next((v['version'] for v in versions if any(e['name'] == 'Development' for e in v.get('environments', []))), None)
if dev_version is None:
    print(f'FAIL: Development not promoted to any version')
elif dev_version == latest_ver:
    print(f'FAIL: Development already on latest v{latest_ver} — run Demo Reset before demo')
else:
    print(f'OK: Development on v{dev_version}, latest is v{latest_ver} — promotion will fire')
" 2>/dev/null || echo "FAIL")
[[ "$result" == *FAIL* ]] && { echo "$FAIL  Satellite CV/LCE state: $result"; ok=false; } || echo "$PASS  Satellite CV/LCE state: $result"

# Satellite: demo errata must be in the latest CV version
result=$(curl -sk -u "${SATELLITE_USERNAME}:${SATELLITE_PASSWORD}" \
    "${SATELLITE_URL}/katello/api/content_view_versions?content_view_name=RHEL9&order=version+desc&per_page=1" \
    | python3 -c "
import sys, json, urllib.request, urllib.parse, base64, ssl
d = json.load(sys.stdin)
versions = d.get('results', [])
if not versions:
    print('FAIL: no CV versions found')
    sys.exit()
print(versions[0]['id'])
" 2>/dev/null)
latest_cv_id="$result"
errata_result=$(curl -sk -u "${SATELLITE_USERNAME}:${SATELLITE_PASSWORD}" \
    "${SATELLITE_URL}/katello/api/errata?content_view_version_id=${latest_cv_id}&per_page=1" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('total', 0))
" 2>/dev/null || echo "0")
if [[ "$errata_result" -gt 0 ]] 2>/dev/null; then
    echo "$PASS  Satellite latest CV has errata ($errata_result total)"
else
    echo "$FAIL  Satellite latest CV has no errata — incremental update may be needed"
    ok=false
fi

echo
if $ok; then
    echo "All checks passed — ready to demo."
else
    echo "One or more checks failed — review above before starting the demo."
    exit 1
fi
