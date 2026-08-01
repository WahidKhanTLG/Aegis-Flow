# Aegis Flow — Open Issues

**Audit date:** July 27, 2026
**Org audited:** `Aegis Flow_WA_Dev` (`00DgL00000YDvsvUAD`)
**Source baseline:** `force-app` @ `sourceApiVersion 67.0`
**Last updated:** July 28, 2026
**Spec of record:** `Aegis_Flow_Market_Ready_Product_Implementation_Specification (1).docx`

## Current verified state

| Check | Result |
|---|---|
| Apex classes deployed | 54 / 54 |
| Apex triggers deployed | 5 / 5 |
| Objects / events / CMDT deployed | 31 / 31 |
| LWC bundles deployed | 12 / 12 |
| Apex tests | **50 / 50 pass** (RunLocalTests) |
| LWC Jest tests | **8 / 8 pass** |
| Org-wide coverage | **85%** (all 5 triggers at 100%) |
| API version | 67.0, matching the org |
| Non-admin end-user journey | PASS (capture → alert → help → escalate → dismiss) |
| Live capture → notify → retrieve smoke test | PASS |

The org matches source with no drift. Everything below is **missing or incomplete implementation**, not a deployment failure.

Severity key: **P0** blocks pilot release · **P1** blocks a spec commitment · **P2** correctness/maintenance · **P3** packaging & GTM.

---

## Issue tracker

Update **Status** and **Owner** as work progresses. Status values: `Open` · `In progress` · `Blocked` · `Needs decision` · `Fixed`.

### P0 — Blocks pilot release

| ID | Issue | Spec | Status | Owner | Target |
|---|---|---|---|---|---|

### P1 — Blocks a spec commitment

| ID | Issue | Spec | Status | Owner | Target |
|---|---|---|---|---|---|
| AF-23 | No Agentforce callout exists — gateway is deterministic-only | §10, EPIC-10 | **Deferred** — decision: keep deterministic, do not burn API credits | | |

### P2 — Correctness and maintenance

| ID | Issue | Spec | Status | Owner | Target |
|---|---|---|---|---|---|

### P3 — Packaging and go-to-market

| ID | Issue | Spec | Status | Owner | Target |
|---|---|---|---|---|---|
| AF-20 | No namespace reserved and no 2GP packaging configured | §16, EPIC-17 | **Deferred** — resume after testing phase; standard in `NAMESPACE_READINESS.md` | | |
| AF-22 | AppExchange readiness work not started | §22, EPIC-18 | Open | | |

### Closed

| ID | Issue | Status | Closed |
|---|---|---|---|
| AF-C1 | `AEIR_BatchApexErrorEventTrigger` was never deployed | Fixed | 2026-07-27 |
| AF-C2 | No permission sets assigned to any user in the org | Fixed | 2026-07-27 |
| AF-C3 | Delta objects had object permissions but zero field permissions | Fixed | 2026-07-27 |
| AF-08 | `AEIR_BatchApexErrorEventTrigger` could not be covered | Fixed | 2026-07-27 |
| AF-17 | Two platform events quarantined and orphaned — **deleted by decision** | Fixed | 2026-07-27 |
| AF-25 | SOQL in a loop in an invocable action; uncached masking metadata | Fixed | 2026-07-27 |
| AF-03 | Notification policy never enforced — no storm protection | Fixed | 2026-07-27 |
| AF-05 | Feature flags were decorative | Fixed | 2026-07-27 |
| AF-14 | Documentation contradicted the implementation | Fixed | 2026-07-27 |
| AF-16 | Retention and async-job monitoring not scheduled | Fixed | 2026-07-27 |
| AF-01 | Flow fault subflow was a non-functional shell | Fixed | 2026-07-27 |
| AF-24 | Async diagnosis round trip never published | Fixed | 2026-07-27 |
| AF-02 | Headless monitor not reachable in any application | Fixed | 2026-07-27 |
| AF-04 | Incident aggregation unimplemented | Fixed | 2026-07-27 |
| AF-07 | Three classes at 0% Apex coverage | Fixed | 2026-07-27 |
| AF-09 | Custom permissions not implemented | Fixed | 2026-07-27 |
| AF-19 | Inbound REST endpoint had no authorization | Fixed | 2026-07-27 |
| AF-10 | Only the Email escalation channel was implemented | Fixed | 2026-07-27 |
| AF-12 | Severity, SLA, and Surface metadata were dead config | Fixed | 2026-07-27 |
| AF-13 | Error_Feedback__c and Error_Attachment__c were unused | Fixed | 2026-07-27 |
| AF-18 | Command Center reported 4 of 11 metrics | Fixed | 2026-07-27 |
| AF-06 | Zero LWC Jest tests and no Jest infrastructure | Fixed | 2026-07-27 |
| AF-11 | Setup readiness and health check did not exist | Fixed | 2026-07-27 |
| AF-21 | API version pinned at 60.0 | Fixed | 2026-07-27 |
| AF-26 | Non-admin users blocked from the whole product | Fixed | 2026-07-28 |
| AF-15 | Escalation recipients were placeholders; no onboarding | Fixed | 2026-07-28 |
| AF-27 | Escalation dispatch was single-record and blew DML limits past ~30 records | Fixed | 2026-07-29 |
| AF-28 | Every Case-channel escalation failed silently on `Case.Origin` | Fixed | 2026-07-29 |
| AF-29 | Delivery audits were silently discarded for Case and connector channels | Fixed | 2026-07-29 |
| AF-30 | Every platform event subscriber and invocable action was single-record | Fixed | 2026-07-29 |

**Progress:** 30 fixed · 1 open (AF-22, go-to-market) · 2 deferred by decision (AF-20 namespace, AF-23 Agentforce callout).

The only remaining engineering-adjacent item is AF-22 (AppExchange listing, privacy policy, security review evidence), which is a go-to-market workstream rather than code.

**All P0 and P1 engineering items are closed.** What remains is packaging (deferred) and go-to-market documentation.

**AF-23 and AF-24 were raised by the AF-17 design review** — see `EVENT_ARCHITECTURE_PROPOSAL.md`.

---

## P0 — Blocks pilot release




## P1 — Blocks a spec commitment








### AF-23 · No Agentforce callout exists — the gateway is deterministic-only
**Files:** `force-app/main/default/classes/AEIR_AgentforceGatewayService.cls`
**Spec:** §10, §10.3, EPIC-10

`AEIR_AgentforceGatewayService` makes **no HTTP callout of any kind**. It runs deterministic string classification and writes `AI_Diagnosis__c` with `Agent_Status__c = 'Deterministic Fallback'`. A repo-wide scan finds no `HttpRequest`, no `new Http()`, and no `callout:` reference anywhere in `force-app`.

The deterministic fallback is genuinely useful and is the correct behaviour when the agent is unavailable — but "Agentforce-powered diagnosis" is not implemented. Still required: Named Credential / External Credential, prompt construction against the §10.3 contract, structured-response validation, unknown-action-key rejection, and confidence calibration.

**Design constraint to carry forward:** a platform event trigger cannot make a callout synchronously. The subscriber must enqueue a `Queueable` implementing `Database.AllowsCallouts`.

**Done when:** a real agent invocation returns a validated structured response, malformed output and unknown action keys are rejected server-side, and the deterministic path still runs when the agent is unavailable.

---




## P2 — Correctness and maintenance









## P3 — Packaging and go-to-market

### AF-20 · No namespace reserved and no 2GP packaging configured

> **Status: deferred by decision (July 27, 2026).** Development continues unmanaged to keep velocity; a separate packaging org is reserved. All new code must follow **`NAMESPACE_READINESS.md`** so the migration is a no-op. Revisit after the testing phase.

**Spec:** §16, §16.2, EPIC-17

`sfdx-project.json` has `"namespace": ""` and no `packageDirectories` package definitions. The spec targets a Second-Generation Managed Package split across four packages (Core / Agentforce Extension / Connector Extensions / Industry Rules).

§16.2 warns that the namespace must be reserved **before** customer-facing beta, and that packaged CMDT keys and public action keys cannot be renamed after release without a migration strategy. This should be settled early — it is the hardest item to reverse.

---


### AF-22 · AppExchange readiness work not started
**Spec:** §22, EPIC-18

Security Review evidence, privacy policy, data-handling and subprocessor documentation, install/upgrade/uninstall guides, demo org, trial experience, support process and severity definitions, listing assets, and the customer-facing AI boundary statement are all outstanding.

---

## Suggested sequencing

1. **AF-01, AF-02, AF-03** — without these the MVP promise (§1.2) is not demonstrable end to end.
2. **AF-04** — unblocks AF-03 grouping and AF-18 metrics.
3. **AF-09, AF-10 (Case route)** — closes the MVP security and routing commitments.
4. **AF-06, AF-07** — get the test story to a defensible state before packaging.
5. **AF-05, AF-12** — make shipped configuration real; needed for edition gating.
6. **AF-11** — required by the §24 acceptance statement.
7. **AF-14 through AF-19** — correctness and hygiene; cheap, do alongside the above.
8. **AF-20** — deferred by decision; enforce `NAMESPACE_READINESS.md` in the meantime so the later migration is a no-op.

### AF-26 resolution — non-admin users can now use the product

A journey test running as a Standard User with only `AEIR_End_User` found **five separate blockers**, each of which alone made the product unusable for a normal employee:

1. **No `applicationVisibilities`** — end users could not open the app hosting the utility bar, so they never saw an alert at all.
2. **No Apex class access** to the five services added during this work.
3. **No `Incident__c` create** — capture failed outright, because incident assignment runs inline.
4. **No `Developer_Escalation__c` create/edit or field permissions** — yet section 1.2 promises the user can "submit an escalation".
5. **No `Delivery_Audit__c` create/edit** — escalation dispatch writes a delivery record.

All fixed. `AEIR_EndUserJourneyTest` now proves an end user can capture, receive an alert, open details, use Get Help, submit feedback, escalate, and dismiss — and separately proves they **cannot** execute remediation, which stays admin-only.

Incident grouping was also made **fail-soft**: if it cannot write, capture still succeeds without an incident link. Section 1.2 requires the error record to persist even when downstream services are unavailable, and bookkeeping must never cost a customer their evidence.

---

### AF-15 resolution — onboarding, configurable teams, and a safe fallback

**New:** `Aegis_Org_Setting__c` hierarchy custom setting, `AEIR_OrgSetupService`, the `aegisSetupWizard` LWC, and an **Aegis Flow Setup** tab.

A three-step wizard captures company name, development team email, and administrator team email, then a safety-net and data-sharing step, then a verify step that runs the health check inline. Multiple comma-separated addresses are supported and validated before save.

**Recipient resolution order:**

1. The team email captured during onboarding
2. The `Escalation_Route__mdt` recipient, if it is not a placeholder
3. **Active System Administrators in the customer org** (default on)
4. The vendor support mailbox — **only when explicitly opted in**

`AEIR_EscalationService` resolves recipients through this chain at escalation creation, so the record shows where it will actually go, and email now supports several addresses instead of one. The health check gained an Onboarding check that reports the resolved destination and warns when the fallback is carrying delivery.

**On the vendor-fallback question.** Routing customer findings to the vendor mailbox *by default* was deliberately not built. Escalation packages carry stack traces, record identifiers, and record snapshots; sending those to the ISV without informed consent creates a GDPR sub-processor relationship and is the kind of default that draws a hard stop in Salesforce Security Review. The capability exists and works — it is simply opt-in, off by default, requires a destination address, and is labelled in the UI with what the data contains. Step 3 (system administrators) means a customer who configures nothing still never loses a finding.

---

### AF-06 resolution — Jest infrastructure and LWC tests

`@salesforce/sfdx-lwc-jest` installed with `jest.config.js`, `npm run test:unit`, and mocks for `lightning/empApi`, `platformShowToastEvent`, and `lightning/navigation`. The empApi mock captures the subscription callback so a test can push a platform event without a live streaming connection.

**8 tests, all passing**, covering the section 20 requirements for `aegisHeadlessMonitor`: dormant on load (one subscription, nothing rendered), alert shown for the current user, alert for a different user ignored, expired alert ignored, duplicate correlation id suppressed, **Detected upgraded to Diagnosed in place rather than stacking a card**, missed alerts loaded on init for the mobile fallback, and unsubscribe on disconnect.

`.forceignore` excludes `__tests__` and the mock directory from deployment.

---

### AF-11 resolution — setup readiness and health check

**New:** `AEIR_SetupHealthCheckService`, reporting PASS / WARNING / FAIL across nine prerequisites — permission sets, escalation routing, rule library, notification policy, feature flags, monitored surfaces, Flow fault framework, scheduled jobs, and the remediation whitelist. Every non-pass carries a concrete remediation instruction, as section 14.1 requires.

`runWithProbe()` adds a live end-to-end probe (capture, classify, group, notify) that returns a test correlation id and **cleans up every record it creates**, satisfying the section 14.1 rule of no production data mutation. The test asserts the org's error log count is unchanged afterwards.

**Live result against `Aegis Flow_WA_Dev`: 8 PASS, 2 WARNING, 0 FAIL.** Both warnings are known open items — placeholder escalation recipients (AF-15) and the intentionally disabled staged-rollout flags.

Remaining for EPIC-16: the guided eight-step wizard UI. The readiness engine it needs now exists and is callable from LWC.

---

### AF-21 resolution — API version 60 to 67

68 metadata files, `sfdx-project.json`, and `manifest/package.xml` moved to 67.0, matching the org. Full suite re-run on the new version.

**The bump earned its keep — it surfaced three real defects that API 60 was masking:**

1. **`Sensitive_Field__mdt` was unreadable** for users without custom metadata access, and `mask()` runs on every capture, so capture threw. Masking now degrades to the built-in secret patterns instead of throwing — fail safe, not fail open — and all twelve Aegis custom metadata types are granted through the permission sets.
2. **`Error_Log__c.Incident__c` and `Incident_Key__c` had no field permissions.** Same class of bug as AF-C3: fields added in AF-04 without FLS. Added across all six permission sets.
3. **`AEIR_RemediationOrchestrator.execute()` threw instead of returning a result** when an unauthorized caller could not insert the audit row. Authorization is now checked before any DML, and a failed audit insert no longer masks the original failure.

Also learned: `fieldPermissions` elements must be **contiguous** in a permission set, or the deploy fails with "Element fieldPermissions is duplicated at this location".

---

### AF-12 resolution — remaining configuration metadata is consulted

**New:** `AEIR_PolicyConfigService`, caching all three types per transaction.

- **`Severity_Rule__mdt`** feeds `AEIR_ErrorCaptureService.buildLog()`. A matching rule overrides the deterministic severity unless the caller supplied one explicitly. Source-specific rules outrank generic rules of equal impact score, and an invalid regex degrades to a substring match rather than throwing.
- **`SLA_Policy__mdt`** now drives `Developer_Escalation__c.SLA_Due_At__c` through `resolveSlaDueAt()`, replacing the hardcoded 4/24 hour split, and supplies `Owner_Team__c` to the Case description.
- **`Surface_Config__mdt`** is exposed to the LWC via `AEIR_AegisHeadlessMonitorController.getSurfaceSettings()`, so an admin can disable the utility, mobile polling, or Experience Cloud surfaces without removing the component. Defaults to enabled when unconfigured, so an untouched org still works.

Also added `getAlertChannel()`, which returns the empApi channel derived from `getDescribe().getName()` — the namespace-safe replacement for the hardcoded string flagged in `NAMESPACE_READINESS.md`.

---

### AF-10 resolution — Salesforce Case route implemented

`AEIR_EscalationService` now dispatches by channel instead of only handling Email. The Case route creates a Case with `Origin = 'Aegis Flow'`, priority derived from severity, and a description carrying correlation id, severity, owner team, SLA due date, summary, and the diagnostic package. The resulting `CaseNumber` is stored in `External_Ticket_Id__c` and a `Delivery_Audit__c` row records the outcome. CRUD is checked before insert; failures mark the escalation `Failed` with the reason recorded rather than swallowed.

Email and Case are Release 1 scope (spec section 18). **Jira, Slack, Teams, GitHub, and webhook now record a `Pending` delivery audit** explaining that the connector is not implemented, instead of silently appearing delivered — which was the more dangerous half of this bug.

---

### AF-13 resolution — feedback and attachments are reachable

**New:** `AEIR_FeedbackService`.

- `submitFeedback()` writes `Error_Feedback__c` with helpfulness, outcome, masked comments, and the submitting user, implementing the section 7.4 loop. Exposed to LWC through `AEIR_AegisHeadlessMonitorController.submitFeedback()`. Feedback with no error log or session reference is rejected.
- `attachEvidence()` registers a Salesforce File against an error log as `Error_Attachment__c`, deduplicating on content document id, with retention aligned to the error log policy. `evidenceFor()` supplies the escalation package's evidence manifest (section 12, Debug Evidence).

Comments are masked before storage — the test asserts a password in free text does not reach the database.

---

### AF-18 resolution — full Command Center metric set

`AEIR_AdminConsoleController.getMetrics()` went from 4 metrics to all 11 in spec section 13.2. The seven added: affected users (distinct today), recurring incidents, unresolved critical incidents, mean minutes to diagnosis, mean minutes to resolution, assisted resolutions, automatically resolved, retry success rate, and ranked top failing sources.

Assisted versus automatic is distinguished by `Requires_Confirmation__c` on the executed remediation — a user-confirmed fix versus a system-safe one. Recurrence threshold is 3 occurrences.

Several of these were only computable once AF-04 populated `Incident__c`, which is why the two were sequenced together.

---

### AF-04 resolution — incident aggregation

**New:** `AEIR_IncidentAggregationService` (92%), wired into both capture paths, plus `Error_Log__c.Incident__c` (lookup) and `Error_Log__c.Incident_Key__c` (external id).

The incident key is `sourceType|sourceName|category|object|timeBucket` on a 60 minute bucket. **Record id is deliberately excluded**, which is what makes 500 rows failing the same validation rule collapse into one incident rather than 500. A failure tomorrow starts a fresh incident instead of inflating today's.

Bulk-safe: two queries and one upsert regardless of input size. Occurrence count accumulates, severity rolls up to the highest observed, and affected record/user counts are distinct across history rather than per batch.

Tests: 20 identical failures produce exactly **1** incident with `Occurrence_Count__c = 20` and `Highest_Severity__c = Critical`; two unrelated failures produce 2 incidents; capture attaches an incident automatically.

This also unblocks AF-18 metrics and gives the notification policy a real `Group_By_Key__c`.

---

### AF-09 resolution — custom permissions

Three custom permissions added and granted through the permission sets: `AEIR_Execute_Remediation` (Product Admin, Support Analyst, Sample Remediation), `AEIR_View_Sensitive_Context` (Product Admin, Developer Viewer), `AEIR_Inbound_Diagnostic_Capture` (Product Admin, Integration User).

`AEIR_RemediationOrchestrator.execute()` now requires `AEIR_Execute_Remediation` via `FeatureManagement.checkPermission()`. Object and field access alone no longer authorize a corrective action — approval is a distinct, explicitly granted capability (spec 15.1).

The deny test runs under `System.runAs()` as a Standard User with no Aegis permission sets, because the admin running the suite legitimately holds the permission.

---

### AF-19 resolution — REST endpoint hardened

Three changes to `AEIR_InboundDiagnosticRestService`: it now requires `AEIR_Inbound_Diagnostic_Capture` and returns **403** otherwise, rejects payloads over 100,000 characters, and returns a clean contract error instead of an unhandled exception on malformed JSON.

Previously any authenticated user could write arbitrary diagnostic records with an unbounded payload.

---

### AF-07 resolution — untested classes covered, and a runtime bug found

| Class | Before | After |
|---|---:|---:|
| `AEIR_AegisHeadlessMonitorController` | 0% | 71% |
| `AEIR_AsyncJobMonitorScheduler` | 0% | 47% |
| `AEIR_QueueableFinalizer` / Example | 0% / 33% | covered |

**The coverage work found a live bug.** `AEIR_AegisHeadlessMonitorController.startHelpFromAlert()` passed `'Detected Failure'` to `Diagnostic_Session__c.Detected_Issue_Type__c`, which is a **restricted** picklist whose values are Save Error, Process Failed, Navigation Help, Data Question, Report Issue, Unknown. Every "Get Help" click from an Aegis alert would have thrown `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`. Corrected to `'Process Failed'`.

This is exactly the path AF-24 had just wired up, so it would have failed in the first demo.

---

### AF-02 resolution — utility bar is live and now deployable from source

The utility item was added through Setup (App Manager > Aegis Flow Admin > Utility Items), then **retrieved into source** so it is reproducible rather than a manual step. `force-app/main/default/flexipages/Aegis_Flow_Admin_UtilityBar.flexipage-meta.xml` and the app's `<utilityBar>` reference are both tracked and redeploy cleanly.

**Why the earlier metadata-authoring attempts failed.** Utility bar item properties must be tagged `<type>decorator</type>`:

```xml
<componentInstanceProperties>
    <name>label</name>
    <type>decorator</type>
    <value>Aegis Flow Headless Monitor</value>
</componentInstanceProperties>
```

Without that tag the validator tries to resolve `label` as an LWC design attribute and rejects it (`Invalid property [label]`); with the property absent it reports the required decorator property missing. The error text said "decorator property" and that was the clue. Valid decorator properties observed: `label`, `icon`, `width`, `height`, `eager`, `scrollable`. **No LWC change is needed** — the `@api label` and `targetConfigs` additions attempted earlier were unnecessary and were reverted.

**Scope limitation — deliberate, and worth tracking.** The utility bar is on the **Aegis Flow Admin app only**. Users working in Sales, Service, or any custom app will not receive proactive alerts, because a utility item is per-application. Spec 6.1 requires the utility be added to *each* supported Lightning application. That is correct for admin-facing validation now, but pilot users must have it in the app they actually work in. Tracked as AF-26.

`optional-metadata/` is now empty and has been removed; nothing remains quarantined.

---

### AF-01 resolution — Flow fault subflow is functional

`Aegis_Error_Capture_Fault_Subflow` was a shell: 13 input variables, **zero elements**, `status = InvalidDraft`. It is now a real autolaunched Flow deployed as **Active** (version 1).

Structure: `Start` → `Resolve Correlation Id` (assignment) → `Publish Error Captured Event` (recordCreates on `Error_Captured__e`). Three formulas back it:

- `fxCorrelationId` — reuses a caller-supplied id so a multi-step process keeps one id across all its failures; otherwise derives `FLOW-{!$Flow.InterviewGuid}`.
- `fxAffectedUserId` — prefers `varInitiatingUserId`, because background Flows run as Automated Process and `$User.Id` alone would misattribute the failure.
- `fxSourceName` — combines Flow api name and failing element so triage does not require opening the Flow.

It publishes the event rather than writing `Error_Log__c` directly, so evidence survives a rollback of the calling transaction (spec 4.1). `varCorrelationId` is an output variable, so a screen Flow can show a friendly reference number.

**Verified live in the org.** Invoking the subflow produced `Error_Log__c` with correlation `FLOW-306685c1…`, `Source_Name__c = "Order_Tax_Update_Flow / Update_Order_Records"`, classified `Validation Rule` / `Medium`.

---

### AF-24 resolution — async round trip closed

Both missing publishes are now wired, so the utility bar spinner resolves.

1. **Request** — `AEIR_ErrorCaptureService` publishes `Agent_Diagnosis_Requested__e` after both the direct and subscriber capture paths, gated on the `AI_DIAGNOSIS` flag. Publishing rather than calling the gateway inline keeps AI work out of the failing transaction (spec 23).
2. **Response** — `AEIR_AgentforceGatewayService.diagnoseError()` calls the new `AEIR_UserNotificationService.notifyDiagnosisComplete()`, which upgrades the existing notification **in place** to `Diagnosed` and publishes a second `Aegis_User_Alert__e`.

Headline and action follow spec 6.5 by fixability: `USER_FIXABLE` → "I have identified the issue." / `FIX`; `RETRYABLE` → retry wording / `RETRY`; `DEVELOPER_ONLY` or `ADMIN_FIXABLE` → technical-assistance wording / `ESCALATE`.

**Schema change:** `Target_User_Id__c` added to `Agent_Diagnosis_Requested__e` — the event previously had no user field, so the subscriber had no way to address the result.

**LWC:** `aegisHeadlessMonitor` now treats a later event sharing a correlation id as a status upgrade rather than a duplicate, replacing the card in place and refreshing an open detail panel.

A dismissed alert is never resurrected by a later diagnosis, preserving the spec 20.1 cooldown behaviour.

Two regression tests cover this: `diagnosisUpgradesTheAlertInPlace` asserts `Detected` before the event bus drains and `Diagnosed` after `Test.stopTest()`, with exactly one notification row throughout; `dismissedAlertIsNotResurrectedByDiagnosis` covers the dismissal case.

---

### AF-03 / AF-05 resolution — notification policy and feature flags are now enforced

**New:** `AEIR_FeatureFlagService` (100% coverage) and `AEIR_NotificationPolicyService` (95%), plus `AEIR_NotificationPolicyTest` with six tests.

`AEIR_UserNotificationService.notifyForErrorLogs()` now evaluates the whole batch against `Notification_Policy__mdt` before creating anything, so a storm cannot slip through one row at a time. Four gates apply in increasing cost order: `Notify_Affected_User__c`, `Minimum_Severity__c`, `Cooldown_Minutes__c`, then `Maximum_Alerts_Per_Hour__c`. Recent-notification history is read in a single query for all target users. `Critical_Mode__c` lets a Critical failure bypass throttling so it is never buried by lower-severity noise. A source-specific policy overrides `DEFAULT`, so one noisy surface can be tuned alone.

`AEIR_RemediationOrchestrator.execute()` is now gated on `GOVERNED_REMEDIATION`.

Regression test `stormIsThrottledByPolicy` captures **25 Medium errors for one user** and asserts at most 3 notifications result. Before this change it produced 25.

**Finding surfaced by this work:** the package ships `AI_DIAGNOSIS`, `CONNECTOR_EXTENSIONS`, and `GOVERNED_REMEDIATION` with `Enabled__c = false` — only `USER_NOTIFICATIONS` is on. That default is correct and matches the roadmap (section 2 places governed remediation in Enterprise / Release 1.2, and section 18 says to keep it limited until the security model is mature). Three existing tests had been silently assuming remediation was always available; they now enable the flag explicitly, making the precondition visible.

---

### AF-14 resolution — documentation corrected

- `CONFIGURATION.md` claimed `AEIR_Admin` "already references an AEIR utility bar". It does not; replaced with the actual Setup procedure and a pointer to AF-02.
- `IMPLEMENTATION_COVERAGE_REPORT.md` listed the two deleted events as implemented; corrected to the five events that exist.
- `AUDIT_REPORT.md` and `AEGIS_FLOW_PACKAGE_REVIEW.md` both stated no org validation was possible. Marked superseded, since deployment, the Apex suite, and a live smoke test have all now run against `Aegis Flow_WA_Dev`.

---

### AF-16 resolution — jobs scheduled

Both schedulers are now registered in the org and in `WAITING` state:

| Job | Cron | Next fire |
|---|---|---|
| Aegis Flow Retention Purge | `0 0 2 * * ?` (daily 02:00) | 2026-07-28 |
| Aegis Flow Async Job Monitor | `0 15 * * * ?` (hourly) | 2026-07-27 |

The scheduling script is idempotent — it skips any job already registered, so it is safe to re-run.

---

### AF-17 resolution — quarantined events deleted

**Decision:** permanently delete `Remediation_Requested__e` and `Retry_Process_Requested__e`. Remediation and retry stay **synchronous** so `isUpdateable()` and `UserInfo.getUserId()` evaluate against the acting user's profile rather than Automated Process. The latency worth solving is the AI callout, not the DML.

Removed from `optional-metadata/custom-object-limit-excluded/`: both event definitions (9 field files), `AEIR_RemediationRequestedEventHandler`, `AEIR_RetryProcessRequestedEventHandler`, and both event triggers. Neither event had ever been deployed, so no destructive deploy was required. Two stale duplicates were removed at the same time — the quarantined `AEIR_BatchApexErrorEventTrigger` and `AEIR_FailingBatchTestHelper`, both superseded by the versions now in `force-app` (the quarantined helper used the `Database.QueryLocator` form that does not raise the event in test context).

`IMPLEMENTATION_COVERAGE_REPORT.md` was corrected — it had listed both events as implemented.

---

### AF-25 resolution — bulk safety

**1. `AEIR_FindRecentErrorsAction` — SOQL in a loop.** Rewritten to collect record IDs and object names across the whole request list, issue **at most three queries per invocation**, bucket results, then map them back by request. Coverage 70% → **100%**.

New regression test `findRecentErrorsIsBulkSafe` invokes the action with **152 requests** and asserts `Limits.getQueries()` stays at or below 3. The previous implementation would have thrown `Too many SOQL queries: 101` on this input.

**2. `AEIR_SecuritySanitizerService` — uncached metadata and per-call regex allocation.** `Sensitive_Field__mdt` is now cached in a `private static` resolved once per transaction, and the seven built-in secret patterns moved to a `static final` list instead of being rebuilt on every call. A 200-event subscriber batch previously performed ~1,600 metadata queries and ~11,000 regex operations.

*Recorded for accuracy:* custom metadata queries do **not** count against the SOQL governor limit, so this was never going to throw `Too many SOQL queries`. The real exposure was **CPU time**, driven by regex volume.

---

## Fixed during the July 27, 2026 audit

For reference, these were found and resolved:

- **AF-C1** — `AEIR_BatchApexErrorEventTrigger` was never deployed, leaving `AEIR_BatchApexErrorEventHandler` as dead code. Deployed and added to `manifest/package.xml`.
- **AF-C2** — No permission sets were assigned to any user in the org. Five assigned to the admin user.
- **AF-C3** — `User_Notification__c`, `Incident__c`, and `Delivery_Attempt__c` had object permissions but **zero field permissions** across all six permission sets — every field on the notification object was invisible, so tabs, list views, and reports rendered empty. Added 38 field permissions per permission set and deployed.
- **AF-08** — `AEIR_BatchApexErrorEventTrigger` had 0% coverage and would have blocked any production or packaging deploy. Resolved; see below.
- **AF-17** — both quarantined platform events deleted by decision; writes stay synchronous. See the AF-17 resolution above.
- **AF-25** — SOQL-in-a-loop in an invocable action, and uncached masking metadata. See the AF-25 resolution above.

### AF-08 resolution — batch trigger coverage

**Files:** `force-app/main/default/classes/AEIR_BatchApexErrorTriggerTest.cls`, `AEIR_FailingBatchTestHelper.cls`

`BatchApexErrorEvent` cannot be constructed and published directly — its fields are not writeable (`Field is not writeable: BatchApexErrorEvent.AsyncApexJobId`). The trigger is instead covered by letting a real batch fail and then draining the queued event:

1. A top-level `@IsTest` batch implements `Database.Batchable<SObject>` **and** `Database.RaisesPlatformEvents`, and divides by zero in `execute()`.
2. `Test.stopTest()` is wrapped in `try/catch` so the intentional crash does not fail the test.
3. `Test.getEventBus().deliver()` drains the queued `BatchApexErrorEvent` into the trigger.
4. The test asserts one `Error_Log__c` with `Source_Type__c = 'Batch'`, `Severity__c = 'High'`, and a `BATCH-` correlation ID.

**Two constraints worth recording, both found the hard way:**

- **`start()` must return `Iterable<SObject>`, not `Database.QueryLocator`.** With a `QueryLocator` the event is never raised in test context and the assertion finds zero logs. This is the single decisive detail.
- **The mock batch must be a top-level class.** An inner class fails to compile: *"Only top-level classes can implement Database.Batchable&lt;SObject&gt;"*.

**Result:** `AEIR_BatchApexErrorEventTrigger` and `AEIR_BatchApexErrorEventHandler` are both at **100%**. All five triggers are now at 100%, and org-wide coverage is 78%. The superseded artificial handler test in `AEIR_ReconciledFeaturesTest` was removed.


---

## AF-27 / AF-28 / AF-29 resolution — escalation bulk refactor, July 29, 2026

`AEIR_EscalationService` was the last single-record service in the product. Refactoring it to
a bulk signature exposed two further defects that no test had ever reached, both hidden by the
same mechanism: `allOrNone = false` DML.

### AF-27 · Dispatch cost scaled with record count

Each escalation cost roughly five DML statements (insert escalation, insert audit, update
escalation, update audit, update log) plus a record-snapshot query. A platform-event batch or
an invocable action handling more than about thirty records exhausted DML limits — and that
happens precisely when the org is unhealthy and escalation matters most.

Everything now flows through `createForErrors(List<Id>, String, Boolean)`. Routes are cached
per transaction, snapshots are batched per object via the new
`AEIR_ContextSnapshotService.getSnapshots(Map<String, Set<String>>, Boolean)`, and `dispatchAll`
collects each channel before flushing it once: one `Messaging.sendEmail`, one Case insert, one
Case query, one status update, one audit insert. `createForError` and `createForSession` delegate
to the same path so the single-record and bulk behaviours cannot diverge.

Measured in `AEIR_EscalationBulkTest.bulkEscalationCostIsBounded`: 60 error logs cost ≤12 queries,
≤12 DML and exactly 1 email invocation.

### AF-28 · `Case.Origin = 'Aegis Flow'` is not a valid picklist value

`Origin` is a restricted picklist on a standard object, and a stock org ships `Phone, Email, Web`.
Setting it unconditionally made every Case-channel escalation fail
`INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`, and because the insert used `allOrNone = false` the
failure was silent: no Case, no error, no ticket number. The Case channel is Release 1 scope
(spec §18) and it had never worked in a clean org.

`caseOriginSupported()` now describes the picklist once per transaction and sets `Origin` only
when the admin has actually added the value. Adding `Aegis Flow` to Case Origin remains a
recommended install step, but skipping it no longer costs the customer their escalations.

### AF-29 · Delivery audits were discarded for Case and connector channels

`Delivery_Audit__c.Channel__c` and `Developer_Escalation__c.Channel__c` do not share a value set:
the audit object spells the Case value **`Salesforce Case`**, and it had no `Pending` status at
all. Writing the escalation's spelling straight through failed the restricted picklist, so
**every Case escalation and every unimplemented-connector escalation produced no audit record**.
The connector branch exists specifically so an undelivered escalation leaves a trace; it was
leaving none, and the console showed a clean delivery history for messages that never went out.

Three changes:
- `Pending` added to `Delivery_Audit__c.Status__c` and to `Developer_Escalation__c.Status__c`
  (the escalation status was rejected for the same reason, leaving connector escalations stuck
  on `New` and indistinguishable from undispatched ones).
- `auditChannel()` maps the escalation spelling to the audit spelling and falls back to `Other`,
  so an audit row always exists whatever the channel.
- `reportPartialFailures()` now logs any row rejected by a partial-success DML. This is the
  general fix: `allOrNone = false` protects the batch but hides the casualty, and that is what
  concealed all three defects here.

### Coverage

`AEIR_EscalationService` moved from **67% to 92%** (257/280 lines).
`AEIR_EscalationBulkTest` adds 13 tests covering bulk cost, the Email/Case/Pending/None channel
branches, invalid recipients, unknown route keys, and both `createForSession` paths.
Org-wide coverage moved from 85% to **88%**, 92 tests, all passing.


---

## AF-30 resolution — every batch entry point made bulk-safe, July 29, 2026

A repeat scan for expensive calls inside loops found 17 hits. Three were false positives (a
query in a `for` header, which runs once; a prefetched map lookup). The other 14 were real, and
they shared one shape: **an entry point the platform hands a batch to, calling a single-record
service in a loop.**

This matters more here than in ordinary code. Platform events are delivered in batches of up to
200 and Flow calls an invocable action once with every record in its batch. Aegis Flow's own
events fire *during an error storm* — precisely when the org is least healthy — so the failure
mode was: limit exceeded, batch retried, batch discarded, and no one is told anything.

### Fixed

| Entry point | Was | Now |
|---|---|---|
| `AEIR_EscalationRequestedEventHandler` | `createForError` per event | grouped by route key, one bulk call each |
| `AEIR_AgentDiagnosisRequestedEventHandler` | `diagnoseError` per event (~6 ops) | one `diagnoseErrors` / `diagnoseSessions` call |
| `AEIR_DiagnosticSessionRequestHandler` | `createSession` per event | one `createSessions` call |
| `AEIR_CreateEscalationAction` | `createForError` per request | grouped by route key + send flag |
| `AEIR_InvokeDiagnosisAction` | `diagnoseError` per request | one bulk call, matched back by id |
| `AEIR_GetErrorContextAction` | 4 queries per request, died at 25 | 4 queries for the whole batch |
| `AEIR_GetRecordSnapshotAction` | 1 query per request | batched per object, split on `forEscalation` |

New bulk APIs: `AEIR_EscalationService.createForSessions`, `AEIR_AgentforceGatewayService.diagnoseErrors`
and `diagnoseSessions`, `AEIR_DiagnosticSessionService.createSessions`,
`AEIR_UserNotificationService.notifyDiagnosisCompleteAll`. Every single-record entry point now
delegates to its bulk counterpart, so the two cannot diverge in behaviour.

### Two related defects found while fixing it

- **Results were returned in SOQL order, not input order.** `createForErrors` returns results
  ordered by the query, so an invocable matching responses to requests by list position would
  mislabel them. `EscalationResult` now carries `errorLogId` and `diagnosticSessionId`, and
  callers correlate on those.
- **`buildPayload` still queried a snapshot per log.** Diagnosis was batched everywhere else,
  and the suite still failed with `Too many SOQL queries: 101` at 100 logs. Snapshots are now
  prefetched per object and passed in. This is only visible in a test that asserts *cost*.

### Deliberately left per-record

`AEIR_ExecuteRemediationAction` and `AEIR_UpdateMissingFieldAction` remain per-record. The
orchestrator enforces the whitelist, CRUD/FLS and the confirmation flag for one field on one
record and writes an individually approved audit row; batching those writes would mean one
approval covering a set, which is the governance the spec requires it not do. The real exposure
was a limits failure part-way through, leaving some customer records changed and no way to tell
which — so the batch is now **capped at 40 and anything larger is refused up front** with an
explicit message, rather than half-applied.

### Verification

`AEIR_BulkEntryPointTest` adds 15 tests asserting **measured** query and DML cost, not merely
that the path runs — a loop-based implementation passes a functional test right up until it
hits the limit. 100 events through each subscriber stay within ~15 queries and ~15 DML; 100
requests through `GetErrorContextAction` use ≤10 queries where the old code needed 400.

**107 tests, all passing, 87% org-wide.** A re-scan leaves 4 hits, all of them the two capped
remediation loops, which are intentional and tested.

### Operational checks (review plan Blocks C and D)

- 13 evidence objects all `Private`; `Aegis_Org_Setting__c` correctly has no sharing model.
- 6 Aegis scheduled jobs `WAITING` with sane next-fire times.
- `AEIR_FlowCoverageService.scan()` → `uncapturedFailures = 0`.
- Schema regenerated: 31 objects, 290 fields. The only drift is today's two `Pending` picklist
  values plus two fields added after the last generation. Nothing unexpected.
- Health check: **7 PASS / 2 WARNING / 1 FAIL.** The FAIL and one WARNING are both AF-15 —
  onboarding not completed and `DEFAULT_ADMIN_EMAIL` still on `admin@example.com`. That needs
  real addresses from you; it is configuration, not code.


---

## AF-15 closed for real — escalation recipients configured, July 29, 2026

AF-15 was marked fixed on July 28 when the onboarding wizard and recipient-resolution logic
were built, but the health check still reported **1 FAIL** because the org itself had never been
onboarded and both escalation routes still pointed at `admin@example.com` / `devteam@example.com`.
Shipped code, unconfigured org.

Now set:

| Setting | Value |
|---|---|
| Company name | The Lodestone Group |
| Developer team email | wahid@thelodestonegroup.com |
| Admin team email | wahid@thelodestonegroup.com |
| Fall back to system admins | true |
| Onboarding completed | 2026-07-29 |

Both `Escalation_Route__mdt` records were updated in source as well, so the repo no longer ships
placeholder recipients. `resolveRecipients('Developer')` now returns the configured address with
`usingFallback = false`.

**Health check: 9 PASS / 1 WARNING / 0 FAIL** (was 7/2/1).

The remaining WARNING is informational: `AI_DIAGNOSIS`, `CONNECTOR_EXTENSIONS` and
`GOVERNED_REMEDIATION` are disabled. The first two are deferred by decision (AF-23, and the
unbuilt connectors). `GOVERNED_REMEDIATION` is a live product decision still open — enabling it
turns on one-click field correction, which writes to customer records.

**Escalations now send real email to a real inbox.** Anything that triggers a High or Critical
capture in this org will reach that address.


---

## Decisions taken July 29, 2026

**1. Test fixtures stay.** `Aegis_Require_Lead_Source` (Contact) and
`Aegis_Test_Order_On_Closed_Won` (Opportunity) remain active by decision. They are the QA
harness. Consequence to keep in mind: **no Opportunity in this org can be moved to Closed Won
without the Flow failing**, and every such failure now emails a real inbox. Anyone else working
in this org will hit both.

**2. Item 1 (custom LWC record form) — on hold.** Not to be built yet. Instead, a QA test plan
covering Lead, Contact, Opportunity and Order was produced: `docs/QA_TEST_PLAN.md`.

**3. AF-22 scope defined** (work not started, on hold):
- Outline user roles and permissions
- Brief documentation / training material for the team
- Pick an official go-live launch date

---

## QA test plan delivered — `docs/QA_TEST_PLAN.md`

19 test cases across Lead, Contact, Opportunity, Order, plus bulk, security and policy.

The plan leads with the **capture-boundary section**, because that is where QA time is most
likely to be wasted. Three cases are deliberately **negative** — TC-C-01, TC-C-03 and TC-L-01
assert that Aegis does *not* fire, because a validation rule on a direct save and a failed Lead
Convert are rejected by the platform before any automation runs. Without that framing QA would
file all three as defects on day one.

The plan also states plainly which cases are **blocked**: every remediation case depends on
`GOVERNED_REMEDIATION`, which is off. Rather than leaving QA to discover that by finding a
missing button, it is called out in the preconditions.

The helper snippet in §9 was **executed against the live org and its expected output recorded
from the actual result** — including a correction, since the real category is `Validation Rule`
rather than the value first written down. Probe rows were deleted afterwards.
