# Aegis Flow

**Smart Diagnostics. Bounded AI. Absolute Governance.**

Aegis Flow is a Salesforce-native diagnostic, guided-remediation, retry, and developer-escalation product. It captures failures from supported Salesforce execution surfaces, normalizes evidence, applies deterministic error rules, exposes approved actions for Agentforce, and routes unresolved issues with a sanitized technical package.

## Reconciled release

This source tree is the consolidated release candidate built from the newest coherent REVIEWED package and selected compatible capabilities from the parallel Complete DX implementation.

**Version:** 1.2.0-reconciled  
**Metadata API pin:** 60.0 for backward-compatible deployment validation. Increment only after compiling and testing against the target org’s current API version.

## Included capabilities

- Direct and rollback-resilient error capture with unique correlation IDs.
- Bulkified platform-event subscribers for capture, diagnosis, remediation, retry, and escalation.
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

The package provides deterministic fallback diagnosis and approved Apex action contracts. It does **not** deploy or activate a finished Agentforce agent because agent topics, instructions, action registration, channels, permissions, licensing, and trust configuration are org-specific.

Available Agentforce actions include:

- `AEIR_GetErrorContextAction`
- `AEIR_FindRecentErrorsAction`
- `AEIR_GetRecordSnapshotAction`
- `AEIR_UpdateMissingFieldAction`
- `AEIR_ExecuteRetryHandlerAction`
- Existing diagnosis and escalation invocable actions

## Local validation

```bash
python3 scripts/local_audit.py
```

The local audit checks XML parsing, Apex/class metadata pairing, trigger metadata pairing, LWC bundle completeness, object metadata structure, and the explicit package manifest.

## Salesforce validation

An authenticated Salesforce org and Salesforce CLI are required for compilation and deployment validation:

```bash
sf org login web --alias aegis-target --set-default
sf project deploy start \
  --source-dir force-app \
  --target-org aegis-target \
  --dry-run \
  --test-level RunLocalTests \
  --wait 60

sf apex run test \
  --class-names AEIR_CoreTest,AEIR_ReconciledFeaturesTest \
  --target-org aegis-target \
  --code-coverage \
  --result-format human \
  --wait 60
```

## Required post-deployment configuration

1. Assign the appropriate Aegis Flow permission sets.
2. Replace sample escalation recipients in `Escalation_Route__mdt`.
3. Add **Aegis Flow Diagnostic Assistant** to selected Lightning utility bars.
4. Register the approved invocable actions in Agentforce and activate the configured agent.
5. Wire customer Flow fault paths to `AEIR_CaptureFlowFaultAction`.
6. Replace the sample retry handler with process-specific, idempotent implementations.
7. Configure debug-log collection only where customer authorization permits.
8. Schedule retention and async-job monitoring according to the customer’s operating model.

See `docs/AEGIS_FLOW_PACKAGE_REVIEW.md` and `docs/DEPLOYMENT_AND_TESTING_GUIDE.md` before deployment.

## Marketable MVP Completion Delta

This archive includes the reconciled Salesforce DX baseline plus a completed marketable-MVP delta for the headless monitoring requirement:

- Added the browser-safe `Aegis_User_Alert__e` platform event.
- Added durable `User_Notification__c`, grouped `Incident__c`, and `Delivery_Attempt__c` operational telemetry.
- Added `Notification_Policy__mdt`, `Feature_Flag__mdt`, `Severity_Rule__mdt`, and `SLA_Policy__mdt` configuration foundations.
- Added `AEIR_UserNotificationService` and `AEIR_AegisHeadlessMonitorController` for secure alert retrieval, acknowledgement, dismissal, Get Help handoff, and escalation.
- Added the `aegisHeadlessMonitor` utility-bar LWC and the missing component bundles named in the product specification.
- Added the packaged `Aegis_Error_Capture_Fault_Subflow` metadata shell with all required input variables for customer Flow fault-path instrumentation.
- Updated the package manifest to include the completed metadata set.
