#!/usr/bin/env bash
# ============================================================================
# send_cve_to_snow.sh
# ============================================================================
# Queries Red Hat Insights for CVEs with known exploits on the provisioned VM,
# picks the highest CVSS one, and POSTs a vulnerability payload directly to
# the ServiceNow Flow Templates for Red Hat Insights endpoint to create an
# incident — bypassing the native Insights→ServiceNow integration (which only
# fires once per CVE per account).
#
# Usage:
#   source docs/dev-environment.sh
#   ./send_cve_to_snow.sh [CVE-ID]        # optional: pin a specific CVE
#
# Requirements: curl, python3, jq (optional)
# ============================================================================

set -euo pipefail

# ── Config from dev-environment.sh ───────────────────────────────────────────
: "${SN_HOST:?source docs/dev-environment.sh first}"
: "${RH_INSIGHTS_INTEGRATION_PASSWORD:?source docs/dev-environment.sh first}"
: "${INSIGHTS_CLIENT_ID:?source docs/dev-environment.sh first}"
: "${INSIGHTS_CLIENT_SECRET:?source docs/dev-environment.sh first}"
: "${AAP_HOSTNAME:?source docs/dev-environment.sh first}"
: "${AAP_CONTROLLER_USERNAME:?source docs/dev-environment.sh first}"
: "${AAP_CONTROLLER_PASSWORD:?source docs/dev-environment.sh first}"

SNOW_ENDPOINT="${SN_HOST}/api/x_rhtpp_rh_webhook/flow_templates_for_red_hat_insights"
PINNED_CVE="${1:-}"   # optional: pass a specific CVE-ID as first argument

# ── Step 1: Get provisioned host from AAP inventory ──────────────────────────
echo "[1/5] Looking up provisioned host from AAP inventory..."
VM_HOSTNAME=$(curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  "${AAP_HOSTNAME}/api/controller/v2/hosts/?inventory__name=lightspeed-patching" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['results']; print(r[0]['name'] if r else '')")

if [ -z "$VM_HOSTNAME" ]; then
  echo "ERROR: No host found in lightspeed-patching inventory. Is the VM provisioned?"
  exit 1
fi
echo "  Host: ${VM_HOSTNAME}"

# ── Step 2: Obtain Insights bearer token ─────────────────────────────────────
echo "[2/5] Obtaining Insights bearer token..."
INSIGHTS_TOKEN=$(curl -s -X POST \
  "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=${INSIGHTS_CLIENT_ID}" \
  -d "client_secret=${INSIGHTS_CLIENT_SECRET}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# ── Step 3: Get Insights inventory_id for the host ───────────────────────────
echo "[3/5] Querying Insights inventory for ${VM_HOSTNAME}..."
INVENTORY_RESP=$(curl -s -H "Authorization: Bearer ${INSIGHTS_TOKEN}" \
  "https://console.redhat.com/api/inventory/v1/hosts?display_name=${VM_HOSTNAME}")

INVENTORY_ID=$(echo "$INVENTORY_RESP" | python3 -c "
import sys,json
r=json.load(sys.stdin)['results']
print(r[0]['id'] if r else '')
")

if [ -z "$INVENTORY_ID" ]; then
  echo "ERROR: Host '${VM_HOSTNAME}' not found in Insights inventory."
  echo "  It may still be syncing. Wait a few minutes and retry."
  exit 1
fi
echo "  Insights inventory_id: ${INVENTORY_ID}"

# ── Step 4: Find a CVE with known exploit ────────────────────────────────────
echo "[4/5] Querying Insights for CVEs with known exploits..."

if [ -n "$PINNED_CVE" ]; then
  # User pinned a specific CVE — fetch its details
  CVE_RESP=$(curl -s -H "Authorization: Bearer ${INSIGHTS_TOKEN}" \
    "https://console.redhat.com/api/vulnerability/v1/systems/${INVENTORY_ID}/cves?search=${PINNED_CVE}&limit=1")
else
  # Prefer CVEs with known exploits; fall back to highest CVSS if none flagged yet
  CVE_RESP=$(curl -s -H "Authorization: Bearer ${INSIGHTS_TOKEN}" \
    "https://console.redhat.com/api/vulnerability/v1/systems/${INVENTORY_ID}/cves?filter%5Bknown_exploit%5D=1&sort=-cvss3_score&limit=1")
  COUNT=$(echo "$CVE_RESP" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null)
  if [ "${COUNT:-0}" = "0" ]; then
    echo "  (no known-exploit CVEs yet — falling back to highest CVSS)"
    CVE_RESP=$(curl -s -H "Authorization: Bearer ${INSIGHTS_TOKEN}" \
      "https://console.redhat.com/api/vulnerability/v1/systems/${INVENTORY_ID}/cves?sort=-cvss3_score&limit=1")
  fi
fi

CVE_DATA=$(echo "$CVE_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d.get('data',[])
if not r:
    print('NONE|||')
    sys.exit(0)
a=r[0].get('attributes',{})
cve_id=r[0].get('id','')
cvss=a.get('cvss3_score','') or a.get('cvss2_score','') or '7.0'
has_rule=str(a.get('rule_id','') != '').lower()
print(f'{cve_id}|{cvss}|{has_rule}')
")

CVE_ID=$(echo "$CVE_DATA" | cut -d'|' -f1)
CVSS_SCORE=$(echo "$CVE_DATA" | cut -d'|' -f2)
HAS_RULE=$(echo "$CVE_DATA" | cut -d'|' -f3)

if [ "$CVE_ID" = "NONE" ] || [ -z "$CVE_ID" ]; then
  echo "ERROR: No CVEs found for this host in Insights."
  exit 1
fi
echo "  CVE: ${CVE_ID}  CVSS: ${CVSS_SCORE}  has_rule: ${HAS_RULE}"

# ── Step 5: POST the vulnerability payload to ServiceNow ─────────────────────
echo "[5/5] POSTing vulnerability payload to ServiceNow..."
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%6NZ")

PAYLOAD=$(python3 -c "
import json
payload = {
    'version': 'v1.1.0',
    'bundle': 'rhel',
    'application': 'vulnerability',
    'event_type': 'any-cve-known-exploit',
    'timestamp': '${TIMESTAMP}',
    'context': {
        'inventory_id': '${INVENTORY_ID}',
        'display_name': '${VM_HOSTNAME}',
        'host_url': 'https://console.redhat.com/insights/inventory/${INVENTORY_ID}'
    },
    'events': [{
        'metadata': {},
        'payload': {
            'reported_cve': '${CVE_ID}',
            'cvss_score': ${CVSS_SCORE:-7.0},
            'has_rule': '${HAS_RULE:-false}' == 'true',
            'known_exploit': True,
            'impact_id': 5
        }
    }],
    'org_id': '${RH_ORG_ID}'
}
print(json.dumps(payload, indent=2))
")

HTTP_CODE=$(curl -s -o /tmp/snow_response.json -w "%{http_code}" \
  -X POST \
  -u "rh_insights_integration:${RH_INSIGHTS_INTEGRATION_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${SNOW_ENDPOINT}")

echo ""
echo "  HTTP response: ${HTTP_CODE}"

if [[ "$HTTP_CODE" == "2"* ]]; then
  echo ""
  echo "✓ Payload accepted by ServiceNow."
  echo "  CVE ${CVE_ID} sent for host ${VM_HOSTNAME}"
  echo "  Check ServiceNow for a new incident from 'rh_insights_integration'."
else
  echo "  Response body:"
  cat /tmp/snow_response.json 2>/dev/null || true
  echo ""
  echo "✗ Unexpected response. Check credentials and endpoint."
  exit 1
fi
