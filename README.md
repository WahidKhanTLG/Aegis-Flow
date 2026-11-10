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
and authorizes the actual service. Local managed-source preparation is implemented. Actual namespace/Dev Hub setup, package
builds and namespaced installation remain team-owned environment work. See
[packaging handoff](docs/PACKAGING_DEVELOPMENT_HANDOFF.md).

## Current review and product tracking

The [product plan and tracker](docs/PRODUCT_PLAN_AND_TRACKER.md) separates all 55 implemented
features from release acceptance, optional integrations, commercial work and proposed ideas.
The [source publication review](docs/SOURCE_PUBLICATION_REVIEW.md) records preservation checks,
the successful 571-component / 311-test Salesforce check-only run, live read-only MCP proof,
and the dated source/org comparison. The later separately authorized
[development deployment](docs/DEVELOPMENT_DEPLOYMENT_VERIFICATION.md) passes 27 components /
311 tests and a focused 9-test follow-up. Current 717-file scoped source parity passes with
two enabled flags and five configured event users preserved. Hosted CI remains blocked by
GitHub account billing; actual managed-package and customer acceptance remain separate.

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

Before the local hardening changes, an isolated org retrieval on November 7 confirmed all
689 product release files matched the published baseline, allowing only formatting and
seven documented org configuration differences. No unexpected differences or missing release files were found. See the
[November 7 source verification](output/development/2026-11-07/verification.json).

```bash
python3 scripts/local_audit.py
npm run test:unit -- -- --runInBand
npm run test:mcp
```

The local audit checks XML parsing, Apex/class metadata pairing, trigger metadata pairing, LWC bundle completeness, object metadata structure, and the explicit package manifest.

## Development hardening deployed and verified

The November 7 P1/P2 hardening was deployed to the verified development org
(`SyncBridge-Product`, org `00DgL00000YDvsvUAD`): 61 focused components, 211 passing Apex
tests across 27 new and affected classes, no compilation errors or coverage warnings.
Six additional post-deployment tests checked the real committed role permissions; their
temporary test class/users were not persisted. Native event capture, publisher attribution,
durable rejection telemetry, diagnosis/alert reads and dismissal, draft escalation replay,
long keys and lifecycle/formula behavior passed controlled runtime checks. All synthetic
diagnostics were cleaned up. Flags, routes, five subscriber identities and six schedules
were preserved. Nothing was deployed to production, committed, pushed or published.
See the [deployment and runtime record](output/development/2026-11-07/hardening-deployment/verification.json)
for source comparison, permission evidence, rollback snapshot and limits. The earlier
[check-only record](output/development/2026-11-07/org-hardening-validation.json) is historical.

- Internal diagnostic-session events are no longer readable/publishable through the End User
  permission set. A request must identify its authenticated publisher. Ordinary Help Me uses
  the current-user-bound controller; trusted on-behalf-of adapters use the server service.
- Capture subscribers inspect every result, record rejected inputs, and retry temporary lock/service
  failures within the platform retry budget. Final event publication failures produce separate
  telemetry through a callback. An accepted publication is not a persistence guarantee.
- Batch failures have event-specific correlations, preserving separate failed scopes and replay deduplication.
- The Flow and async monitors persist keyset progress in the existing org setting. Each run
  advances one bounded page (200 interviews or 100 jobs), including pages already captured.
  End-of-sweep reset catches late status changes; async selection uses completion time.
- Escalations use a unique source/route key and a durable delivery claim under the source row lock.
  A draft may be sent once. Sent, failed, pending, or historically attempted deliveries are
  returned without implicit resend. Reconcile uncertain outcomes before an explicitly governed retry.
- Flow coverage counts exact observed-interview correlations separately from historical captures.
  Long incident keys hash their complete inputs, retaining source, object, category and time bucket.
- Timing uses server-owned first-diagnosis/resolution transitions and aggregate formula durations,
  not last edit times or a capped row sample. Unknown legacy timings return null. No historical
  timestamps or incident keys are fabricated or migrated by this change.

Development requires Node 22.13+ LTS or Node 24+, with pinned test/parser packages and a
lockfile. The Salesforce CLI is an **external prerequisite** for explicitly authorized org
operations and CLI-backed MCP authentication; it is no longer redundantly bundled into this
project's npm installation. The installed system CLI is not changed or security-certified here.
Review its vendor advisories separately before providing deployment credentials. The MCP
server and Salesforce runtime metadata do not import the removed CLI package.

The November 9 external CLI review inventories npm-installed CLI 2.156.8 and records 16
separate dependency-advisory matches (seven high, nine moderate). No shared CLI update was
performed. [Release toolchain review](docs/RELEASE_TOOLCHAIN_REVIEW.md) documents the stable
candidate and completed local CLI-01 qualification for its restricted nonproduction
validation/Apex-test scope. The [decision record](release-preparation/cli-release-use-review.json)
binds the exact artifact/runtime/plugins and exclusions. No target/action authority is
granted; the shared global CLI, bare wrappers and CLI-backed MCP launch are not qualified.

## Local handoff and acceptance preparation

The prepared local package includes the [operating handoff](docs/OPERATIONS_HANDOFF.md),
[user quick start](docs/USER_QUICK_START.md), [final acceptance plan](docs/RELEASE_ACCEPTANCE_PLAN.md)
and [rollback runbook](docs/ROLLBACK_RUNBOOK.md). The
[preparation index](release-preparation/README.md) contains 17 bounded acceptance cases,
an unbound target profile and an evidence template with every case marked Not run.
`npm run check:release-prep` validates their contracts and source references without
contacting Salesforce; it also runs inside `npm run verify`. Explicit readiness validation
rejects the unbound profile. Document preparation does not establish owner sign-off,
current target identity, actual delivery, org rollback or customer acceptance.

```bash
npm ci --ignore-scripts
npm run verify
npm run audit:deps
```

`verify` runs metadata checks, Apex grammar/inline-query syntax checks, all-bundle LWC compilation,
standalone source syntax checks, JavaScript lint, dependency-compatibility regressions, LWC
tests and MCP tests.
The syntax checker does not type-check Salesforce APIs or execute Apex tests. The focused
development validation separately compiled the hardening metadata and ran the new and affected
Apex tests, including event failure handling, replay, backlog fixtures and formula durations.
Committed permission upgrades and controlled runtime scenarios were verified after the
development deployment. Live backlog volume, true concurrent contention and rendered
customer/browser acceptance remain separate from these checks.
The dependency audit reports all severities and fails at high/critical; lower-severity vendor
findings remain visible and require review rather than forced incompatible upgrades.

## CI and static checks

The GitHub Actions workflow validates pull requests and pushes to `main` on Node 22 and 24.
It uses the same `npm run verify` command as local development, a clean locked installation
with lifecycle scripts disabled, workflow syntax validation, and the existing high/critical
dependency-audit gate. It requires no Salesforce credentials and performs no deployment.

The setup remains local until an explicitly authorized commit/push; no hosted run is claimed.
See [CI and static checks](docs/CI_AND_STATIC_CHECKS.md) for scope, pinned tooling, lint policy,
dependency qualification, and the first-hosted-run acceptance boundary.

The November 10 packaging-development update resolves the project dependency findings with
an explicit owned deepmerge security replacement and an isolated ESLint 10 lint toolchain.
Both all-severity locked audits are clean. Salesforce rule ports are locally qualified;
upstream ESLint 10 support is not claimed. Install both dependency trees before verification:

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm ci --prefix tools/lint --ignore-scripts --no-audit --no-fund
npm run verify
```

The full local suite passes on Node 22.23.4/24.22.2: 124 LWC, 33 MCP, 12 dependency/security
and eight source-staging tests. All 105 Apex grammar inputs and 14 LWC bundles / 39 compiler
inputs pass locally. See [dependency security review](docs/DEPENDENCY_SECURITY_REVIEW.md)
and [packaging development handoff](docs/PACKAGING_DEVELOPMENT_HANDOFF.md). No actual
namespaced compilation, package version, clean installation or hosted CI result is claimed.

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
