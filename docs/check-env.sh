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
hosts_json=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
    "${AAP_HOSTNAME}/api/controller/v2/hosts/?page_size=20" 2>/dev/null || echo "{}")
result=$(echo "$hosts_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
hosts = [h['name'] for h in d.get('results', []) if h.get('enabled') and h['name'] != 'localhost']
print(f\"{len(hosts)} host(s): {', '.join(hosts) if hosts else 'none provisioned'}\")
" 2>/dev/null || echo "FAIL")
check "Provisioned hosts" "$result"

# Capture demo host for downstream checks
demo_host=$(echo "$hosts_json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
hosts = [h['name'] for h in d.get('results', []) if h.get('enabled') and h['name'] != 'localhost']
print(hosts[0] if hosts else '')
" 2>/dev/null || echo "")

# Satellite: demo VM is registered
if [[ -n "$demo_host" ]]; then
    result=$(curl -sk -u "${SATELLITE_USERNAME}:${SATELLITE_PASSWORD}" \
        "${SATELLITE_URL}/api/v2/hosts?search=name%3D${demo_host}&per_page=1&include=content_facet_attributes" \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
total = d.get('total', 0)
if total > 0:
    h = d['results'][0]
    cfe = h.get('content_facet_attributes', {})
    cves = cfe.get('content_view_environments', [])
    if cves:
        cv = cves[0].get('content_view', {})
        lce = cves[0].get('lifecycle_environment', {})
        print(f\"registered (cv={cv.get('name','?')} v{cv.get('content_view_version','?')}, lce={lce.get('name','?')})\")
    else:
        print('registered (cv/lce unknown)')
else:
    print('FAIL: host not found in Satellite — run Register RHEL JT')
" 2>/dev/null || echo "FAIL")
    check "Satellite host registration" "$result"
else
    echo "$FAIL  Satellite host registration: skipped — no demo host found"
    ok=false
fi

# Insights: demo VM is registered
if [[ -n "$demo_host" ]]; then
    insights_token=$(curl -sk -X POST \
        "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token" \
        -d "grant_type=client_credentials&client_id=${INSIGHTS_CLIENT_ID}&client_secret=${INSIGHTS_CLIENT_SECRET}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
    if [[ -n "$insights_token" ]]; then
        result=$(curl -sk \
            -H "Authorization: Bearer ${insights_token}" \
            "https://console.redhat.com/api/inventory/v1/hosts?display_name=${demo_host}&per_page=1" \
            | python3 -c "
import sys, json
d = json.load(sys.stdin)
total = d.get('total', 0)
if total > 0:
    h = d['results'][0]
    print(f\"registered (insights_id={h.get('insights_id','?')[:8]}...)\")
else:
    print('FAIL: host not in Insights inventory — run insights-client --register on host')
" 2>/dev/null || echo "FAIL")
    else
        result="FAIL: could not get Insights token — check INSIGHTS_CLIENT_ID/SECRET"
    fi
    check "Insights registration" "$result"
else
    echo "$FAIL  Insights registration: skipped — no demo host found"
    ok=false
fi

# ServiceNow: Business Rule that triggers EDA must be active
result=$(curl -sk -u "${SN_USERNAME}:${SN_PASSWORD}" \
    "${SN_HOST}/api/now/table/sys_script?sysparm_query=name=Harris+-+Inc&sysparm_fields=name,active&sysparm_limit=1" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('result', [])
if not results:
    print('FAIL: Business Rule not found — check ServiceNow instance')
elif results[0].get('active') == 'true':
    print('active')
else:
    print('FAIL: Business Rule is inactive — EDA will not receive SNow incidents')
" 2>/dev/null || echo "FAIL")
check "SNow Business Rule (Harris - Inc)" "$result"

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
