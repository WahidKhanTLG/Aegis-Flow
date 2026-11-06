# Aegis Flow Configuration Guide

## Development deployment

The November 3 deployment targets the verified Aegis development org under
`SyncBridge-Product`. The release manifest excludes the two original QA Opportunity Flows;
the separate `qa/approved-flow-retry` project is not a product dependency. See the
[dated verification record](../output/development/2026-11-03/verification.json) for actual
configuration and acceptance. Keep environment settings separate from portable defaults.

Assign role-specific permission sets. Headless clients need `AEIR_Headless_User` plus an
Aegis diagnostic role; that API entitlement grants no business object access. Recovery needs
its separate capability, exact metadata whitelist/registration and native target access.

## Event processing and diagnosis

Select an approved active event-processing user with the required diagnostic permissions,
including `AEIR_Process_Diagnostics`. Configure all five shipped event subscriber definitions
with that identity and the packaged batch size of 200. Portable source intentionally contains
no username. For an already running subscription, Salesforce documents suspension/resumption
to apply the cached configuration immediately; coordinate this service change and resume from
the earliest retained event. Verify the real execution identity and durable diagnosis result.

Enable `AUTO_DIAGNOSIS` for deterministic diagnosis after capture. Keep `USER_NOTIFICATIONS`
enabled for notices. `AI_DIAGNOSIS` controls optional remote enrichment; it is not required for
deterministic guidance. Diagnosis requests publish after the parent commits, while rollback-safe
capture ingress publishes immediately. The read-only health check and explicit rollback-cleaned
probe do not by themselves establish committed event delivery.

The development overlay enables AUTO_DIAGNOSIS and GOVERNED_REMEDIATION. The generic source
keeps both disabled for deliberate installation. Apply the intended overlay after a release;
do not assume deploying portable defaults preserves a customer's enabled feature settings.

## Escalation routing

Configure `Escalation_Route__mdt` with approved company destinations. DEFAULT_DEV_EMAIL and
DEFAULT_ADMIN_EMAIL use the effective setup/team/route/fallback resolver. Existing recipients
must be preserved unless an authorized administrator changes them.

Email and Case delivery are implemented. Optional Slack, Teams, Jira, GitHub and webhook
adapters use Named Credentials, explicit relative endpoints/targets and a durable delivery
audit/outbox. Keep CONNECTOR_EXTENSIONS disabled until the intended credential, principal,
tenant and test destination are approved. An uncertain remote outcome requires reconciliation;
do not blindly replay it. Live email/external delivery requires an approved test destination.

## Optional Agentforce enrichment

The optional Agent API client requires an approved dedicated **read-only** diagnostic agent,
Named/External Credential, principal access, correct agent ID and explicit Agent_Connection
and AI_DIAGNOSIS enablement. It retains deterministic fallback and validates bounded results;
it never executes a returned recommendation. Do not expose write, retry or escalation actions
to this enrichment agent. Separately governed interactive workflows can use the approved
invocable catalog under their own permission and confirmation boundary.

## Flow faults and business recovery

Connect the fault paths of each selected customer Flow to AEIR Capture Flow Fault or the
packaged fault subflow. Supply the actual source, object, record and correlation context.
For rollback-prone callers use the publish-immediate capture path. Show a friendly correlation
reference rather than a raw exception or stack trace. Native platform forms are not universally
intercepted; the Aegis save form captures its own Salesforce validation errors.

Register only reviewed customer remediation whitelists or idempotent retry implementations.
The shipped sample tax handler fails closed. The implemented approved-Flow extension and its
fixed input/output contract are described in [Approved Flow recovery](APPROVED_FLOW_RECOVERY.md).
Knowledge of a customer process does not authorize replaying shipments, invoices, estimates or
work steps; define and accept that operation's real postcondition first.

## Lightning surfaces

The Aegis Admin app includes Operations, Setup and its utilities. Tracked Sales Console and
Lightning Service app metadata preserve their existing utility associations. Users working
in another app require its own authorized utility placement. Honor Surface_Config enablement.

The Contact layout includes Save with Aegis Diagnostics. The product Feedback layout exposes
its existing Comments field for a meaningful native custom-object edit. The user chose to preserve the Case
Solutions related list; Case saves use the Operations workspace. The Case quick-action
definition alone does not place it on the native Case layout. Existing Case layout data and
Solutions remain intact. Operations is a support/admin surface, not an End User tab grant.

## Optional linked debug-log bodies

The collector can return a sanitized, bounded body only for an authorized server-linked log
in the exact current org. Configure an approved same-org Named Credential and Log_Connection
metadata plus native sensitive-context/admin and diagnostic access. The default connection
is disabled. Retrieval uses at most two GETs, rejects oversized logs, and returns ephemeral
text; it does not enable trace flags or persist Files. See the developer guide for limits.

## MCP product and process knowledge

The [local MCP server](../integrations/mcp/README.md) serves scoped curated knowledge offline,
plus authorized live Salesforce diagnostics when an org connection is configured. Initial
content covers Aegis, ABC pick/ship and SoCal field service, with source hashes and explicit
local/proposed/unknown evidence states. It does not establish either customer's live-org
parity. Customer knowledge requires explicit AEGIS_KNOWLEDGE_CUSTOMERS selection. Add other
products through the documented reviewed ingestion workflow; never ingest live data or secrets.

## Monitoring and retention

Preserve existing schedules and tune them for the customer's operating model. Validate
instrumentation and representative volume under actual customer automation. Application
health, unit tests and a synthetic diagnostic run cannot prove every customer business process.

## Remaining environment acceptance

The standard-user rendered journey passed after the user explicitly approved a temporary
Login As policy window in this development org. Own notice/details, Help/Analyze, dismissal
surviving reload, foreign notice absence and foreign-record denial were verified. The original
OFF policy was restored after each test window; no password or profile was changed. The
monitor follow-up also verified one bounded Refresh alerts read and automatic live receipt.

The QA session could subscribe to Aegis alerts while its optional native Flow error stream
was unavailable. The monitor now reports that limitation separately from action failures;
it does not grant broader access or claim all event sources are working. Saved-alert refresh,
configured fault instrumentation and scheduled reconciliation remain separate paths.

Existing personalized app navigation was preserved; users with customized navigation may need
to add Operations/Setup from the app's configured items. Default app metadata includes both.
The local stdio server is ready for registration in the chosen MCP client using its guide;
no global client settings or shared hosting were changed by this implementation.
