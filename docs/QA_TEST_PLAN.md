# Aegis Flow — QA Test Plan

**Org:** `Aegis Flow_WA_Dev` (`00DgL00000YDvsvUAD`)
**Prepared:** 2026-07-29
**Scope:** Lead, Contact, Opportunity, Order

---

## 1. Read this first — what Aegis Flow can and cannot capture

This is the single most important section. **Most false bug reports against this product come
from testing a scenario it is architecturally unable to observe.** Please read it before
raising anything.

Aegis Flow captures failures in **automation** — Flows, Apex, triggers, batch and queueable
jobs. It does not capture errors that the Salesforce platform rejects *before* any automation
runs.

### Capturable ✅

| Failure type | How it is captured | Latency | Record id in package? |
|---|---|---|---|
| Record-triggered Flow fault | `FlowExecutionErrorEvent` → utility bar (real time) | Seconds — **but only while a browser tab with the Aegis utility bar is open**, see §1.1 | Yes |
| Record-triggered Flow fault (**with a fault path**) | Fault → `Error_Captured__e` | **Seconds, always** | ✅ **Yes** |
| Record-triggered Flow fault (no fault path) | `FlowInterview` reconciliation (poll, backstop) | ≤ 5 min (testing cadence) | No |
| Screen Flow fault | Same two layers | Seconds / ≤ 15 min | Varies |
| Apex exception wrapped in `AEIR_Guard` | Publish-based capture | Seconds | Yes |
| Batch Apex failure | `BatchApexErrorEvent` trigger | Seconds | No |
| Failed async job (Batch / Queueable) | `AsyncApexJob` reconciliation (poll) | ≤ 15 min (testing cadence) | No |
| Explicit Flow fault path calling the Aegis action | Invocable capture | Immediate | Yes |

### 1.1 How fast — and the condition attached to "real time"

`FlowExecutionErrorEvent` is **not triggerable** (`IsTriggerable = false`), so no Apex trigger
can subscribe to it. The only way to receive it is a streaming subscription, which Aegis does
from the **headless monitor in the utility bar** — client side, in a browser.

**Consequence QA must know:** the real-time path only fires while at least one user has a tab
open on an app carrying the Aegis utility bar. Overnight batch failures, integration-user
activity and anything happening when nobody is logged in fall through to the **15-minute
poller**. That is not a defect; it is the platform's constraint.

| Path | Typical | Worst case | Works with nobody logged in? |
|---|---|---|---|
| Flow — utility bar streaming | seconds | seconds | ❌ No |
| Flow — **fault path** (best) | seconds | seconds | ✅ **Yes** |
| Flow — `FlowInterview` poller | ~2.5 min | **5 min** (testing cadence) | ✅ Yes |
| Apex via `AEIR_Guard` | seconds | seconds | ✅ Yes |
| Batch Apex (`BatchApexErrorEvent`) | seconds | seconds | ✅ Yes |
| Failed async job poller | ~7 min | **15 min** (testing cadence) | ✅ Yes |

**When timing a test, always allow the worst case before reporting a miss.**

### NOT capturable ❌ — expected behaviour, do not raise as a defect

| Scenario | Why |
|---|---|
| **Validation rule fires on a direct record save** | The platform rejects the DML and returns the error to the UI. No Apex or Flow ever executes, so there is nothing for Aegis to observe. |
| **Required-field error on a direct save** | Same reason. |
| **Duplicate rule blocking a save** | Same reason. |
| **Lead Convert failing a validation rule** | Convert runs through `LeadConvertDesktopController`, a closed platform controller. Verified against a live network trace. |
| **Page layout / field-level-security errors in the UI** | Client-side, never reaches the server. |
| **A validation rule that a Flow trips** | ✅ **This IS captured** — see the distinction below. |

### The distinction that matters most

> **Who tripped the rule?**
>
> - *A user typing into a form and pressing Save* → platform rejects it → **not captured**.
> - *A Flow or Apex trying to write a record and tripping the same rule* → the automation
>   fails → **captured**.
>
> The Contact test below (TC-C-01) is deliberately a **negative** test proving the first case.
> The Opportunity → Order test (TC-O-01) proves the second.

---

## 2. Environment preconditions

Confirm all of these before starting. A failure here invalidates every result.

| # | Check | Expected | Where |
|---|---|---|---|
| P1 | Tester has an Aegis permission set | `AEIR_End_User` at minimum | Setup → Permission Sets |
| P2 | Aegis Flow app is accessible | App launcher → "Aegis Flow" | App Launcher |
| P3 | Utility bar shows the Aegis monitor | Bottom bar, Aegis Flow app | Any page in the app |
| P4 | Scheduled jobs are `WAITING` | 6 Aegis jobs | Setup → Scheduled Jobs |
| P5 | `USER_NOTIFICATIONS` flag enabled | `true` | `Feature_Flag__mdt` |
| P6 | Escalation recipient configured | `wahid@thelodestonegroup.com` | `Escalation_Route__mdt` |
| P7 | Health check | 9 PASS / 1 WARNING / 0 FAIL | Aegis Flow Setup tab |

### ⚠️ Feature flags currently OFF

Three flags are disabled. **Any test depending on these will correctly do nothing.** Do not
raise these as defects:

| Flag | State | Effect on testing |
|---|---|---|
| `AI_DIAGNOSIS` | **OFF** | Diagnosis uses the deterministic rule engine, not a live AI call. Summaries will be rule-derived. This is by design (deferred). |
| `GOVERNED_REMEDIATION` | **OFF** | **One-click "Fix it" will not appear or will not execute.** Skip all remediation cases (TC-R-*) unless this is switched on first. |
| `CONNECTOR_EXTENSIONS` | **OFF** | Jira / Slack / Teams routes are not implemented. They record a `Pending` audit rather than delivering. |

### ⚠️ Live test fixtures — intentionally left in place

| Fixture | Object | Effect |
|---|---|---|
| `Aegis_Require_Lead_Source` (validation rule) | Contact | **A Contact cannot be saved without Lead Source.** |
| `Aegis_Test_Order_On_Closed_Won` | Opportunity | **No fault path.** Fires on any Closed Won whose **Name does NOT contain `AEGIS_FAULT`**. The save **rolls back**; captured by the poller with **no record id**. |
| `Aegis_Test_Order_On_Closed_Won_With_Fault` | Opportunity | **With a fault path.** Fires only when the **Name contains `AEGIS_FAULT`**. The save **succeeds**; captured in **seconds with the record id**. |

Both need at least one Opportunity **line item** — with none the Flow skips Order creation and
nothing fails, so a clean save is correct rather than a missed capture.

### 🔀 Switching between the two paths

The two flows are mutually exclusive on the Opportunity **Name**, so both stay active and you
never have to deactivate anything:

| Opportunity Name | Flow that fires | Save | Capture | Record id |
|---|---|---|---|---|
| `Q3 Renewal - Acme` | no-fault | **rolls back** | poller, ≤1 min | ❌ none |
| `Q3 Renewal - Acme AEGIS_FAULT` | with-fault | **succeeds** | instant | ✅ yes |

Verified side by side on 2026-07-29. This is the clearest demonstration of why fault paths
matter: same failure, same Flow logic, two very different outcomes for the user.

These are deliberate. They are the test harness. Any *other* team using this org will hit them.

### ⚠️ Escalations send real email

`wahid@thelodestonegroup.com` receives every escalation raised during testing. Expect volume
when running the bulk cases in §7.

---

## 3. Where to verify a result

| Question | Where to look |
|---|---|
| Was the failure captured? | **Error Logs** tab → `All` list view |
| Was it classified correctly? | `Error_Log__c.Error_Category__c`, `Severity__c`, `Normalized_Message__c` |
| Was the user told? | **User Notifications** tab, and the utility-bar bell |
| Were repeats grouped? | **Incidents** tab → one Incident, occurrence count > 1 |
| Was a developer package built? | **Developer Escalations** tab → `Diagnostic_Package_JSON__c` |
| Did the email actually go out? | **Delivery Audits** tab → `Status__c` = `Delivered` |
| Was a diagnosis produced? | **AI Diagnoses** tab |
| How is this failure keyed? | `Correlation_Id__c` — prefix tells you the capture layer |

**Correlation ID prefixes:** `FLOWINT-` = Flow interview reconciliation · `ASYNC-` = failed
async job · others are per-source.

---

## 4. Contact — proving the platform boundary

### TC-C-01 — Validation rule on direct save is NOT captured ❌ *(negative test)*

| | |
|---|---|
| **Priority** | High — this is the most misunderstood behaviour in the product |
| **Precondition** | `Aegis_Require_Lead_Source` active |

**Steps**
1. Contacts → New.
2. Enter Last Name only. Leave **Lead Source** blank.
3. Save.

**Expected**
- Save is blocked with the validation-rule message. ✅
- **No** Error Log is created. ✅
- **No** notification appears in the utility bar. ✅
- No Incident, no escalation.

**Pass criteria:** the absence of a capture *is the pass*. If an Error Log appears here, that
is a genuine defect — report it.

**Why:** the platform rejects the DML before any automation runs.

---

### TC-C-02 — Same rule tripped by automation IS captured ✅

| | |
|---|---|
| **Priority** | High — the positive counterpart to TC-C-01 |
| **Precondition** | A Flow or Apex that creates a Contact without Lead Source. If one does not exist, ask the dev team to enable a test Flow, or run the anonymous-Apex snippet in §9. |

**Steps**
1. Trigger the automation that creates a Contact with no Lead Source.
2. Wait up to 15 minutes (or seconds, if the real-time layer catches it).

**Expected**
- Error Log created, `Object_API_Name__c` = `Contact`.
- `Error_Category__c` = `Validation Rule`.
- `Normalized_Message__c` is plain English, not a raw stack trace.
- Notification appears for the user who triggered it.

---

### TC-C-03 — Duplicate rule on direct save ❌ *(negative)*

Create a Contact that trips a duplicate rule via the UI. **Expected: no capture.** Same reason
as TC-C-01.

---

## 5. Lead — conversion boundary

### TC-L-01 — Lead Convert failure is NOT captured ❌ *(negative test)*

| | |
|---|---|
| **Priority** | High |

**Steps**
1. Create a Lead with no Lead Source.
2. Convert it (Convert button).
3. Conversion fails on the Contact validation rule.

**Expected**
- Conversion is blocked with an error. ✅
- **No** Error Log, **no** notification. ✅

**Why:** Lead Convert executes inside `LeadConvertDesktopController`, a closed platform
controller. Confirmed against a live network trace. This is a permanent architectural limit,
not a bug and not a backlog item.

---

### TC-L-02 — Lead-triggered Flow failure IS captured ✅

**Steps**
1. Have a record-triggered Flow on Lead that fails (e.g. writes to a field the running user
   cannot edit, or creates a child record missing a required field).
2. Create/update a Lead to trigger it.

**Expected**
- Error Log with `Source_Type__c` = `Flow` and `Source_Name__c` naming the Flow **and the
  failing element**.
- `Correlation_Id__c` starts `FLOWINT-` if caught by the poller.
- Notification within 15 minutes.

---

### TC-L-03 — Manual "Report an issue" on a Lead ✅

**Steps**
1. Open any Lead.
2. Utility bar → Aegis → describe a problem → submit.

**Expected**
- Diagnostic Session created, `Created_From__c` = `Help Me Utility`.
- `Context_Record_Id__c` = the Lead id, `Object_API_Name__c` = `Lead`.
- If the user hit a real error on that record in the last 24 h, the session links to it
  (`Recent_Error_Log__c`) and diagnoses **that error** rather than the generic fallback.

---

## 6. Opportunity → Order — the primary end-to-end case

This is the flagship scenario. It exercises capture → classify → notify → diagnose → escalate.

### TC-O-01 — Closed Won triggers a failing Flow, captured end to end ✅

| | |
|---|---|
| **Priority** | **Critical — the product's core promise** |
| **Precondition** | `Aegis_Test_Order_On_Closed_Won` active. Opportunity has an Account and at least one line item. |

**Steps**
1. Open an Opportunity with line items.
2. Set Stage → **Closed Won**. Save.
3. The Flow attempts to create an Order with **no `AccountId`** and fails.
4. Observe the utility bar; then check Error Logs.

**Expected**

| # | Expectation |
|---|---|
| 1 | Save succeeds — the Opportunity **is** Closed Won. The fault path added 2026-07-29 catches the Flow error instead of rolling the save back. |
| 2 | Error Log created. `Source_Type__c` = `Flow`. |
| 3 | `Source_Name__c` = `Aegis_Test_Order_On_Closed_Won / Create_Order_Without_Account`. |
| 4 | `Error_Category__c` = `Missing Data`, `Severity__c` = `Medium`. |
| 4b | **`Record_Id__c` = the Opportunity id.** Only the fault path supplies this; the poller cannot. |
| 5 | `Original_Error_Message__c` retains the raw platform message. |
| 6 | `Normalized_Message__c` is readable by a non-technical user. |
| 7 | Notification appears for the acting user. |
| 8 | An Incident exists grouping this failure. |
| 9 | Clicking **View details** opens the diagnosis — no permission error. |
| 10 | **Send to developer** produces a Developer Escalation and a `Delivered` Delivery Audit. |
| 11 | The escalation email arrives at `wahid@thelodestonegroup.com`. |

**Timing: seconds.** Verified end to end on 2026-07-29 — captured within 10 seconds with the
Opportunity id attached, correlation id `FLOW-<hash>`.

**Precondition that trips people up:** the Opportunity needs **at least one line item**. With
none, the Flow skips Order creation entirely and nothing fails — a green save is then correct,
not a missed capture.

---

### TC-O-02 — Deduplication under repetition ✅

**Steps** Repeat TC-O-01 on **12 different Opportunities** in quick succession.

**Expected**
- 12 Error Logs (one per real failure — evidence is never discarded).
- **1 Incident**, occurrence count 12.
- **1 notification**, not 12. *(Notification policy: cooldown + hourly cap.)*

**This is a storm-protection test.** 12 notifications = defect.

---

### TC-O-03 — Dismissed notification is not resurrected ✅

1. Trigger TC-O-01. 2. Dismiss the notification. 3. Wait for diagnosis to complete.

**Expected:** the dismissed alert does **not** reappear. Diagnosis updates the record silently.

---

### TC-O-04 — Diagnosis closes the round trip ✅

**Steps** Trigger TC-O-01 and watch the utility bar continuously.

**Expected**
- Initial alert appears (`Notification_Type__c` = `Detected`).
- It is **replaced** by the diagnosed outcome (`Diagnosed`) — the spinner resolves.
- A stuck spinner that never resolves **is a defect**.

---

## 7. Order — bulk and volume

### TC-B-01 — Bulk Closed Won (50 records) ✅

| | |
|---|---|
| **Priority** | High — governor-limit regression guard |

**Steps** Update 50 Opportunities to Closed Won in one Data Loader batch.

**Expected**
- Every failure is captured; none silently lost.
- **No** `System.LimitException` anywhere (check Setup → Apex Jobs, and debug logs).
- Incidents group correctly; notifications remain throttled.
- Escalation emails are batched, not 50 separate sends.

---

### TC-B-02 — Bulk via Data Loader, 200 records ✅

Same as TC-B-01 at 200. This exercises the full platform event batch size.

**Expected:** no limit exceptions; no dropped captures. *(This is the exact scenario that was
failing before the July 29 bulk refactor — worth running deliberately.)*

---

### TC-B-03 — Failed batch job is reconciled ✅

**Steps** Run an Apex batch that fails (dev team can supply one).

**Expected**
- Within 15 min, an Error Log with `Correlation_Id__c` starting `ASYNC-`.
- `Source_Type__c` = `Batch`, `Async_Job_Id__c` populated.
- Re-running the poller does **not** duplicate it.

---

## 8. Cross-cutting cases

### TC-S-01 — Sensitive data is masked ✅

**Steps** Cause a failure whose message contains a long digit string (16–18 digits), a
`password=` fragment, or a token.

**Expected**
- `Original_Error_Message__c` and the escalation package show `[MASKED]`.
- **No** exception during capture. *(A group-less regex bug here once killed captures silently —
  worth probing.)*

---

### TC-S-02 — Non-admin user journey ✅

**Steps** Repeat TC-O-01 as a **Standard User** with only `AEIR_End_User`.

**Expected**
- Notification appears.
- **View details** works — no "you don't have access".
- The user sees **their own** errors only, never another user's.

---

### TC-S-03 — Cross-user isolation 🔒

**Steps** User A triggers a failure. User B opens Aegis.

**Expected:** User B does **not** see A's notification or error detail. All evidence objects are
`Private`.

---

### TC-S-04 — Escalation with an unimplemented connector ✅

**Steps** Point a route at Slack/Jira and escalate.

**Expected**
- Escalation status = **`Pending`**, not `Sent`.
- A Delivery Audit exists explaining the connector is not implemented.
- **Nothing may report as delivered when it was not.**

---

### TC-R-01 — Governed remediation ⚠️ *(requires `GOVERNED_REMEDIATION` = ON)*

**Skip unless the flag is enabled.** With it on:
1. Trigger a USER_FIXABLE error. 2. Use the one-click fix. 3. Confirm the modal.

**Expected**
- Confirmation is **required** — no silent write.
- Only whitelisted object/field pairs are writable.
- A `Remediation_Action__c` audit row is written.
- A batch of **more than 40** is **refused outright** with a clear message — never
  half-applied.

---

## 9. Helper — forcing a capturable Contact failure

For TC-C-02, if no suitable automation exists, ask a developer to run this in **Developer
Console → Anonymous Apex**. It fails inside Apex, so Aegis *can* see it.

```apex
try {
    insert new Contact(LastName = 'Aegis QA Probe'); // no LeadSource -> trips the rule
} catch (Exception e) {
    AEIR_Guard.capture(e, 'QA Contact Probe', null, 'Contact', 'Create Contact');
}
```

**Verified against the live org on 2026-07-29.** Expect, within seconds:

| Field | Value |
|---|---|
| `Source_Type__c` | `Apex Class` |
| `Source_Name__c` | `QA Contact Probe` |
| `Error_Category__c` | `Validation Rule` |
| `Severity__c` | `Medium` |
| `Object_API_Name__c` | `Contact` |
| `Normalized_Message__c` | "A validation rule blocked the action. Review the rule message and update the record accordingly." |

Note the shape of that message: the point of the product is that a non-technical user reads
**that**, not a stack trace.

---

## 10. Defect reporting template

Please include all of these — the correlation id is the fastest route to root cause.

```
Test case ID:
Object:
What I did:
What I expected:
What actually happened:

Correlation Id:            (from the Error Log, if one exists)
Error Log Id:
Time (with timezone):
User / profile / perm sets:
Waited 15+ minutes before reporting?   Y / N
Checked §1 "NOT capturable"?           Y / N
Relevant feature flags on/off:
```

**Before raising anything, confirm:**
1. Is the scenario in the **NOT capturable** table in §1? If yes, it is expected.
2. Did you wait **15 minutes**? The poller is the backstop for the real-time layer.
3. Is the relevant **feature flag** on?

---

## 11. Coverage summary

| Area | Cases | Notes |
|---|---|---|
| Contact | TC-C-01 … 03 | Two negative (boundary proofs), one positive |
| Lead | TC-L-01 … 03 | Convert limitation, Flow capture, manual report |
| Opportunity / Order | TC-O-01 … 04 | Core end-to-end, dedupe, round trip |
| Bulk | TC-B-01 … 03 | 50, 200, async reconciliation |
| Security & policy | TC-S-01 … 04 | Masking, non-admin, isolation, connectors |
| Remediation | TC-R-01 | **Blocked on `GOVERNED_REMEDIATION`** |

**Not covered here, by decision:** live Agentforce AI diagnosis (`AI_DIAGNOSIS` off, deferred),
and Jira/Slack/Teams delivery (connectors not built).
