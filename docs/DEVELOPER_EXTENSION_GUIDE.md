# Developer Extension Guide

## Capturing Apex errors

```apex
try {
    // customer business logic
} catch (Exception ex) {
    AEIR_ErrorCaptureService.ErrorInput input = new AEIR_ErrorCaptureService.ErrorInput();
    input.sourceType = 'Apex Class';
    input.sourceName = 'CustomerService';
    input.objectApiName = 'Account';
    input.recordId = accountId;
    input.actionName = 'Customer action name';
    input.originalMessage = ex.getMessage();
    input.stackTrace = ex.getStackTraceString();
    input.contextJson = JSON.serialize(contextMap);
    AEIR_ErrorCaptureService.publish(input);
    throw ex;
}
```

## Adding a remediation action

1. Create `Remediation_Action_Setting__mdt` record.
2. Set `Action_Key__c`, `Object__c`, `Field__c`, `Requires_Confirmation__c`, and `Active__c`.
3. Call `AEIR_RemediationOrchestrator.execute` or expose the invocable in a separately governed interactive workflow. Never register write actions on the dedicated read-only enrichment agent.

## Adding a retry handler

```apex
public with sharing class MyRetryHandler implements AEIR_RetryHandler {
    public AEIR_RetryOrchestrationService.RetryResult retry(AEIR_RetryOrchestrationService.RetryRequest request) {
        AEIR_RetryOrchestrationService.RetryResult result = new AEIR_RetryOrchestrationService.RetryResult();
        // Implement and verify the actual authorized, idempotent customer operation here.
        // Report failure until the operation has actually completed.
        result.success = false;
        result.message = 'No customer-specific retry operation has been implemented.';
        return result;
    }
}
```

Then create `Retry_Handler__mdt` with `Apex_Class__c = MyRetryHandler`.


## Recovery contracts

The synchronous retry service supports at most 20 inputs in one transaction, prefetches its
registry and state, requires `AEIR_Execute_Retry`, and writes audits in user mode. Assign the
permission with appropriate Retry Attempt CRUD/FLS, currently the Product Admin or Integration
User role. Arbitrary registered handlers must enforce target-record CRUD/FLS/sharing, have
bounded governor cost, and be idempotent. They run after audit DML/savepoints, so they must not
perform HTTP callouts or irreversible external side effects. Use an asynchronous outbox design
for external business operations. The shipped tax handler deliberately reports failure until
replaced by genuine customer logic.

Remediation requires the feature flag, Execute Remediation permission, active exact action
whitelist, confirmation where configured and target CRUD/FLS/sharing. Target changes roll back
if the required audit cannot be saved. Both remediation invocables have a 20-input limit and
reject oversized batches before applying changes.

`AEIR_CaptureFlowFaultAction` retains its synchronous result contract. For a rollback-prone
caller, set `varRollbackSafe=true`, or use `Aegis_Error_Capture_Fault_Subflow`. The asynchronous
publication returns a correlation and publication status, with no fabricated immediate error
record ID. Later subscribers persist the evidence.

## Headless API

Base path: `/services/apexrest/aegis-flow/v1/operations/`.

| Method | Resource | Contract |
| --- | --- | --- |
| GET | capabilities | Supported resources, actions and current feature flags |
| GET | errors | Current user's sanitized errors; bounded filters and keyset cursor |
| GET | incidents | Current user's accessible incidents; bounded keyset cursor |
| GET | context | Typed `errorLogId`; authorized sanitized diagnostic context |
| GET | notifications | Current user's unexpired new notices |
| POST | help | `description`, optional valid object-consistent `recordId`, `objectApiName`, `pageUrl`; snapshots separately enforce business-record access |
| POST | dismiss | Current user's active `correlationId` |
| POST | escalate | Current user's active `correlationId`; may deliver to configured recipients |

Assign `AEIR_Headless_User` together with the appropriate Aegis role. The custom API permission
alone does not grant diagnostic object/field access. Requests enforce operation-specific access
and canonical ownership. `scope=visible` is supported for errors, incidents and context; it
requires Sensitive Context permission and does not bypass sharing or field access.
Notifications and mutation operations reject that scope. Error lists default to seven days,
maximum 30; page sizes default to 25, maximum 100. Cursors expire after 60 minutes. Use the
returned opaque `nextCursor` with the same page size and filters.
Never synthesize a cursor or reuse another user's cursor. Payload and cursor bounds are checked.
The API returns generic denied/invalid messages, rather than raw exceptions or credentials.

## MCP stdio bridge

Run `node integrations/mcp/server.mjs` with Node 22 or later and an existing authorized
Salesforce CLI alias in `AEGIS_TARGET_ORG`. No additional runtime dependencies are required.
The bridge reads connection information from CLI into short-lived process memory; it never
prints an access token. Alternatively, an administrator can inject both `AEGIS_INSTANCE_URL`
and `AEGIS_ACCESS_TOKEN` through a secure process environment. Do not commit tokens or put
these values in a client configuration file.

The supported MCP handshake revisions are 2025-11-25, 2025-06-18 and 2025-03-26. Newer clients
must support the documented fallback to the initialize lifecycle; a direct modern-only client
is not supported by this bridge. Stdout carries JSON-RPC only. The process serves a fixed set
of Salesforce diagnostic routes, rejects arbitrary endpoints and follows no HTTP redirects.

Default tools are `get_capabilities`, `find_recent_errors`, `list_incidents`,
`list_notifications`, and `get_error_context`, plus offline `search_knowledge` and
`get_knowledge`. MCP resources expose only the allowlisted corpus selected for the process;
customer knowledge requires `AEGIS_KNOWLEDGE_CUSTOMERS`. See the
[MCP guide](../integrations/mcp/README.md) and its ingestion/provenance instructions. Set `AEGIS_ALLOW_WRITES=true` only for an
approved client to expose `create_help_session`, `dismiss_notification`, and
`create_escalation`; each requires `confirmed: true`. This does not replace client-side user
approval or Salesforce authorization. Diagnostic text is untrusted evidence, not instructions.
Mutations are not automatically retried after network errors.

Example client process configuration (replace paths and alias with actual approved values):

```json
{
  "command": "node",
  "args": ["/absolute/path/to/Aegis-Flow/integrations/mcp/server.mjs"],
  "env": { "AEGIS_TARGET_ORG": "your-authorized-org-alias" }
}
```

Run offline bridge checks with `npm run test:mcp`; they include injected HTTP/CLI cases and
real spawned stdio without Salesforce credentials. They never contact Salesforce or send an
escalation. A separate authorized live client must verify the actual org connection.

## Optional Agentforce connection

Diagnosis authorizes a minimal user-mode record read before reading technical evidence or
writing a server-curated result. End users can diagnose their own accessible errors/sessions
without receiving arbitrary diagnosis-create or error-edit permissions. Support processing
of another affected user's visible records requires Sensitive Context or the separate
`AEIR_Process_Diagnostics` permission. Only the Integration User permission set includes the
processing permission by default. This dedicated runtime role has explicit View All Records
on errors, sessions and diagnoses so it can process affected-user-owned private records;
it has no Modify All Records grant on these objects. The processing permission itself grants
neither raw-context export nor record visibility. Limit this role to the approved service
identity; it is not an inbound-only or human end-user role.
The asynchronous enrichment job rechecks both its diagnosis and referenced parent access.
After those gates, private server persistence helpers write only curated diagnosis/status
results. Their elevated record-write context does not grant the caller direct edit access
to another user's records or authority over business data.

Stored diagnosis JSON is bounded using actual field lengths. Input JSON also follows the
12,000-character Agent API evidence ceiling; output JSON follows its 32,768-character field
limit. Large context/snapshot sections are omitted with explicit markers;
text truncation preserves valid JSON and Unicode. The original captured evidence remains
available under its existing permissions and retention policy.

`Agent_Connection__mdt.DEFAULT` ships inactive. `AI_DIAGNOSIS` also remains disabled.
Configure a Named Credential for the Salesforce Agent API host using an External Credential;
store only its developer name in `Named_Credential__c`. Set the activated diagnostic agent ID,
a message timeout, and Active only after reviewing its permissions and topics.

Use a dedicated **read-only diagnostic agent and principal**. `bypassUser=false` preserves the
configured token identity. Instructions to the model alone cannot prevent a remotely configured
agent from calling its own write actions, so do not register such actions on this agent.
The client starts a session, sends one sanitized diagnostic message, and ends the session.
It accepts only the expected typed diagnosis, confidence range and registered action keys;
returned recommendations never execute a remediation. Configure OAuth scopes and principal
access according to the current [Agent API setup](https://developer.salesforce.com/docs/ai/agentforce/guide/agent-api-get-started.html).

Deterministic diagnosis is persisted before queueing remote work. At most three optional
Agent API enrichments are admitted per transaction; excess work retains its deterministic
result and an explicit skipped reason. API failures, rejected responses and queue capacity
also retain that evidence. The mock tests prove the lifecycle and failure paths, not a live
agent's licensing, tenant configuration, reasoning quality or access boundaries.

## External escalation routes

Enable `CONNECTOR_EXTENSIONS` only after a tenant administrator approves the destinations.
Each outbound route uses `Named_Credential__c`, a validated nonsecret `Target__c` JSON object,
and (for a generic webhook) a safe relative `Endpoint_Path__c`. Tokens, signed webhook URLs,
and authentication query parameters belong in credential configuration, never route metadata
or a browser payload. Provider-specific paths are derived from validated target identifiers.

| Channel | Named Credential base | Example nonsecret target | Required capability |
| --- | --- | --- | --- |
| Webhook | Approved customer HTTPS service | Optional | Accept the versioned Aegis escalation JSON contract |
| Slack | `https://slack.com` | `{"channelId":"C1234567890"}` | OAuth `chat:write` to the approved channel |
| Teams | `https://graph.microsoft.com` | `{"teamId":"actual-team-id","channelId":"actual-channel-id"}` | Approved delegated `ChannelMessage.Send` identity |
| Jira Cloud | Approved Atlassian site | `{"projectKey":"OPS","issueTypeId":"10001"}` | Create issues in the approved project |
| GitHub Issues | `https://api.github.com` | `{"owner":"example-org","repo":"salesforce-errors"}` | Issues write permission for the approved repository |

Slack uses Web API authentication, not a secret incoming-webhook URL. Teams uses the Graph
channel-message API; migration-only application permissions are not a general posting identity.
The actual target IDs and OAuth permissions must be validated in the customer's environment.

The outbox records a durable claim before queueing. Delivery processes ten callouts per job,
with a finite 200-item initial limit and an explicit queue-depth budget. If continuation cannot
be admitted, delivered outcomes remain recorded and remaining items are marked Pending /
NotQueued for a new transaction. The job performs no database writes until its callouts finish.
The trusted worker reads internal technical fields without granting end users direct audit
access. It still enforces sharing and creator-or-approved-processor authority. Execution and
continuation must match the persisted claim's actual queueable job ID; superseded jobs cannot
send or reclaim the work.

`AEIR_ConnectorDeliveryJob.retryEscalations(ids)` provides privileged, explicit retries, with
at most three attempts and Retry-After enforcement. A timeout, ambiguous 2xx, HTTP 408 or 5xx
requires reconciliation before another POST; an Idempotency-Key header alone does not prove
that a destination deduplicates. No automatic retry is performed for an uncertain external
outcome. Inspect the durable Delivery Audit state and the destination before taking action.

Provider contracts: [Slack](https://docs.slack.dev/reference/methods/chat.postMessage/),
[Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/channel-post-messages?view=graph-rest-1.0),
[Jira](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/),
[GitHub](https://docs.github.com/en/rest/issues/issues#create-an-issue).

## Event subscriber execution and volume

Internal notice deduplication, completion updates and throttling history use scoped server
reads so a processor can maintain affected-user-owned notices. These operations are not
client actions. User-facing notification methods retain current-recipient and user-mode
access checks; the runtime role does not receive View All Records on notifications.

The application includes `PlatformEventSubscriberConfig` definitions with a maximum batch of
200 for its five event triggers. Salesforce's platform default is 2,000; the application does
not rely on that larger untested delivery batch. These definitions do not choose a customer
username. Before an authorized deployment, preserve any existing subscriber running-user
choice and configure an approved active integration principal with the required diagnostic
permissions. Email delivery from a platform-event subscriber requires a suitable configured
running user; the default Automated Process identity has no sender email.

In this org's check-only Apex validation, Automated Process could read the shared diagnostic
but its native custom-permission check remained false despite an isolated test assignment.
Tests therefore verify the actual event principal's authorization outcome and independently
exercise successful processing under a normal, natively authorized principal. Confirm the
actual configured running user's full event-to-diagnosis path during deployment acceptance;
do not assume that a default Automated Process subscription has the processing capability.

Larger evidence payloads and customer automation may require a smaller delivery batch and
additional capacity testing. Framework DML reserves cover its own transaction-control/audit
operations; they cannot predict the extra queries/writes of arbitrary customer triggers and
Flows. Regression tests separate framework overhead from the actual business handler cost.
Snapshot reads reserve ten SOQL queries for the caller. If a mixed-object batch or earlier
automation uses that capacity, each omitted snapshot returns a fixed `snapshotError` marker;
the diagnostic can continue with the captured source evidence.
See [Salesforce subscriber configuration](https://developer.salesforce.com/docs/platform/platform-events/guide/platform-events-trigger-config.html)
for running-user and batch changes, including subscription refresh behavior.

Flow coverage analysis compares captured history with observed failed interviews per Flow.
It deduplicates observed interview GUIDs and sums each Flow's gap independently. A matching
historical count for the same Flow is an estimate, not proof that every individual interview
has a corresponding capture. Use the shared `FLOWINT-<InterviewGuid>` correlation where
available and validate critical fault instrumentation with representative end-to-end runs.

## Debug-log evidence boundary

`AEIR_LogCollectorService` preserves its authorized link response and optionally fetches a
server-linked debug log body from the exact current org. Enable `Log_Connection.DEFAULT`
only after configuring an approved same-org Named Credential and principal access. Sensitive
Context permission or actual Modify All Data, a user-mode parent diagnostic read and a valid
server-stored debug-log reference are required. Client-supplied log IDs and cross-org endpoints
are rejected. The collector uses a size preflight and at most two GETs, bounds UTF-8 bytes
(including masking expansion), sanitizes the body and returns it ephemerally to the workspace.
It does not enable trace flags or persist the body in Salesforce Files. The default connection
is disabled; captured exceptions/context remain useful without it.

## Automatic diagnosis and affected-user evidence

`AUTO_DIAGNOSIS` enables deterministic diagnosis requests after durable capture. The optional
`AI_DIAGNOSIS` flag separately controls remote Agentforce enrichment and also retains its legacy
request behavior. `Agent_Diagnosis_Requested__e` publishes after commit so the processor can
read the parent; rollback-safe ingress `Error_Captured__e` remains publish-immediate.
Trusted server probes can set `CaptureOptions.notifyUser=false` and `requestDiagnosis=false`.

A privileged processor never creates a fresh business-record snapshot under its own access
for a different affected user's diagnosis payload. That payload explicitly reports
`OMITTED_DIFFERENT_AFFECTED_USER`; it can retain already captured, sanitized evidence. Same-user
fresh snapshots retain user-mode field/record checks. UI/headless context reads continue to
check the actual caller's permissions. Subscriber failure telemetry is also masked.

## Approved Flow recovery

The reusable `AEIR_ApprovedFlowRetryHandler` accepts only fixed server-built inputs, an exact
active registration/object/native custom permission and a typed success result for the same
target. See [Approved Flow recovery](APPROVED_FLOW_RECOVERY.md) for the reviewed Flow contract,
rollback/idempotency obligations and separate development-only acceptance fixture. Product
metadata includes no enabled customer business retry registration.

## Utility connection status and saved refresh

The utility treats streaming failures separately from user action failures. A refused optional
Flow stream has its own safe status; it does not imply that Aegis alerts, Help or dismissal
failed. Unknown transport errors remain visible without displaying raw EMP payloads. Only
unambiguously unrelated structured channels are ignored. A later valid owned Aegis wake-up
can clear a warning specific to that channel, while other warnings remain independent.

Refresh alerts performs a single-flight bounded read of saved unread notices; it does not
start polling, replay a write, or prove a streaming connection recovered. Fresh saved diagnosis
DTOs replace unchanged in-memory DTOs, while newer in-flight stream results and local dismissal
state win races. Initial unread retrieval excludes Viewed notices; canonical resolution can
still authorize an unexpired Viewed notice, and dismissal prevents future resolution.
