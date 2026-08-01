# Aegis Flow — Session State and Review Plan

**Purpose:** durable record of where the implementation actually stands, what was learned the
hard way, and what still needs doing. Written so that if conversation context is lost, this
file alone is enough to pick the work back up without re-deriving anything.

**Last verified:** July 29, 2026 against org `Aegis Flow_WA_Dev` (`00DgL00000YDvsvUAD`)

---

## 1. ⚠️ Live test fixtures — read this first

Two artifacts are **active in the org right now**. They are test fixtures, deliberately
kept outside `force-app`, and they change org behaviour:

| Fixture | Effect | How to remove |
|---|---|---|
| `Aegis_Test_Order_On_Closed_Won` (Flow) | Creates an Order with `AccountId` unmapped, so it always fails. **Changed 2026-07-29: a fault path now catches it, so the Opportunity save SUCCEEDS** and the failure is captured in seconds with the record id. Needs ≥1 Opportunity line item to fire at all. | Setup → Flows → Deactivate. See §5 for the deactivation trap. |
| `Aegis_Require_Lead_Source` (Contact validation rule) | Blocks Contact create/save without Lead Source. Also blocks **Lead Convert** when the Lead has no Lead Source. | Setup → Object Manager → Contact → Validation Rules → deactivate |

Neither is in the product package.

**Decision, July 29, 2026: both fixtures STAY.** They are the QA harness for `docs/QA_TEST_PLAN.md`.
This supersedes the earlier "remove before handover" instruction. Consequences to keep in mind:
no Opportunity in this org can reach Closed Won without the Flow failing, every such failure now
emails a real inbox, and anyone else working in this org will hit both.

---

## 2. Verified current state

| Metric | Value |
|---|---|
| Apex classes | 64 |
| Apex triggers | 5 (all at 100% coverage) |
| LWC bundles | 12 |
| Objects / events / CMDT | 31 |
| Permission sets | 6 |
| List views (`All`) | 13 |
| Apex tests | **107 passing, 100%** |
| Jest tests | **13 passing, 100%** |
| Org-wide coverage | **87%** |
| Full-source deploy | 471 components, 0 errors |
| Scheduled jobs | 6 (retention, async monitor, 4× flow interview monitor) |
| API version | 67.0 |
| Docs | 15 markdown files |

**Commands to re-verify all of the above:**

```bash
sf apex run test --test-level RunLocalTests --target-org "Aegis Flow_WA_Dev" --code-coverage --result-format human --wait 40
npx sfdx-lwc-jest -- --silent
python3 scripts/local_audit.py
sf project deploy start --source-dir force-app --target-org "Aegis Flow_WA_Dev" --dry-run --test-level NoTestRun --wait 30
```

---

## 3. Capture architecture — what actually works

Three independent paths, deliberately layered. **Aegis captures automation failures.**

| Path | Trigger | Instrumentation | Latency | Record ID? |
|---|---|---|---|---|
| **Real-time Flow** | `FlowExecutionErrorEvent` → LWC empApi → `captureFlowError()` | **None** | Seconds — **browser-dependent, see below** | ✅ `ContextRecordId` |
| **Polled Flow** | `FlowInterview` → `AEIR_FlowInterviewMonitor` | **None** | ≤ 5 min (testing) / ≤ 15 min | ❌ |
| **Fault path** | Flow fault → `Error_Captured__e` | Per Flow | Instant | ✅ |
| **Apex** | `AEIR_Guard.capture()` | One line | Instant | ✅ |
| **Batch** | `BatchApexErrorEvent` trigger | `Database.RaisesPlatformEvents` | Instant | ❌ |
| **Async jobs** | `AEIR_AsyncJobMonitorScheduler` | **None** | ≤ 15 min (testing) / ≤ 1 hour | ❌ |
| **Custom LWC** | `errorBoundaryWrapper` | Wrap component | Instant | ✅ |
| **Integration** | REST endpoint | Caller posts | Instant | ✅ |

Real-time and polled paths share correlation id `FLOWINT-<InterviewGuid>`, and
`Correlation_Id__c` is a unique external id, so **they cannot double-capture**.

### ⚠️ The real-time path is browser-dependent — corrected July 29, 2026

`FlowExecutionErrorEvent` has `IsTriggerable = false` (verified against `EntityDefinition`), so
**no Apex trigger can subscribe to it**. The only subscriber is the headless monitor LWC over
empApi — client side, in a browser tab.

Earlier revisions of this table said "Instant" with no qualifier. That overstated it. The
seconds-latency path fires **only while at least one user has a tab open on an app carrying the
Aegis utility bar.** Overnight failures, integration-user activity, and anything happening when
nobody is logged in fall through to the 15-minute poller.

| Path | Typical | Worst case | Works with nobody logged in? |
|---|---|---|---|
| Flow — utility bar streaming | seconds | seconds | ❌ **No** |
| Flow — `FlowInterview` poller | ~7 min | 15 min | ✅ Yes |
| Apex via `AEIR_Guard` | seconds | seconds | ✅ Yes |
| Batch Apex (`BatchApexErrorEvent`) | seconds | seconds | ✅ Yes |
| Failed async job poller | ~30 min | **60 min** (cron `0 15 * * * ?`, hourly) | ✅ Yes |

**This is a structural limit, not a tuning problem.** If "Aegis must know within seconds
regardless of who is logged in" becomes a product requirement, it is a design conversation.
Open tuning options: async monitor hourly → 15 min (4 jobs), Flow poller 15 min → 5 min
(12 jobs, 12 of the org's 100 scheduled-Apex slots).

### ❌ Not capturable by any package — confirmed by experiment

- Validation rule blocking a **direct record save** (platform rejects before Apex/Flow runs)
- Validation rule blocking **Lead Convert** — verified via browser network trace:
  handler is `LeadConvertDesktopController/ACTION$convertLeadServer`, a Salesforce-internal
  Aura controller with no package hook. Error returns in the HTTP response, never a record.

Only a custom LWC replacing the standard form could capture the first. Nothing practical
captures the second. **This is a product boundary, not a bug.**

---

## 4. Built this session

- **AF-01** Flow fault subflow made functional (was an empty `InvalidDraft` shell)
- **AF-02** Utility bar deployable; now on Sales, Service, Sales Console, Aegis Flow Admin
- **AF-03** Notification policy enforced — severity, cooldown, hourly cap, critical bypass
- **AF-04** `AEIR_IncidentAggregationService` — 500 failures collapse to 1 incident
- **AF-05** Feature flags enforced
- **AF-06** Jest infrastructure + 13 tests
- **AF-07/08** Coverage; batch trigger covered via `Test.getEventBus().deliver()`
- **AF-09/19** Custom permissions; REST endpoint hardened (403 + payload cap)
- **AF-10** Salesforce Case escalation route; unimplemented connectors log `Pending`
- **AF-11** `AEIR_SetupHealthCheckService` — 10 checks + self-cleaning live probe
- **AF-12/13** All remaining CMDT wired; feedback + attachments implemented
- **AF-14** Documentation corrected
- **AF-15** Onboarding wizard, `Aegis_Org_Setting__c`, recipient fallback chain
- **AF-16** Retention + async monitor scheduled
- **AF-17** Quarantined events deleted; writes stay synchronous
- **AF-18** Command Center 4 → 11 metrics
- **AF-21** API 60 → 67
- **AF-24** Async diagnosis round trip (Detected → Diagnosed in place)
- **AF-25** Bulk safety: SOQL-in-loop fixed, masking metadata cached
- **AF-26** Non-admin journey unblocked (5 separate permission blockers)
- **New** `FlowExecutionErrorEvent` real-time capture, `AEIR_Guard`, `AEIR_FlowCoverageService`,
  `AEIR_FlowInterviewMonitor`, data model doc generator, 13 list views

---

## 5. Platform lessons — do not re-derive these

Each of these cost real time to discover.

| Lesson | Detail |
|---|---|
| **Deactivating a Flow** | Deploying `<status>Draft</status>` creates **v2 and leaves v1 active**. Must deploy `FlowDefinition` with `<activeVersionNumber>0</activeVersionNumber>`. Then delete versions via Tooling API; v1 won't delete while `FlowInterview` rows reference it. |
| **Utility bar FlexiPage** | Item properties need `<type>decorator</type>`. Without it: *"Invalid property [label]"*; with the property absent: *"missing required decorator property"*. Valid decorators: `label`, `icon`, `width`, `height`, `eager`, `scrollable`. No LWC change needed. |
| **Permission set XML** | `fieldPermissions` elements must be **contiguous**, or deploy fails *"Element fieldPermissions is duplicated"*. Same for other repeated element types. |
| **Apex reserved words** | `group` and `on` cannot be identifiers. |
| **Batchable** | Inner classes cannot implement `Database.Batchable` — must be top-level. |
| **BatchApexErrorEvent test** | Only coverable if the mock batch's `start()` returns **`Iterable<SObject>`**, not `QueryLocator`. Then catch the exception around `Test.stopTest()` and call `Test.getEventBus().deliver()`. |
| **CMDT and governor limits** | Custom metadata SOQL does **not** count against the SOQL limit. Caching it is a CPU optimisation, not a limit fix. |
| **Platform event triggers** | Cannot make callouts synchronously — must enqueue a `Queueable` with `Database.AllowsCallouts`. |
| **`FlowExecutionErrorEvent`** | `IsTriggerable = false`, not SOQL-queryable. Streaming only — subscribe via empApi in the browser. |
| **`Error_Captured__e`** | `publishBehavior = PublishImmediately`, which is why evidence survives a rollback. Do not change this. |
| **npm in this repo** | Every `npm install` errors `ERR_INVALID_ARG_TYPE` because the folder path contains `&` (`Internal POC & R&D`). **The install still succeeds**; only `package.json` fails to update. Sync it by hand, or rename the folder. |
| **Rollback-safe capture** | `AEIR_Guard.capture()` publishes (survives rollback). `captureNow()` does direct DML. Capture-then-rethrow **must** use `capture()`. |
| **`allOrNone = false` hides casualties** | Partial-success DML protects the batch but a rejected row vanishes without a word. This single pattern concealed three separate defects (AF-28, AF-29). Always report rejects — `AEIR_EscalationService.reportPartialFailures()` is the model. |
| **Picklist value sets differ across objects** | `Developer_Escalation__c.Channel__c` spells it `Case`; `Delivery_Audit__c.Channel__c` spells it **`Salesforce Case`**. Writing one into the other failed a restricted picklist silently. Never assume two same-named picklists share a value set — map explicitly with an `Other` fallback. |
| **`Case.Origin` is restricted** | A stock org ships `Phone, Email, Web`. Setting `Origin = 'Aegis Flow'` unconditionally made every Case escalation fail `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`. Describe the picklist before writing a value to a standard field. |
| **Bulk results come back in SOQL order** | `createForErrors()` returns results ordered by the query, **not** by input order. A caller matching responses to requests by list position mislabels them. Correlate on an id the result carries. |
| **`Group` is a reserved word** | Same family as `group` and `on`. An inner class cannot be named `Group`. |
| **Functional tests miss limit bugs** | A loop-based implementation passes a functional test right up until it hits the governor limit. Bulk tests must assert **measured** `Limits.getQueries()` / `getDmlStatements()`, not just that the path ran. |

---

## 6. Still open

| ID | Item | Blocker |
|---|---|---|
| **Item 1** | Custom LWC record form to capture validation-rule saves | **On hold by decision, July 29.** QA plan delivered instead |
| AF-22 | GTM: (a) user roles/permissions outline, (b) team documentation/training, (c) official go-live date | **Scope defined July 29; work not started, on hold** |
| AF-20 | Namespace / 2GP packaging | **Deferred by decision.** Follow `NAMESPACE_READINESS.md` meanwhile |
| AF-23 | Real Agentforce callout | **Deferred by decision** — deterministic fallback is intentional |

**Unverified assumption:** whether subscribing to `FlowExecutionErrorEvent` requires extra
permission in this org. The LWC degrades silently to the poll if refused. Confirm by running
the Closed Won test with the utility bar open — an instant toast means the subscription works.

---

## 7. Review plan — status

Blocks A–D are complete. Findings became AF-27 … AF-30 in `OPEN_ISSUES.md`.

### Block A — Correctness ✅ complete
- [x] Re-run verification commands — 2026-07-29: **107 Apex + 13 Jest green, 87% org-wide**
- [x] `AEIR_ErrorCaptureService` — capture vs publish paths, incident assignment
- [x] `AEIR_NotificationPolicyService` — cooldown holds under bulk
- [x] `AEIR_IncidentAggregationService` — key stability, 60-min bucket
- [x] `AEIR_FlowInterviewMonitor` + `captureFlowError()` — dedupe confirmed via shared `FLOWINT-` id
- [x] `AEIR_Guard.capture()` is publish-based at every call site

### Block B — Security ✅ complete
- [x] `@AuraEnabled` CRUD/FLS and sharing
- [x] `AEIR_RemediationOrchestrator` dynamic SOQL is whitelist-bound — re-confirmed
- [x] `AEIR_SecuritySanitizerService` masking on every outbound path
- [x] `Aegis_User_Alert__e` carries no stack traces or record values
- [x] Non-admin journey as a Standard User

### Block C — Data model
- [x] Regenerate `npm run docs:datamodel`; diff for unexpected schema drift — 2026-07-29: no unexpected drift (31 objects, 290 fields)
- [x] Confirm all 10 evidence objects still `Private` sharing — 2026-07-29: all 13 Private
- [x] Check every new field has FLS in all 6 permission sets — 2026-07-29: no new fields added; only two picklist values (`Pending` on `Developer_Escalation__c.Status__c` and `Delivery_Audit__c.Status__c`), which do not require FLS changes

### Block D — Operational
- [x] Confirm 6 scheduled jobs still `WAITING` with sane next-fire times — 2026-07-29: all 6 WAITING
- [x] Run the health check — 2026-07-29 **final: 9 PASS / 1 WARNING / 0 FAIL** after onboarding was completed. (Earlier the same day: 7/2/1.) The remaining WARNING is informational — three feature flags off, two deferred by decision and `GOVERNED_REMEDIATION` awaiting a product call.
- [x] Run `AEIR_FlowCoverageService.scan()` — 2026-07-29: `uncapturedFailures` is 0

### Block E — Cleanup before handover
- [x] ~~Remove both test fixtures~~ — **reversed by decision July 29: fixtures stay.** See §1
- [x] Replace placeholder escalation recipients — 2026-07-29: onboarding completed, both routes now `wahid@thelodestonegroup.com`, `usingFallback = false`
- [x] Decide the pilot object for Item 1 — **on hold**; QA scope is Lead, Contact, Opportunity, Order per `docs/QA_TEST_PLAN.md`
- [x] Update `OPEN_ISSUES.md` progress counts — 30 fixed, 1 open (AF-22), 2 deferred
- [ ] **AF-22 GTM** — roles/permissions, training docs, launch date. Scope agreed, work not started

### Block F — Bulk safety sweep ✅ complete (added July 29)
- [x] Re-scan all classes for expensive calls inside loops — 17 hits, 3 false positives
- [x] Bulk-safe every platform event subscriber and invocable action → **AF-30**
- [x] `AEIR_EscalationService` refactored to a bulk signature, 67% → 92% coverage → **AF-27**
- [x] `Case.Origin` restricted-picklist failure → **AF-28**
- [x] Delivery audits silently discarded for Case/connector channels → **AF-29**
- [x] `AEIR_BulkEntryPointTest` + `AEIR_EscalationBulkTest` — 28 tests asserting measured limits

---

## 8. Key files

| Area | File |
|---|---|
| Issue tracker | `docs/OPEN_ISSUES.md` |
| Data model + diagrams | `docs/DATA_MODEL_AND_PROCESS_FLOW.md` (regenerate: `npm run docs:datamodel`) |
| Event design + FLS finding | `docs/EVENT_ARCHITECTURE_PROPOSAL.md` |
| Namespace standard | `docs/NAMESPACE_READINESS.md` |
| QA test plan (19 cases, Lead/Contact/Opp/Order) | `docs/QA_TEST_PLAN.md` |
| This file | `docs/SESSION_STATE_AND_REVIEW_PLAN.md` |


---

## 9. July 29, 2026 — fault path, poller cadence, and the LWC null crash

### Flows: split into a with-fault and a no-fault pair (final state)

There are now **two** Opportunity fixtures, mutually exclusive on the Opportunity **Name**, both
active — so neither has to be deactivated to test the other:

| Flow | Fires when Name... | Save | Capture | Record id |
|---|---|---|---|---|
| `Aegis_Test_Order_On_Closed_Won` | does **not** contain `AEGIS_FAULT` | **rolls back** | `FLOWINT-` poller | ❌ none |
| `Aegis_Test_Order_On_Closed_Won_With_Fault` | contains `AEGIS_FAULT` | **succeeds** | `FLOW-` instant | ✅ yes |

Verified side by side. `Name` is used as the switch because `Description` is a Long Text Area and
Salesforce rejects it in an entry-condition formula.

### Original single-fixture note (superseded by the pair above)

`Aegis_Test_Order_On_Closed_Won` had **no fault connector**, which is the whole reason TC-O-01
depended on the 15-minute poller. A `faultConnector` on `Create_Order_Without_Account` now calls
`Aegis_Error_Capture_Fault_Subflow`.

Verified end to end: captured in **under 10 seconds** with `Record_Id__c` = the Opportunity id,
`Error_Category__c` = `Missing Data`, source `Aegis_Test_Order_On_Closed_Won / Create_Order_Without_Account`.

**Behaviour change to be aware of:** a Flow with a fault path *handles* the error, so the
**Opportunity save now succeeds** instead of rolling back. Better for QA — Closed Won is no
longer globally blocked — but it changes what TC-O-01 asserts, and the "blocks every Closed Won
save" warning in §1 no longer applies. Remove the fault connector to restore the old behaviour.

**No invocable contract broke.** Today's bulk refactor added `@InvocableVariable` fields but
removed none, so every existing Flow binding still resolves. No other Flow needs updating.

### Poller cadence — why 1 minute was not the answer

Scheduled Apex fires at most hourly **per job**, so "every N minutes" = 60/N jobs. Every-1-minute
would need 60 jobs per poller — 120 of the org's 100 slots. It does not fit, and it would not
help: **a poller can never recover the record id**, so no snapshot reaches the escalation package
however often it runs. Polling is the backstop; a fault path is the fix.

**Currently set to RAPID by request: Flow every 1 min (60 jobs), async every 15 min (4 jobs) =
64 of the org's 100 scheduled-Apex slots** (69 total in use). It fits, but it leaves little
headroom and runs 60 reconciliations an hour whether or not anything failed. **Switch back to
`TESTING` or `NORMAL` when the test window closes.**

- `scripts/set_poller_cadence.apex` — flip `MODE` to `NORMAL` when testing ends
- `scripts/run_pollers_now.apex` — runs both immediately; usually what you actually want mid-test

### LWC crash: `Cannot read properties of undefined (reading 'Severity__c')`

`aegisHeadlessMonitor.html` rendered `{detail.errorLog.Severity__c}` directly. **LWC templates do
not optional-chain**, so a null `errorLog` killed the whole panel.

`errorLog` is legitimately null: `User_Notification__c.Error_Log__c` is `deleteConstraint = SetNull`,
so the retention purge deletes the Error Log and leaves the notification pointing at nothing.

Fixed with flattened null-safe getters, a purged-evidence fallback view, Escalate/Get Help hidden
when there is no log to package, and a list-based Apex query (the bare `SELECT ... LIMIT 1` into an
sObject would throw `QueryException` under sharing). Three Jest regression tests; the fix was
verified by reverting the template and confirming the original error reproduces.

**Fourth instance of the same family today:** a null/absent value no happy-path test produces.
See also the `allOrNone = false` lesson in §5.

### New docs

| File | Purpose |
|---|---|
| `docs/ERROR_CATALOG.md` | Every error category, grouped, with covered / partial / out-of-scope marked |
| `docs/QA_TEST_PLAN.md` | 19 QA cases across Lead, Contact, Opportunity, Order |
