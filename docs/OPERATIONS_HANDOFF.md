# Aegis Flow operating and support handoff

**Prepared:** November 9, 2026 · `1.2.0-reconciled` · API 67.0\
**State:** Local handoff package complete for owner review. No operator assignment, training
attendance, customer acceptance, or current org health is asserted by this document.

## Start here

Aegis captures supported failures, preserves bounded and masked evidence, produces
deterministic guidance, and offers separately governed recovery or escalation. The
[configuration guide](CONFIGURATION.md) owns setup details; the
[user quick start](USER_QUICK_START.md) owns day-to-day user steps. Use the
[acceptance plan](RELEASE_ACCEPTANCE_PLAN.md) before declaring the selected environment ready.

Keep four states separate: publication accepted, diagnostic persisted, diagnosis produced,
and a notification or escalation delivered. A successful publish response alone proves
neither durable capture nor delivery. Optional AI and external connectors are separate
configuration and acceptance decisions. The product does not universally intercept native
Salesforce saves or Lead Convert failures.

## Ownership to assign before operational acceptance

| Role | Accountable for | Required handoff decision |
| --- | --- | --- |
| Product/release owner | Release scope, accepted limits, launch and rollback decision | Name the owner and an alternate; record the release artifact and review decision |
| Salesforce administrator | Tenant policy, permissions, subscriber identity, schedules and configuration | Name the administrator; approve the environment profile and configuration snapshot |
| Support lead | Triage, user communication and unresolved-incident ownership | Name the lead/coverage arrangement and agree severity response targets |
| Developer/on-call owner | Root-cause analysis and reviewed code or recovery changes | Name the technical owner and approved escalation channel |
| QA lead | Evidence, role/browser/load cases, cleanup and unresolved defects | Name the lead and reviewers of the acceptance record |
| Security/privacy reviewer | Evidence access, masking, outbound data, retention and tool findings | Name the reviewer and record unresolved-findings disposition |
| Customer process owner | Capture points, business rules, approved recovery and success criteria | Name the owner for the chosen process; record the accepted business postcondition |

These are responsibilities, not invented named assignments. Store actual assignments and
acknowledgements in the target profile or the organization's controlled handoff record.
An unassigned role or absent review keeps REL-23's operational acceptance open. A proposed
severity response target is not an agreed service level.

## Access matrix and separation of duties

| Shipped permission set | Intended use | Boundary to review |
| --- | --- | --- |
| `AEIR_End_User` | Own alerts, manual Help Me and permitted user actions | No internal diagnostic-session event Read/Create grant; test independent profile/permission grants and cross-user denial |
| `AEIR_Support_Analyst` | Diagnostic triage and permitted governed corrections | Includes the remediation capability and its workspace controller access; target-object/field/record rights, active registration, feature flag and confirmation still apply |
| `AEIR_Developer_Viewer` | Technical evidence review | Includes `AEIR_View_Sensitive_Context`; approve this entitlement explicitly and preserve masking/record access |
| `AEIR_Product_Admin` | Product setup and authorized administration/recovery | Administrative access is not representative of an ordinary user's effective permissions |
| `AEIR_Integration_User` | Approved inbound capture/processing and retry integration | Includes `AEIR_Process_Diagnostics`, inbound capture and retry capabilities; use a dedicated principal with only required native rights |
| `AEIR_Headless_User` | Headless API entitlement alongside a diagnostic role | Adds `AEIR_Headless_Access`; grants no business-object rights by itself |
| `AEIR_Sample_Account_Remediation` | Narrow sample acceptance scenario | Do not assign broadly or treat it as customer recovery approval |

The workspace offers correction preparation only to the remediation custom-permission
holder; other diagnostic/help surfaces remain available through their own access checks.
Both Help surfaces require the report confirmation checkbox and stop a second submission
after a created report. These UI controls supplement server authorization.

Validate effective access, including profiles and other permission sets. Diagnostic read
access, sensitive evidence, remediation, retry and headless access are separate capabilities.
The five event subscribers need a deliberately chosen active principal and bounded batch
configuration; do not infer its runtime capability from an admin's successful test.

## Routine operating checks

1. Review saved diagnostics and the setup health result in the intended org. Record the
   time, exact environment and failures; the historical November 7 score is not today's result.
2. Check the selected Flow and async monitor schedules and cursor progression. The source
   bounds each pass to 200 interviews or 100 failed jobs. An empty page is not backlog proof.
3. Review rejected capture and final-publication telemetry as well as accepted diagnostics.
   Reconcile source failures with durable captures using the actual correlation identity.
4. Check notifications through an ordinary user's session. Saved-alert refresh and the
   optional streaming connection are distinct paths; a transport warning is not proof that
   Help, dismissal or stored notices failed.
5. Review pending/failed delivery audits and unresolved escalations. Confirm recipients and
   destination-side results before considering another send.
6. Check retention/purge scheduling against the agreed policy. Preserve records subject to
   investigation or an applicable hold; do not invent a retention period from sample defaults.

Preserve subscriber identities, batch settings, schedules, routes, enabled feature overlays,
masking policy and access assignments across releases. Portable metadata defaults can differ
from an existing tenant's enabled configuration.

## Triage and user communication

Collect the correlation reference, UTC occurrence time, supported capture surface, affected
role, business operation and safe reproduction steps. Use sanitized evidence links with
access control rather than pasting raw payloads, credentials or sensitive record values into
chat/email. A correlation reference is useful evidence, not an authorization token.

| Observation | Operator response |
| --- | --- |
| No alert after a failed native save | Check the supported surface first. Use manual Help or the instrumented/custom save path; do not promise universal interception |
| Publish accepted but no saved diagnostic | Review durable rejection/final-publication telemetry and the subscriber path; do not report success from acceptance alone |
| Stored alert exists but streaming warns | Use **Refresh alerts** once; inspect channel-specific status and the saved result. Do not start a manual polling loop |
| Different user's evidence is denied | Preserve the denial and check intended role/sharing. Do not grant administrator rights merely to make the screen pass |
| No known correction is available | Preserve evidence and use a confirmed escalation. Do not invent a business repair |
| Remediation/retry fails | Inspect the governed audit and business postcondition; retain failure/rollback evidence and observe configured attempt/backoff limits |
| Delivery is uncertain, pending or failed | Reconcile the actual destination and durable claim/audit. A repeated request must not implicitly send again |
| Duration is null | Unknown legacy or unresolved/reopened timing can legitimately be null; do not reinterpret it as zero or backfill timestamps without a separate migration |

Severity values are Low, Medium, High and Critical. Their operational response/coverage
must be agreed by the owners. Avoid promising response times not accepted in that handoff.

## Recovery and escalation controls

Remediation requires a registered allowed object/field/action, the appropriate capability,
native CRUD/FLS/record access, explicit confirmation and an atomic audit. Retries additionally
need reviewed idempotent business logic, a durable postcondition and configured attempt/backoff
limits. Do not invoke a handler directly to bypass the orchestrator.

For an approved Flow, use the exact fixed contract and constraints in
[Approved Flow recovery](APPROVED_FLOW_RECOVERY.md). Product source ships no enabled customer
business Flow registration. Diagnostics-only acceptance can exclude recovery only through
an explicit recorded scope decision.

Email/Case escalation requires a reviewed route and destination. Optional Slack, Teams,
Jira, GitHub and webhook adapters need their own credentials, principal scopes and live
acceptance. An external timeout can have delivered remotely. Do not delete delivery claims,
request keys or attempt records to force a resend; use a separately governed reconciled retry.

Optional Agentforce enrichment uses a dedicated read-only agent and preserves deterministic
fallback. Its recommendations never authorize a write. Keep recovery/escalation actions out
of that enrichment agent. Linked debug-log bodies remain a separate sensitive-context,
same-org, bounded retrieval feature; they are not an instruction to enable trace flags.

## Incident, change and rollback handoff

The support lead owns an incident until an explicit receiving owner accepts it. Record the
business impact, current user guidance, correlation references, sanitized evidence, actions
already attempted, delivery uncertainty and next review point. Use the organization's
approved incident channel; this package sends no messages.

Stop a planned release if its artifact/target/configuration differs from the reviewed
baseline, required tests fail, permission boundaries regress, or duplicate/uncertain writes
cannot be reconciled. The release owner selects corrective action using the
[rollback runbook](ROLLBACK_RUNBOOK.md). A source rollback does not reverse sent email,
external actions or later business edits. Preserve diagnostics/audits and business data.

## Training walkthrough and acknowledgement

Use synthetic data and the selected roles. Walk through one owned alert, one manual Help
session, a foreign-record denial, permitted correction/retry boundaries, a confirmed report,
and dismissal surviving reload. Demonstrate one unavailable/uncertain channel without
resending. Review supported capture surfaces and where to find masked evidence.

The handoff record must name attendees/reviewers, artifact/configuration identity, unresolved
limits, operating owners, approved recipients, response expectations, retention policy,
training outcome and follow-up owner. No training attendance or sign-off is prefilled.

## Open release conditions

CLI-01's scoped local release-use qualification is complete; target binding and explicit
action authority remain required. The separate product dependency/support issues remain
open; see [release tooling](RELEASE_TOOLCHAIN_REVIEW.md) and
[dependency findings](DEPENDENCY_SECURITY_REVIEW.md). Hosted CI, final org/runtime/browser/load
acceptance, actual delivery, rollback rehearsal and customer approval remain separate. Keep
those limits in customer-facing handoff claims until evidence closes them.
