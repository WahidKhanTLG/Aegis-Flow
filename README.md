# Aegis Flow

**Smart Diagnostics. Bounded AI. Absolute Governance.**

Aegis Flow is a Salesforce-native diagnostic, guided-remediation, retry, and developer-escalation product. It captures failures from supported Salesforce execution surfaces, normalizes evidence, applies deterministic error rules, exposes approved actions for Agentforce, and routes unresolved issues with a sanitized technical package.

## Reconciled release

This source tree is the consolidated release candidate built from the newest coherent REVIEWED package and selected compatible capabilities from the parallel Complete DX implementation.

**Version:** 1.2.0-reconciled  
**Metadata API pin:** 67.0. Compilation and regression results must be recorded against the actual target org.

## Current development scope

The application supports sales, service, custom-object and integration diagnostics through
configurable rules, context-field allowlists, escalation routes and registered retry/remediation
strategies. Customer-specific business logic must be explicitly registered and authorized;
the product does not automatically repair arbitrary Salesforce errors.

The current development adds JSON-safe masking, atomic remediation audits, bounded retry
processing, canonical notification resolution, functional diagnostic surfaces, scoped REST
operations, a local MCP bridge and optional Named Credential adapters for Agentforce and
external escalation. External connections remain disabled until an administrator configures
and authorizes the actual service. Managed packaging is outside this development scope.

## Included capabilities

- Direct and rollback-resilient error capture with unique correlation IDs.
- Bulkified platform-event subscribers for capture, session requests, diagnosis, batch failures and escalation, with explicit 200-event delivery configuration. Governed remediation and business retries remain synchronous.
- Manual **Diagnostic Assistant** utility for Lightning apps and record pages.
- Deterministic diagnosis fallback plus approved Agentforce invocable actions.
- Metadata-governed remediation with confirmation, CRUD/FLS, sharing, object/record validation, picklist validation, and audit history.
- Registered idempotent retry handlers with `Retry_Attempt__c` audit records.
- Developer escalation packages with route selection and `Delivery_Audit__c` delivery results.
- Queueable finalizer, Batch Apex error event handling, async-job monitoring, Flow fault action, LWC error boundary, and inbound REST capture.
- Private sharing defaults for diagnostic and evidence objects.
- Corporate Aegis Flow command center, diagnostic assistant, escalation viewer, and remediation confirmation UI.
- Permission sets for end users, support analysts, developer viewers, product admins, integration users, and the sample Account remediation scenario.

## Agentforce implementation boundary

The package provides deterministic fallback diagnosis, approved Apex action contracts, and an
optional Agent API client with bounded asynchronous enrichment. It does **not** deploy or
activate a finished Agentforce agent. Agent configuration, licensing, Named/External
Credentials and principal access are org-specific. Use a dedicated read-only diagnostic
agent: returned recommendations are validated and never executed automatically.

Available Agentforce actions include:

- `AEIR_GetErrorContextAction`
- `AEIR_FindRecentErrorsAction`
- `AEIR_GetRecordSnapshotAction`
- `AEIR_UpdateMissingFieldAction`
- `AEIR_ExecuteRetryHandlerAction`
- Existing diagnosis and escalation invocable actions

This action catalog serves separately governed interactive workflows. The dedicated
enrichment agent must exclude remediation, retry, escalation and other write actions.

## Local validation

The November 3 development release was deployed to the verified Aegis development org
(`SyncBridge-Product`, org `00DgL00000YDvsvUAD`): 551 components and 283 passing Apex tests.
The subsequent telemetry masking patch passed all 284 Apex tests; the setup-health follow-up
passed all 286. Final local checks passed 105 LWC tests and 30 MCP tests. Live stdio knowledge/diagnostic reads also passed.
See the [November 3 verification record](output/development/2026-11-03/verification.json)
for final counts, source comparison, configuration, live acceptance and explicit limits.
The [November 2 report](output/development/2026-11-02/verification.json) remains historical.

A fresh isolated org retrieval on November 7 confirmed all 689 product release files
match this source, allowing only formatting and seven documented org configuration
differences. No unexpected differences or missing release files were found. See the
[November 7 source verification](output/development/2026-11-07/verification.json).

```bash
python3 scripts/local_audit.py
npm run test:unit -- -- --runInBand
npm run test:mcp
```

The local audit checks XML parsing, Apex/class metadata pairing, trigger metadata pairing, LWC bundle completeness, object metadata structure, and the explicit package manifest.

## Salesforce validation

An authenticated Salesforce org and Salesforce CLI are required for compilation and deployment validation:

```bash
sf project deploy start \
  --manifest manifest/package.xml \
  --target-org YOUR_AUTHORIZED_DEV_ORG \
  --dry-run \
  --test-level RunLocalTests \
  --wait 60

sf apex run test \
  --class-names AEIR_CoreTest,AEIR_ReconciledFeaturesTest \
  --target-org YOUR_AUTHORIZED_DEV_ORG \
  --code-coverage \
  --result-format human \
  --wait 60
```

## Required post-deployment configuration

1. Assign the appropriate Aegis Flow permission sets.
2. Configure approved company escalation recipients and `Escalation_Route__mdt` destinations.
3. Add **Aegis Flow Diagnostic Assistant** to selected Lightning utility bars.
4. Configure Agentforce only if needed. Keep the enrichment agent read-only; register write actions only in a separately governed interactive workflow.
5. Wire customer Flow fault paths to `AEIR_CaptureFlowFaultAction`.
6. Replace the sample retry handler with process-specific, idempotent implementations.
7. Optionally configure the implemented, bounded same-org Tooling log-body collector with an approved Named Credential; it remains disabled by default.
8. Schedule retention and async-job monitoring according to the customer’s operating model.

See `docs/AEGIS_FLOW_PACKAGE_REVIEW.md` and `docs/DEPLOYMENT_AND_TESTING_GUIDE.md` before deployment.

## Headless operations and MCP

`AEIR_HeadlessRestService` exposes bounded diagnostic operations under
`/services/apexrest/aegis-flow/v1/operations/`. Assign `AEIR_Headless_User` alongside the
appropriate Aegis diagnostic role; the custom permission alone grants no object access.
Read tools cover capabilities, recent errors, incidents, notifications and sanitized error
context. Two additional tools search/read curated product and process knowledge. Help, dismissal and escalation remain separately authorized, explicit operations.

The dependency-free Node MCP bridge uses an existing authorized Salesforce CLI alias:

```bash
AEGIS_TARGET_ORG=YOUR_AUTHORIZED_DEV_ORG node integrations/mcp/server.mjs
```

It defaults to read-only tools. Enable `AEGIS_ALLOW_WRITES=true` only for an approved client;
each mutation also requires `confirmed: true`. Credentials stay in process memory and are
never included in MCP responses. The Salesforce API must be deployed before live diagnostic reads. Curated knowledge works
offline without Salesforce or an AI provider. See [the MCP guide](integrations/mcp/README.md)
for resources, customer scoping, client configuration and source provenance.

## Development QA fixtures

The two `Aegis_Test_Order_On_Closed_Won*` Flows intentionally inject failures in the existing
development org. They are excluded by `.forceignore` and the release manifest. No original order fixture was deactivated. The separate approved-Flow QA fixture passed real
write/deduplication/idempotency checks and was then disabled and unassigned. Use the manifest-based scripts
with an explicit target org for any future authorized deployment.

## Marketable MVP Completion Delta

This archive includes the reconciled Salesforce DX baseline plus a completed marketable-MVP delta for the headless monitoring requirement:

- Added the browser-safe `Aegis_User_Alert__e` platform event.
- Added durable `User_Notification__c`, grouped `Incident__c`, and `Delivery_Attempt__c` operational telemetry.
- Added `Notification_Policy__mdt`, `Feature_Flag__mdt`, `Severity_Rule__mdt`, and `SLA_Policy__mdt` configuration foundations.
- Added `AEIR_UserNotificationService` and `AEIR_AegisHeadlessMonitorController` for secure alert retrieval, acknowledgement, dismissal, Get Help handoff, and escalation.
- Added the `aegisHeadlessMonitor` utility-bar LWC and the missing component bundles named in the product specification.
- Added the functional `Aegis_Error_Capture_Fault_Subflow` with rollback-resilient publication and required inputs for customer Flow fault-path instrumentation.
- Updated the package manifest to include the completed metadata set.
