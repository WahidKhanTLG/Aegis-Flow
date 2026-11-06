# Business Scenario Coverage

Scope: sales, service, custom objects and integrations. Managed packaging is excluded by the
user's current instruction. A business scenario is supported through its Salesforce execution
surface and explicit configuration; this is not a claim to understand every customer's rules
or to intercept every native Salesforce error.

## Application and process coverage

| Business process or failure | Implementation | Required configuration / boundary | Regression evidence |
| --- | --- | --- | --- |
| Sales record missing required data | Flow/Apex/custom-form capture; Missing Data diagnosis | Instrument fault paths or use the Aegis form; whitelist any proposed correction | CrossBusinessScenarioTest, CoreTest, UI-save Jest |
| Service record duplicate or invalid value | Duplicate, picklist and length rules; captured evidence and user guidance | Correct mappings or values; no automatic merge/truncation | CrossBusinessScenarioTest, UI-save Jest |
| Custom-object automation failure | Object-independent capture, context and classification | Configure accessible context fields and customer automation instrumentation | CrossBusinessScenarioTest, CaptureRetryBulkTest |
| Service/custom-object approved correction | Generic metadata whitelist, explicit confirmation, CRUD/FLS/sharing and atomic audit | Register the exact object/field/action; enable governed remediation intentionally | CrossBusinessScenarioTest, ReleaseSecurityTest, RemediationControllerTest |
| Flow faults before transaction rollback | Publish-immediate capture event, packaged fault subflow; optional rollback-safe invocable path | Use the subflow or varRollbackSafe=true when the caller can roll back; asynchronous paths return no immediate log ID | CaptureRetryBulkTest, BulkEntryPointTest |
| Batch/Queueable/async failure | Batch error subscriber, finalizer pattern and scheduled job monitor | Batch opt-in/finalizer instrumentation; configured poller for uninstrumented async jobs | BatchApexErrorTriggerTest, AsyncLifecycleTest, MonitorAndTelemetryTest |
| Standard Salesforce form/Lead Convert failure | Manual screen report; custom Aegis form captures its own save errors | Native platform forms/conversion are not universally intercepted | Monitor and UI-save Jest |
| Integration timeout/throttling/unavailable service | API/guard capture; integration classifications and sanitized evidence | Caller instrumentation; retries require known idempotent business logic and backoff | CrossBusinessScenarioTest, ReconciledFeaturesTest |
| Integration authentication/storage/configuration issue | Explicit administrator guidance; no blind retry | Reconnect Named Credential or fix capacity/mapping before retrying | CrossBusinessScenarioTest |
| Registered synchronous business retry | Bulk-prefetched attempts/logs, maximum 20 requests, unique attempt audit and backoff | Execute Retry permission plus audit CRUD/FLS; handler enforces business access and idempotency | CaptureRetryBulkTest |
| Synchronous retry handler fails after mutation | Per-handler rollback and atomic audit finalization | Handlers must have bounded cost and no irreversible external side effects | CaptureRetryBulkTest |
| Outbound integration callout retry | Connector outbox/job has separate asynchronous delivery and explicit bounded retry | Synchronous legacy retry handlers cannot make HTTP callouts after audit DML; use an asynchronous integration design | ConnectorDeliveryTest |
| User receives the correct alert | Minimal event hints, uncached canonical resolution and ownership/status/expiry checks | Assign appropriate Aegis role and host the monitor; startup/reload reads recover durable notices missed by streaming | NotificationBoundaryTest, monitor and card Jest |
| Forged, expired, dismissed or stale streaming hint | Ignored unless durable authorized state resolves | Consumers cannot publish user-alert events; shared event contains no diagnostic text | NotificationBoundaryTest, monitor Jest |
| Manual help without a captured error | Functional Get Help session, deterministic guidance, explicit escalation | User description and permitted context; malformed input rejected | InputBoundaryTest, GetHelpPanel Jest |
| Known rule diagnosis without AI | Deterministic classification and stored diagnosis | Rule metadata, no AI licensing required | CoreTest, CrossBusinessScenarioTest |
| End-user diagnosis and integration processing | Own-record user-mode gate; curated result writes; separate processor capability for visible affected-user records | Integration principal receives Process Diagnostics; sensitive-context export stays separately authorized | DiagnosisPayloadTest |
| Large diagnostic evidence | Valid bounded JSON, Unicode-safe text limits and explicit omitted-context markers | Original evidence retains its own access and retention policy; enrichment evidence capped at 12,000 characters | DiagnosisPayloadTest |
| Optional Agentforce enrichment | Persist fallback first; bounded queueable calls configured Agent API; strict output validation | Dedicated read-only agent, OAuth Named/External Credential and explicit feature/config enablement | AgentforceClientTest with HttpCalloutMock |
| Agentforce unavailable, malformed, throttled or unsafe output | Preserve fallback; record failed/skipped enrichment; execute no returned action | No uncontrolled API retry loop; maximum three enrichments per transaction | AgentforceClientTest |
| Email/Case escalation | Authorized evidence package and delivery audit; functional confirmation UI | Configure company recipients or administrator fallback; Case CRUD/FLS | EscalationBulkTest, escalation/GetHelp Jest |
| Slack/Teams/Jira/GitHub/webhook escalation | Named Credential adapters, durable queue/audit and bounded explicit delivery retry | Approved channel target, endpoint and OAuth scopes; CONNECTOR_EXTENSIONS enabled | ConnectorDeliveryTest with HttpCalloutMock |
| External support console or agent client | Scoped REST errors/incidents/context/notifications; explicit help/dismiss/escalate actions | Headless permission plus diagnostic operation CRUD/FLS and record access | HeadlessApiTest |
| MCP client | Five Salesforce reads, two offline scoped knowledge tools and MCP resources; three optional confirmed writes | Explicit customer selection; reviewed provenance; org auth only for live reads | Native Node security/stdio tests and dated live acceptance |
| Unknown customer-specific failure | Preserve evidence and escalate without inventing a correction | Add customer-specific rules and approved handlers when requirements are known | CrossBusinessScenarioTest |
| Credentials or sensitive values in any business context | JSON-aware recursive and text masking, preserved structure and safe failure | Maintain Sensitive_Field rules; do not configure identity/key regexes as value-only rules | ReleaseSecurityTest, CrossBusinessScenarioTest |
| Event delivery volume | Explicit maximum 200-event subscriber configurations instead of the platform default 2,000 | Administrator selects the running principal; tune lower for large evidence and verify customer automation cost | Metadata audit and Salesforce validation |
| Bulk/null/malformed/duplicate input | Ordered results, bounds and explicit per-item failures where supported | Respect documented batch/object/payload limits; callers inspect success/status | CaptureRetryBulkTest, InputBoundaryTest |

## Acceptance process

1. Identify each customer process's actual surface: Flow, Apex, async, custom UI or integration.
2. Register the context field allowlist and classification/routing rules. Keep personal or
   regulated fields out unless there is an approved operational reason to include them.
3. Grant role-specific diagnostic permissions. Recovery is separate from diagnostic reading.
4. Demonstrate a representative failure, durable capture, correct user notification, guidance
   and escalation. Include a background failure while no utility browser is open.
5. For every proposed write/retry, demonstrate denied permission, missing confirmation,
   unknown action, duplicate request, invalid input, failure rollback and audit persistence.
6. Exercise the expected volume and existing customer automation. Arbitrary third-party
   triggers/Flows can consume limits beyond the framework's own budget.
7. For external services, test the actual approved Named Credential and target in an authorized
   nonproduction environment. HTTP mocks validate code paths, not a tenant's credentials,
   licensing, agent instructions, remote delivery or recipient configuration.

## Verification status

The November 3 development deployment installed 551 components and passed 283 Apex tests;
the subsequent masked-telemetry patch passed all 284. The final setup-health follow-up passed
all 286; local checks passed 105 LWC and 30 MCP tests. Four synchronous diagnostic scenarios
and the separate real approved-Flow recovery fixture passed with rollback cleanup. The
[dated verification record](../output/development/2026-11-03/verification.json) records final
local test counts, committed-event, rendered UI, MCP and source comparison evidence.

ABC printing/collection/shipment and SoCal crew-day/checklist/estimate evidence are curated
with explicit proposed checks in [the MCP corpus](../integrations/mcp/knowledge/README.md).
This source review did not connect either customer org, execute their business operations or
register an automatic repair. Their actual process postconditions and volume acceptance
remain customer-specific. Optional external services require approved credentials and live
tenant acceptance if selected; they remain disabled in this deployment.
