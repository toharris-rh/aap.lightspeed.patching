# ServiceNow Business Rules — aap.lightspeed.patching

Two Business Rules drive the AAP EDA integration.

---

## BR 1 — Catalog Order → EDA (Provision workflow)

**Table:** `sc_req_item`  
**When:** After insert  
**Condition:** Short description is `Lightspeed Patching - Request RHEL VM`  
**Name:** `Lightspeed Patching - Fire EDA on Catalog Order`

### Filter Conditions

```
Short description  is  Lightspeed Patching - Request RHEL VM
AND
Requested for      is one of  [your SE user accounts — see shared-instance caveat]
```

> **Shared-instance caveat:** This ServiceNow instance is shared by ~33 SEs.
> Add an OR "Requested for is \<user\>" for each SE who will place orders.
> Currently: Eric Ames, Tony Harris, AAP ServiceAccount.

### Script (Advanced → Script field)

```javascript
(function executeRule(current, previous) {
    var endpoint = gs.getProperty('dc1.eda_event_stream_url'); // set in System Properties
    var token = gs.getProperty('dc1.eda_event_stream_token');  // set in System Properties

    var r = new sn_ws.RESTMessageV2();
    r.setEndpoint(endpoint);
    r.setHttpMethod('POST');
    r.setRequestHeader('Content-Type', 'application/json');
    r.setRequestHeader('Authorization', 'Bearer ' + token);

    var payload = {
        short_description: current.short_description.toString(),
        number: current.number.toString(),
        sys_id: current.sys_id.toString(),
        vm_size_tier: current.variables.vm_size_tier.toString() || 'medium'
    };

    r.setRequestBody(JSON.stringify(payload));

    var response = r.execute();
    gs.info('Lightspeed Patching EDA response: ' + response.getStatusCode());
})(current, previous);
```

### System Properties (set once per instance)

| Property | Value |
|----------|-------|
| `dc1.eda_event_stream_url` | Your AAP EDA event stream URL (from AAP → Automation Decisions → Event Streams) |
| `dc1.eda_event_stream_token` | Bearer token (same value as `EDA_EVENT_STREAM_TOKEN` in `docs/dev-environment.sh`) |

---

## BR 2 — Insights INC → EDA (Remediate CVE workflow)

**Table:** `incident`  
**When:** After insert  
**Name:** `Lightspeed Patching - Fire EDA on Insights Incident`

> ⚠️ **PENDING (Tony, Phase 5):** The exact filter condition depends on how the
> Red Hat Insights → ServiceNow native integration populates the INC record.
> Once Tony validates the payload (what field identifies the INC as
> Insights-originated), update the filter and script below.

### Candidate Filter Conditions (validate one)

```
# Option A — if Insights sets a caller_id
Caller ID        is  Red Hat Insights

# Option B — if Insights sets a category
Category         is  software

# Option C — if Insights sets a custom field
u_source         is  Red Hat Insights
```

### Script (Advanced → Script field)

```javascript
(function executeRule(current, previous) {
    var endpoint = gs.getProperty('dc1.eda_event_stream_url');
    var token = gs.getProperty('dc1.eda_event_stream_token');

    var r = new sn_ws.RESTMessageV2();
    r.setEndpoint(endpoint);
    r.setHttpMethod('POST');
    r.setRequestHeader('Content-Type', 'application/json');
    r.setRequestHeader('Authorization', 'Bearer ' + token);

    var payload = {
        // Marker field so the EDA rulebook (servicenow_incident_events.yml)
        // can distinguish this from a catalog order event.
        event_type: 'insights_incident',
        number: current.number.toString(),
        sys_id: current.sys_id.toString(),
        short_description: current.short_description.toString(),
        category: current.category.toString(),
        // TODO (Tony - Phase 5): add the confirmed Insights-source field here
        // e.g. cmdb_ci: current.cmdb_ci.name.toString()
    };

    r.setRequestBody(JSON.stringify(payload));

    var response = r.execute();
    gs.info('Lightspeed Patching EDA incident response: ' + response.getStatusCode());
})(current, previous);
```

### Allowlist note

Add the same "Requested for" / "Assigned to" allowlist used in BR 1 if needed
to prevent other SEs' Insights INC tickets from triggering remediation runs
against your demo hosts.

---

## Testing BRs

1. **BR 1:** Place a test order in the SNow catalog → verify in AAP that the provision workflow launched
2. **BR 2 (after Phase 5):** Run `playbooks/introduce_cve.yml`, wait for Insights INC → verify EDA fires → remediate workflow launches
3. Check **System Log → All** in ServiceNow for `gs.info` output from both BRs
