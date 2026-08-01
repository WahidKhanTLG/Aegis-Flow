# Namespace Readiness Standard

**Status:** Active standard for all new development
**Decision (AF-20):** Namespace application is **deferred**. Development continues in the unmanaged org `Aegis Flow_WA_Dev`; a separate packaging org is reserved for when the managed package is generated.
**Therefore:** all code written from today must be namespace-safe, so the migration is a no-op rather than a rewrite.

---

## Why this matters

When the package acquires a namespace (say `aegisflow`), every custom object, field, and platform event gains a prefix:

| Today | After namespace |
|---|---|
| `Error_Log__c` | `aegisflow__Error_Log__c` |
| `Error_Log__c.Correlation_Id__c` | `aegisflow__Error_Log__c.aegisflow__Correlation_Id__c` |
| `/event/Aegis_User_Alert__e` | `/event/aegisflow__Aegis_User_Alert__e` |

Anything that names these as a **raw string** breaks silently at runtime. Anything that resolves them through **schema** keeps working untouched.

---

## Baseline: current violations

Scanned July 27, 2026. Small and very fixable — worth clearing before the codebase grows.

| Location | Count | Risk |
|---|---|---|
| `lwc/aegisHeadlessMonitor/aegisHeadlessMonitor.js:12` | 1 | **High** — `const CHANNEL = '/event/Aegis_User_Alert__e'` |
| `lwc/developerEscalationViewer/developerEscalationViewer.html` | 7 | **High** — raw `field-name` attributes |
| `lwc/adminErrorConsole/adminErrorConsole.js:15-18` | 4 | Medium — datatable `fieldName` strings |
| `classes/AEIR_RetentionScheduler.cls:5` | 1 | Medium — `Object_Name__c = 'Error_Log__c'` in SOQL |
| `classes/AEIR_AdminConsoleController.cls:13-14` | 2 | Low — dynamic SOQL `WHERE` fragments |
| **`@salesforce/schema` imports across all LWC** | **0** | No component currently uses the safe pattern |

The empApi channel is the one to fix first: if it breaks, the entire real-time notification flow goes silent with no error.

---

## Apex

### Do

```apex
// Schema-derived names — namespace applied automatically
String objectName = Error_Log__c.SObjectType.getDescribe().getName();
String fieldName  = Error_Log__c.Correlation_Id__c.getDescribe().getName();

// Typed SOQL needs no strings at all — strongly preferred
List<Error_Log__c> logs = [SELECT Id, Correlation_Id__c FROM Error_Log__c WHERE Status__c = 'New'];

// Platform event channel for empApi, derived not typed
String channel = '/event/' + Aegis_User_Alert__e.SObjectType.getDescribe().getName();
```

### Don't

```apex
// Breaks under a namespace
SObject o = Schema.getGlobalDescribe().get('Error_Log__c').newSObject();
String soql = 'SELECT Id FROM Error_Log__c WHERE Correlation_Id__c = :cid';
```

### Notes specific to this codebase

- **`Schema.getGlobalDescribe()` keys are namespaced.** `AEIR_RemediationOrchestrator` line 35 looks up `gd.containsKey(req.objectApiName)`. That is *correct* today because `objectApiName` comes from `Remediation_Action_Setting__mdt`, which will itself be namespaced after packaging — the two stay consistent. Leave it, but do not copy the pattern with a literal.
- **Custom metadata that stores API names must be reviewed at packaging time.** `Remediation_Action_Setting__mdt.Object__c`, `Retention_Policy__mdt.Object_Name__c`, and `Context_Field_Setting__mdt` all hold API names as data. Spec §16.2 warns that packaged CMDT keys cannot be renamed after release — decide before the first managed release whether these store bare or namespaced names.
- **`with sharing` and FLS checks are unaffected** by namespacing; no action needed.

---

## LWC

### Do

```javascript
import CORRELATION_ID from '@salesforce/schema/Error_Log__c.Correlation_Id__c';
import ERROR_LOG_OBJECT from '@salesforce/schema/Error_Log__c';

// Use .fieldApiName / .objectApiName wherever a string is required
const column = { label: 'Correlation ID', fieldName: CORRELATION_ID.fieldApiName };
```

```html
<lightning-record-view-form object-api-name={errorLogObject}>
    <lightning-output-field field-name={correlationIdField}></lightning-output-field>
</lightning-record-view-form>
```

Expose the imported references as getters so the template never contains a literal.

### Don't

```javascript
const CHANNEL = '/event/Aegis_User_Alert__e';        // breaks
const cols = [{ fieldName: 'Severity__c' }];          // breaks
```

```html
<lightning-output-field field-name="Subject__c"></lightning-output-field>
```

### Platform event channels

There is no `@salesforce/schema` import for an event channel. Return it from Apex instead, derived from the describe:

```apex
@AuraEnabled(cacheable=true)
public static String getUserAlertChannel() {
    return '/event/' + Aegis_User_Alert__e.SObjectType.getDescribe().getName();
}
```

The LWC then awaits that value before calling `subscribe()`. This is the recommended fix for `aegisHeadlessMonitor.js:12`.

### Apex method imports are already safe

`import getOpenAlerts from '@salesforce/apex/AEIR_AegisHeadlessMonitorController.getOpenAlerts'` needs no change — the platform resolves the namespace for Apex imports automatically. Class names take a namespace prefix but the import syntax handles it.

---

## Agentforce and AI payloads

- **Never hand raw API names to the LLM as literals.** `AEIR_AgentforceGatewayService.buildPayload()` currently builds its map with stable *logical* keys (`correlationId`, `objectApiName`, `recordId`) rather than API names — that is the right pattern. Keep it.
- Where a field API name genuinely must appear in a prompt, derive it via `getDescribe().getName()` at build time.
- **Action keys are a public contract.** `safeRemediationActionKey` values such as `UPDATE_ACCOUNT_TAX_CODE` are matched server-side against `Remediation_Action_Setting__mdt`. Per §16.2 these must not be renamed after release. They are namespace-independent by design — keep them logical, never derive them from an API name.
- The server must keep rejecting unknown action keys (§10.3). Namespacing does not change this, but it does mean the rejection path must not compare against hardcoded strings.

---

## Pre-migration checklist

Run before generating the first namespaced package:

1. `grep -rnE "['\"][A-Za-z_]+__(c|e)" force-app/main/default/lwc/` returns nothing.
2. `grep -rn "/event/" force-app/main/default/lwc/` returns nothing.
3. No `Schema.getGlobalDescribe().get('<literal>')` in Apex.
4. No dynamic SOQL built from literal `__c` names.
5. Decide bare-vs-namespaced storage for API names held in custom metadata (see Apex notes).
6. Deploy to the packaging org and run the full Apex + Jest suite there, not just in the unmanaged org.

Items 1–4 are cheap to enforce and worth adding to CI once AF-06 brings in Jest tooling.
