# ServiceNow Business Rules — aap.lightspeed.patching

Business Rules drive the AAP EDA integration. Each SE creates their own BR +
Outbound REST Message pair scoped to CIs they manage (`managed_by` on the CI).

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

## BR 2 — CVE Incident → EDA (per-SE, scoped by CI managed_by)

Each SE creates their own BR + Outbound REST Message pair. The BR fires when
an incident is created against a CI the SE manages (`managed_by` dot-walk).
This replaces the earlier "Phase 5 pending" approach — no need to filter on
caller/category/custom field; the CI ownership is the scope.

### Harris - Inc (Tony Harris — live)

**Table:** `incident`
**When:** After insert
**Filter Condition:**
```
cmdb_ci.managed_by=94ac108687ff925064a055383cbb3519^state=1^EQ
```
(CI managed by Tony Harris AND incident state = New)

**Outbound REST Message:** `Harris - Lightspeed EDA Event Stream`
**System Property:** `harris.eda_event_stream_token`

#### Script (Advanced → Script field)

```javascript
(function executeRule(current, previous) {
  var REST_MESSAGE_NAME = 'Harris - Lightspeed EDA Event Stream';
  var EVENT_NAME = 'CVE_INCIDENT';

  try {
    function clean(v) { return (v == null) ? v : String(v).trim(); }

    var json = { event: EVENT_NAME };
    if (current.number)            json.number            = clean(current.number.getDisplayValue());
    if (current.sys_id)            json.sys_id            = current.sys_id.toString();
    if (current.state)             json.state             = clean(current.state.getDisplayValue());
    if (current.short_description) json.short_description = clean(current.short_description.getValue('short_description'));
    if (current.description)       json.description       = clean(current.description.getValue('description'));
    if (current.impact)            json.impact            = clean(current.impact.getDisplayValue());
    if (current.urgency)           json.urgency           = clean(current.urgency.getDisplayValue());
    if (current.priority)          json.priority          = clean(current.priority.getDisplayValue());
    if (current.category)          json.category          = clean(current.category.getDisplayValue());

    if (current.cmdb_ci) {
      json.cmdb_ci        = clean(current.cmdb_ci.getDisplayValue());
      json.cmdb_ci_sys_id = current.cmdb_ci.toString();
    }

    if (current.caller_id) {
      var caller = current.caller_id.getRefRecord();
      if (caller.isValidRecord()) json.caller = caller.getValue('email');
    }

    var r = new sn_ws.RESTMessageV2(REST_MESSAGE_NAME, 'POST');
    r.setRequestHeader('Content-Type', 'application/json');
    r.setRequestHeader('Authorization', 'Bearer ' + gs.getProperty('harris.eda_event_stream_token'));
    r.setRequestBody(JSON.stringify(json));
    r.setTimeout(10000);
    var resp = r.execute();
    gs.info('Harris INC EDA trigger [' + json.number + '] -> HTTP ' + resp.getStatusCode());
  } catch (ex) {
    gs.error('Harris INC EDA trigger failed: ' + ex.message);
  }
})(current, previous);
```

### Creating a new SE's BR (template)

1. Look up the SE's `sys_id` in `sys_user` (user_name field).
2. Create an **Outbound REST Message** (`sys_rest_message`):
   - Name: `<SE> - Lightspeed EDA Event Stream` (≤40 chars)
   - Endpoint: the SE's AAP EDA event stream URL
   - Auth: No authentication (bearer token injected in BR script)
   - Add a POST method (inherits from parent)
3. Create a **System Property** (`sys_properties`):
   - Name: `<se>.eda_event_stream_token`
   - Value: the bearer token matching the SE's AAP EDA event stream credential
4. Create the **Business Rule** (`sys_script`):
   - Table: `incident`, When: after, Insert: true, Update: false
   - Filter: `cmdb_ci.managed_by=<SE sys_id>^state=1^EQ`
   - Script: copy the template above, update `REST_MESSAGE_NAME` and
     `gs.getProperty()` to the SE's names

---

## Outbound REST Messages

Named REST messages decouple the endpoint URL from the BR script. Each SE
creates one for their AAP instance. The BR references it by name via
`new sn_ws.RESTMessageV2('<name>', 'POST')`.

| Name | Endpoint | SE | sys_id |
|------|----------|----|--------|
| `Ames - DC1.Azure EDA Event Stream` | AAP EDA event stream (dc1.azure) | Eric Ames | `1c00b1f887ab56106a094046cebb3547` |
| `Harris - Lightspeed EDA Event Stream` | PLACEHOLDER (Tony fills in) | Tony Harris | `8e78c6b487e5071064a055383cbb3556` |

> **40-char limit** on the `name` field in `sys_rest_message`. Keep names short.

---

## System Properties

| Property | Purpose | SE |
|----------|---------|----|
| `dc1.eda_event_stream_url` | EDA event stream URL (BR 1 inline pattern) | Eric Ames |
| `dc1.eda_event_stream_token` | Bearer token (BR 1 + Ames catalog BRs) | Eric Ames |
| `harris.eda_event_stream_token` | Bearer token (Harris - Inc BR) | Tony Harris |

---

## Incident table states

| Value | Label |
|-------|-------|
| 1 | New |
| 2 | In Progress |
| 3 | On Hold |
| 6 | Resolved |
| 7 | Closed |
| 8 | Canceled |

---

## Testing BRs

1. **BR 1:** Place a test order in the SNow catalog → verify in AAP that the provision workflow launched
2. **BR 2 (Harris - Inc):** Run `playbooks/introduce_cve.yml` against a host whose CI has `managed_by=Tony Harris` → verify INC is created → verify Tony's EDA receives the event
3. Check **System Log → All** in ServiceNow for `gs.info` output:
   - BR 1: `DC1.Azure EDA trigger [RITM...] -> HTTP 200`
   - BR 2: `Harris INC EDA trigger [INC...] -> HTTP 200`
