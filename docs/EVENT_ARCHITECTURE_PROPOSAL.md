# AF-17 — Event Architecture & Payload Proposal

**Status:** For review. No code written yet.
**Date:** July 27, 2026
**Relates to:** AF-17 (quarantined events), AF-03 (notification policy), AF-04 (incident grouping)

---

## 1. Read this first: the quarantined events do not serve the stated use case

The real-time "LWC pops up → spinner → AI answer pushed back" round trip is a **different pair of events** from the two in quarantine. Restoring `Remediation_Requested__e` and `Retry_Process_Requested__e` will not produce that behaviour.

| Event | Purpose | Deployed? | Trigger live? | Anything publishes it? |
|---|---|---|---|---|
| `Agent_Diagnosis_Requested__e` | **Async "please diagnose this"** | Yes | Yes | **No** — only `AEIR_CoreTest` |
| `Aegis_User_Alert__e` | **Browser push to the LWC** | Yes | n/a (empApi) | Yes, but only as `Detected` |
| `Remediation_Requested__e` | Async *write* — execute a registered field update | No (quarantined) | No | No |
| `Retry_Process_Requested__e` | Async *write* — invoke a registered retry handler | No (quarantined) | No | No |

**The async diagnosis pipeline is already built and deployed.** `AEIR_AgentDiagnosisRequestedEventTrigger` → `AEIR_AgentDiagnosisRequestedEventHandler` → `AEIR_AgentforceGatewayService` is live in the org right now. `aegisHeadlessMonitor.js` already subscribes to `/event/Aegis_User_Alert__e` and already filters by user.

What is missing is **two publish calls**, not two events:

1. Nothing ever publishes `Agent_Diagnosis_Requested__e` in production code, so the async diagnosis never starts.
2. `AEIR_UserNotificationService` only ever writes `Notification_Type__c = 'Detected'` ([line 49](../force-app/main/default/classes/AEIR_UserNotificationService.cls#L49)). It never publishes a second `Diagnosed` alert when diagnosis completes, so the spinner would never resolve.

The spec anticipated exactly this shape — §6.5 defines both messages: *"A background process encountered an issue. Aegis Flow is analyzing it now."* (Diagnosing) and *"I have identified the issue…"* (Diagnosed).

**Recommendation:** treat the diagnosis round trip and the remediation/retry restoration as two separate pieces of work. The first is the one that unblocks the product demo, and it is much smaller than it looks.

---

## 2. There are currently zero Agentforce callouts

`AEIR_AgentforceGatewayService` makes **no HTTP callout of any kind**. It runs deterministic string classification and writes `AI_Diagnosis__c` with `Agent_Status__c = 'Deterministic Fallback'`. A repo-wide scan finds no `HttpRequest`, no `new Http()`, and no `callout:` reference anywhere in `force-app`.

Two consequences for the action items:

- **Callout chunking is not yet a problem** — there is nothing to chunk. The prerequisite is building the gateway (Named Credential, prompt contract, response validation per §10.3). Worth tracking as its own issue.
- **A hard constraint applies once callouts exist:** a platform event trigger **cannot make a callout synchronously**. The subscriber must enqueue a `Queueable` (implementing `Database.AllowsCallouts`) and make the callout there. This should be settled in the design, not discovered in implementation.

### On the "500 failed records" scenario

Chunking 500 callouts is the wrong lever. Under §8.1 those 500 failures collapse into **one `Incident__c`** sharing an incident key, and we diagnose the incident once — not 500 times. That is one callout, not 500.

That makes **AF-04 (incident aggregation) a prerequisite** for the bulk story. Without it, we are chunking work that should never have been created. Recommend sequencing AF-04 before the callout work.

---

## 3. Security finding — async remediation would bypass the user's FLS

This is the most important issue in restoring the two quarantined events, and it needs a decision.

`AEIR_RemediationOrchestrator.execute()` enforces authorization using the **running user**:

```apex
if (!od.isUpdateable()) throw ...      // running user's object access
if (!fd.isUpdateable()) throw ...      // running user's field access
audit.Requested_By__c = UserInfo.getUserId();
```

Platform event triggers run as the **Automated Process** user, not the person who clicked the button. If remediation moves behind `Remediation_Requested__e`, every one of those checks evaluates against Automated Process — which typically has broad access. A user with no edit rights on `Account.Tax_Code__c` could publish the event and have the update succeed.

The quarantined handler carries `Requested_By__c`, but the current code **only stores it for audit** — it never re-validates against it.

Three options, in order of preference:

| Option | Approach | Trade-off |
|---|---|---|
| **A — keep writes synchronous** | Remediation and retry stay in the user's transaction; only *diagnosis* goes async | Simplest and safest. Writes are fast; the slow part is AI, which is already async. **Recommended.** |
| **B — re-validate in the subscriber** | Subscriber loads `Requested_By__c` and re-checks that user's CRUD/FLS via a permission-set/`UserRecordAccess` lookup before executing | Correct but non-trivial; FLS for an arbitrary user is awkward to evaluate in Apex |
| **C — pre-authorize at publish time** | Validate synchronously, write an approved `Remediation_Action__c` with status `Approved`, and have the subscriber execute only pre-approved rows | Good audit story; the event becomes a dispatch signal rather than a trust boundary |

**My recommendation is A.** The user-facing latency problem is the AI callout, not the DML. Making writes async buys little and costs the entire authorization model. Spec §11.1 requires CRUD/FLS/sharing checks to pass and §11.2 says *"a retry must never be initiated from an arbitrary class name or payload supplied by AI or the browser"* — an event payload is exactly that kind of untrusted input.

If we do proceed with async writes, **option C** is the safer of the two remaining.

---

## 4. Proposed payloads for review

### 4.1 `Agent_Diagnosis_Requested__e` — extend (4 new fields)

Existing: `Correlation_Id__c`, `Error_Log_Id__c`, `Prompt_Input_JSON__c`, `Session_Id__c`

| Add | Type | Why |
|---|---|---|
| `Target_User_Id__c` | Text(18) | Who to push the `Diagnosed` alert to when work finishes. Without this the subscriber cannot address the result. |
| `Request_Source__c` | Text(40) | `AUTO_CAPTURE` · `USER_GET_HELP` · `RETRY_EVALUATION`. Drives §9.1 policy and prevents duplicate diagnosis of the same incident. |
| `Incident_Id__c` | Text(18) | Diagnose once per incident, not once per failed row (§2 above). Depends on AF-04. |
| `Requested_At__c` | DateTime | Needed for the §13.2 *mean time to diagnosis* metric, which is currently uncomputable. |

### 4.2 `Aegis_User_Alert__e` — no schema change required

The existing ten fields already cover the round trip. `Target_User_Id__c` **already solves action item #1** — `aegisHeadlessMonitor.js` filters on it at [line 63](../force-app/main/default/lwc/aegisHeadlessMonitor/aegisHeadlessMonitor.js#L63).

The round trip works purely by publishing the same event twice with different `Notification_Type__c` values:

| Stage | `Notification_Type__c` | `Headline__c` | `Action_Available__c` |
|---|---|---|---|
| Capture | `Detected` | "A background process encountered an issue. Aegis Flow is analyzing it now." | `NONE` |
| Diagnosis done, user-fixable | `Diagnosed` | "I have identified the issue." | `FIX` or `HELP` |
| Diagnosis done, developer-only | `Diagnosed` | "I found the issue, but it requires technical assistance." | `ESCALATE` |
| Retryable | `Retry Available` | "A temporary issue interrupted the process. A safe retry is available." | `RETRY` |

That is a direct match to spec §6.5 and covers both of your flows — User-Fixable and IT-Only — without a schema change.

**Optional additions if we want the LWC to skip a round trip:**

| Add | Type | Why |
|---|---|---|
| `Diagnosis_Id__c` | Text(18) | Lets the panel fetch the diagnosis directly instead of re-deriving it from the correlation ID |
| `Diagnostic_Session_Id__c` | Text(18) | Ties the alert to an open Get Help session so the panel reopens in place |

**Constraint to hold the line on (spec §5.2):** this event is broadcast to *every* subscriber and filtered client-side. It must never carry stack traces, raw messages, record values, or tokens. Keep it to IDs and user-safe copy; `AEIR_UserNotificationService.getAlertDetails()` already does the authorized server-side retrieval and is the correct place for anything sensitive.

### 4.3 `Remediation_Requested__e` / `Retry_Process_Requested__e`

Payload changes are secondary to the §3 decision. If we adopt **option C**, both events shrink considerably — they become dispatch signals rather than instruction payloads:

| Field | Keep? | Note |
|---|---|---|
| `Correlation_Id__c` | Yes | Required on every event (§5.3) |
| `Remediation_Action_Id__c` | **New** | Points at a pre-approved `Remediation_Action__c` row |
| `Action_Key__c` | Yes | Cross-check against the approved row |
| `Requested_By__c` | Yes | Must be **validated**, not just stored |
| `Payload_JSON__c` | **Drop** | Loose object/field/value JSON is the trust-boundary problem |
| `Record_Id__c` | Drop | Read from the approved row instead |

`Retry_Process_Requested__e` follows the same shape via `Retry_Attempt__c`, which already has an idempotency key. §11.2 also requires max-attempt and backoff enforcement, which does not exist yet in `AEIR_RetryOrchestrationService`.

---

## 5. Loop prevention

A real risk, and worth designing explicitly rather than relying on what is there today.

Current state: every subscriber wraps its work in `catch (Exception ignored) {}` — see `AEIR_AgentDiagnosisRequestedEventHandler` line 10 and `AEIR_RemediationRequestedEventHandler`. This *incidentally* prevents loops, because a failure inside a subscriber never captures a new error. It also silently discards every failure, which is why a broken subscriber would be invisible today.

Proposed replacement:

1. **A static re-entry guard** (`AEIR_EventContext.isSubscriberContext`) set at the top of every subscriber. `AEIR_ErrorCaptureService.capture()` checks it and refuses to publish a new event when already inside one.
2. **Never call `ErrorCaptureService` from a diagnosis/notification subscriber.** Subscriber failures belong in `Delivery_Attempt__c` — the object exists for this and is already used for notification delivery.
3. **Replace silent swallow with recorded failure**, so a broken subscriber surfaces in Automation Health rather than vanishing.
4. **Cap by correlation ID** — one diagnosis request per correlation ID, enforced by checking for an existing `AI_Diagnosis__c` before publishing.

---

## 6. Open questions for our review session

1. **§3 — do we accept option A (writes stay synchronous)?** This is the decision that determines whether the two events get restored at all.
2. Do we split AF-17 into *AF-17a: diagnosis round trip* (small, unblocks the demo) and *AF-17b: async writes* (blocked on the §3 decision)?
3. Do we sequence **AF-04 (incident grouping)** before the Agentforce callout work, per §2?
4. Is a real Agentforce callout in scope for this phase, or does the deterministic fallback carry the demo? This decides whether we need the Named Credential and §10.3 response validation now.
5. Custom object headroom — the org currently holds **37 custom objects**; restoring both events adds 2. The `custom-object-limit-excluded` folder name suggests this was the original blocker, so worth confirming the ceiling before we commit.

---

## 7. Suggested next step

Fastest path to a demonstrable real-time flow, without touching the two quarantined events or the authorization model:

1. Publish `Agent_Diagnosis_Requested__e` at the end of capture (feature-flagged via `Feature_Flag.AI_DIAGNOSIS` — see AF-05).
2. Publish a `Detected` alert immediately with `Action_Available__c = NONE`, so the LWC shows the spinner.
3. Have `AEIR_AgentforceGatewayService` publish a second `Diagnosed` alert on completion.
4. Update `aegisHeadlessMonitor.js` to replace an existing alert in place when a later event arrives with the same correlation ID.

Steps 1–4 use only already-deployed metadata. The one schema change needed is `Target_User_Id__c` on `Agent_Diagnosis_Requested__e` (§4.1).
