# Aegis Flow — Error Catalog

**What this is:** every Salesforce error category, grouped, with an explicit statement of
whether Aegis Flow covers it — and if not, why not.

**Last verified:** 2026-07-29 against org `Aegis Flow_WA_Dev`

---

## Legend

| Mark | Meaning |
|---|---|
| ✅ **Covered** | Captured, classified by a rule, and surfaced to the user |
| 🟡 **Partial** | Captured, but classified as `Unknown` — no tuned rule yet |
| ⛔ **Out of scope** | Architecturally impossible to capture. Not a defect, not a backlog item |
| 🔜 **Planned** | Not covered today; a known route exists |

**The one rule that explains most of this table:** Aegis captures failures in **automation**.
If the Salesforce platform rejects an operation *before* any Apex or Flow runs, there is nothing
to observe. See §7.

---

## 1. Data and validation errors

| Error | Platform code | Covered? | Category | Severity | Fixability |
|---|---|---|---|---|---|
| Required field missing | `REQUIRED_FIELD_MISSING` | ✅ | Missing Data | Medium | USER_FIXABLE |
| Custom validation rule failed | `FIELD_CUSTOM_VALIDATION_EXCEPTION` | ✅ | Validation Rule | Medium | ADMIN_FIXABLE |
| Record blocked by another automation | `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` | ✅ | Automation Failure | High | DEVELOPER_ONLY |
| Field value too long | `STRING_TOO_LONG` | 🟡 | Unknown | — | — |
| Invalid picklist value | `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` | 🟡 | Unknown | — | — |
| Invalid cross-reference key | `INVALID_CROSS_REFERENCE_KEY` | 🟡 | Unknown | — | — |
| Duplicate value on unique field | `DUPLICATE_VALUE` | 🟡 | Unknown | — | — |

> **Worth adding rules for.** The 🟡 rows above are captured with full evidence — they simply
> fall through to `Unknown` instead of getting a plain-English message. `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`
> in particular is worth a rule: it is what broke our own Case escalation channel (AF-28), and
> it is silent under `allOrNone = false`.

---

## 2. Permission and access errors

| Error | Platform code | Covered? | Category | Severity | Fixability |
|---|---|---|---|---|---|
| No access to a referenced record | `INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY` | ✅ | Permission | Medium | ADMIN_FIXABLE |
| Insufficient access on the record itself | `INSUFFICIENT_ACCESS_OR_READONLY` | 🟡 | Unknown | — | — |
| Field not writeable for this user | FLS failure | 🟡 | Unknown | — | — |

---

## 3. Governor limit errors

| Error | Platform code | Covered? | Category | Severity | Fixability |
|---|---|---|---|---|---|
| Apex CPU time exceeded | `APEX_CPU_TIME_LIMIT_EXCEEDED` | ✅ | Governor Limit | High | DEVELOPER_ONLY |
| Too many SOQL queries | `System.LimitException` | 🟡 | Unknown | — | — |
| Too many DML statements | `System.LimitException` | 🟡 | Unknown | — | — |
| Too many query rows | `System.LimitException` | 🟡 | Unknown | — | — |

> These are the failures Aegis's own July 29 bulk refactor was about. All four are captured;
> only CPU time has a tuned rule. A single `System.LimitException` rule would cover the rest.

---

## 4. Code defects

| Error | Platform code | Covered? | Category | Severity | Fixability |
|---|---|---|---|---|---|
| Null pointer | `System.NullPointerException` | ✅ | Null Pointer | High | DEVELOPER_ONLY |
| Mixed DML | `MIXED_DML_OPERATION` | ✅ | Configuration | High | DEVELOPER_ONLY |
| List index out of bounds | `System.ListException` | 🟡 | Unknown | — | — |
| SOQL returned no rows for assignment | `System.QueryException` | 🟡 | Unknown | — | — |
| Type conversion failure | `System.TypeException` | 🟡 | Unknown | — | — |
| Divide by zero / math | `System.MathException` | 🟡 | Unknown | — | — |

---

## 5. Concurrency and integration

| Error | Platform code | Covered? | Category | Severity | Fixability |
|---|---|---|---|---|---|
| Row lock contention | `UNABLE_TO_LOCK_ROW` | ✅ | Locking | Low | **RETRYABLE** |
| Callout timeout | `System.CalloutException` | 🟡 | Unknown | — | — |
| Named credential / auth failure | `System.CalloutException` | 🟡 | Unknown | — | — |
| Remote site not configured | `System.CalloutException` | 🟡 | Unknown | — | — |
| External system 5xx | Varies | 🟡 | Unknown | — | — |

> `UNABLE_TO_LOCK_ROW` is the only rule marked `RETRYABLE`, which drives the one-click retry
> offer. Callout failures are frequently retryable too and are the strongest candidate for the
> next rule.

---

## 6. Where the failure happens — capture path and speed

| Source | Covered? | Path | Speed | Record id? |
|---|---|---|---|---|
| Record-triggered Flow **with a fault path** | ✅ | Fault → `Error_Captured__e` | **Seconds** | ✅ Yes |
| Record-triggered Flow **without a fault path** | ✅ | `FlowInterview` poll | ≤ 5 min (testing) / ≤ 15 min | ❌ No |
| Screen Flow | ✅ | Same two layers | Same | Varies |
| Apex wrapped in `AEIR_Guard` | ✅ | Publish → trigger | Seconds | ✅ Yes |
| Apex **not** wrapped | ⛔ | — | — | — |
| Batch Apex (`Database.RaisesPlatformEvents`) | ✅ | `BatchApexErrorEvent` | Seconds | ❌ No |
| Failed Queueable / Batch job | ✅ | `AsyncApexJob` poll | ≤ 15 min (testing) / ≤ 60 min | ❌ No |
| Scheduled Apex failure | ✅ | `AsyncApexJob` poll | Same | ❌ No |
| Custom LWC | ✅ | `errorBoundaryWrapper` | Seconds | ✅ Yes |
| External system calling in | ✅ | REST endpoint | Seconds | ✅ Yes |
| Platform Event subscriber failure | ✅ | `AEIR_SubscriberTelemetry` | Seconds | ❌ No |

**The single highest-leverage change available to a customer:** add a fault path to the Flows
that matter. It moves capture from *minutes with no record id* to *seconds with the record id*,
and it is the only way to get a record snapshot into the escalation package. Polling faster is
not a substitute — see §8.

---

## 7. ⛔ Out of scope — architecturally impossible

**None of these are defects. Do not raise them as bugs.**

| Scenario | Why it cannot be captured |
|---|---|
| Validation rule on a **direct record save** | The platform rejects the DML and returns the error to the UI. No Apex, no Flow, no trigger runs. There is no execution context to observe. |
| Required-field error on a **direct save** | Same. |
| Duplicate rule blocking a **direct save** | Same. |
| **Lead Convert** failing a validation rule | Runs inside `LeadConvertDesktopController`, a closed Salesforce Aura controller with no package hook. Verified against a live browser network trace. |
| Page-layout or FLS errors in the UI | Client-side; never reaches the server. |
| Login, SSO, session errors | Outside any transaction Aegis participates in. |
| Declarative rollback with no automation involved | Nothing executes to catch. |

### The distinction that decides every case

> **Who tripped the rule?**
>
> - A **user** typing in a form and pressing Save → platform rejects → ⛔ not captured.
> - A **Flow or Apex** writing a record and tripping the same rule → automation fails → ✅ captured.
>
> Same validation rule. Different answer. This is the most common source of false bug reports.

**The only route to the first case** is a custom LWC record form that submits through Apex, so
the failure happens inside a context Aegis can see. That is "Item 1", currently on hold.

---

## 8. Why polling faster is the wrong lever

Scheduled Apex fires **at most once per hour per job**, so "every N minutes" means scheduling
60/N jobs. Every-1-minute would need **60 jobs per poller — 120 of the org's 100 slots.** It
does not fit, and it would not help:

- A poller can **never** recover the record id. `FlowInterview` does not store it. So no record
  snapshot reaches the escalation package, no matter how often you poll.
- Polling is the **backstop**. If a Flow failure is arriving late, the fix is a fault path on
  that Flow: seconds, with the record id.
- Every extra tick costs queries against `FlowInterview` and `AsyncApexJob` — during a storm,
  exactly when the org is least healthy.

**Current cadence (testing phase, set 2026-07-29):**

| Poller | Jobs | Every | Slots |
|---|---|---|---|
| Flow interview | 12 | 5 min | 12 |
| Async job | 4 | 15 min | 4 |

Scripts: `scripts/set_poller_cadence.apex` (flip `MODE` to `NORMAL` when testing ends) and
`scripts/run_pollers_now.apex` (run both immediately — usually what you actually want mid-test).

---

## 9. Coverage summary

| Group | Covered rules | Captured but unclassified |
|---|---|---|
| Data & validation | 3 | 4 |
| Permission | 1 | 2 |
| Governor limits | 1 | 3 |
| Code defects | 2 | 4 |
| Concurrency & integration | 1 | 4 |
| **Total** | **8 active rules** | **17 fall through to `Unknown`** |

**Read this carefully:** "unclassified" does **not** mean "not captured". Every 🟡 row is
captured with full evidence, correlation id, incident grouping and escalation. It simply gets a
generic message instead of a tuned plain-English one. Adding a rule is a **Custom Metadata
record, not code** — `Error_Rule__mdt`, no deployment required.

### Recommended next rules, highest value first

1. `System.LimitException` → Governor Limit / DEVELOPER_ONLY — covers 3 gaps at once
2. `System.CalloutException` → Integration / **RETRYABLE** — unlocks one-click retry for integrations
3. `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` → Configuration / ADMIN_FIXABLE
4. `INSUFFICIENT_ACCESS_OR_READONLY` → Permission / ADMIN_FIXABLE
5. `System.QueryException` → Code Defect / DEVELOPER_ONLY
