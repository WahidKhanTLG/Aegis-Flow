# Aegis Flow Implementation Coverage Report

## Product purpose and current scope

Aegis Flow captures Salesforce failures, stores sanitized evidence, gives deterministic or
optional Agentforce guidance, executes explicitly approved recovery actions and routes
unresolved issues to the responsible team. Its reusable platform supports Sales, Service,
custom-object and integration processes. Customer rules and business writes require explicit
configuration and acceptance. Managed packaging is excluded from this development scope.

## Implemented application capabilities

| Area | Local implementation | Operational dependency |
| --- | --- | --- |
| Capture | Apex guard, Flow fault action/subflow, custom-form errors, Batch error events, Queueable finalizers, async/Flow monitors and authenticated inbound REST | Instrument supported execution surfaces; native platform saves are not universally intercepted |
| Evidence protection | Private objects, structured secret masking, bounded snapshots, authorized context reads and payload limits | Maintain field allowlists and retention policy |
| Diagnosis | Deterministic rules, bounded valid JSON, owned-record authorization, separately privileged integration processing and stored results | Configure customer rules; no AI license needed for fallback |
| Optional Agentforce | Named Credential Agent API lifecycle, strict response/action validation, asynchronous enrichment and fallback preservation | Dedicated read-only agent/principal, licensing, approved OAuth and explicit enablement |
| User experience | Functional diagnostic, help, notification, remediation and escalation surfaces; canonical alerts; pending/error/empty states and keyboard handling | Host components in authorized apps and perform rendered Salesforce acceptance |
| Remediation | Exact metadata whitelist, confirmation, target CRUD/FLS/sharing, strict values and atomic target/audit rollback | Register approved object/field actions; enable governed remediation intentionally |
| Retry | Authorized registered synchronous handlers, bounded batches, backoff, idempotency audit and mutation rollback | Customer-specific idempotent business implementation; shipped sample fails closed |
| Escalation | Email/Case and optional Slack, Teams, Jira, GitHub and webhook adapters; durable outbox/audit and uncertain-delivery handling | Approved destinations, credentials, identities and explicit connector enablement |
| Headless | Bounded scoped REST errors/incidents/context/notifications plus explicit help/dismiss/escalate operations | Headless permission plus diagnostic role and operation-specific access |
| MCP | Node stdio resources, scoped source-cited product/process knowledge, five Salesforce read tools and three optional confirmed writes | Explicit customer corpus selection; reviewed curation; authorized org identity for live reads |
| Volume and monitoring | Bulk collection operations, subscriber batches capped at 200, telemetry and Flow-level gap estimates | Approved subscriber principal and customer-automation capacity testing |

## Validation evidence

The November 3 product deployment succeeded (`0AfgL00000cRx7mSAC`): 551 components and 283
Apex tests. The telemetry masking follow-up (`0AfgL00000cRxisSAC`) passed all 284 Apex tests.
The setup-health follow-up passed all 286 Apex tests; final local checks passed 105 LWC
and 30 MCP tests. The health check passed all 10 configuration checks. Real rollback-cleaned diagnostics passed
Sales, Service, custom-object and integration samples. A separate QA Flow proved actual write,
service deduplication, Flow idempotency and refusal of an unapproved marker, then was disabled.

The [November 3 verification record](../output/development/2026-11-03/verification.json)
contains final local test counts, source/config comparison, rendered UI and committed-event/MCP
acceptance results. The November 2 check-only report is historical; it did not deploy the org.
No managed package, commit or push is part of this work.

## Customer acceptance boundary

ABC and SoCal source-grounded knowledge and proposed acceptance scenarios are curated in
[the MCP corpus](../integrations/mcp/knowledge/README.md). Their customer orgs were not accessed
or modified. Production recovery registrations still need reviewed exact targets/writes,
permissions, real business idempotency and customer-approved success criteria. External agent,
Tooling-body and delivery connections remain disabled until approved credentials/destinations
are supplied; the user selected knowledge/MCP work instead of activating those providers.

Use the dated result to distinguish actual deployment and synthetic development acceptance
from customer production certification. The two original order QA Flows remain unchanged and
excluded from the release. The newer temporary Flow fixture was separately disabled afterward.

Detailed contracts and acceptance criteria: [Scenario Coverage](SCENARIO_COVERAGE.md) and
[Developer Extension Guide](DEVELOPER_EXTENSION_GUIDE.md).
