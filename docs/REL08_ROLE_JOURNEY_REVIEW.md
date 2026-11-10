# REL-08 role and journey review

**November 10, 2026. Local source review and component checks; live role acceptance pending.**

The review covers Aegis Flow only. It changes no other product and performs no live
business recovery, report delivery, user provisioning or permission assignment.

| Role | Intended journey | Access boundary |
| --- | --- | --- |
| Product Admin | Setup, command center, owned context, registered corrections and sensitive evidence | Explicit product grants; server registration, flags, CRUD/FLS, sharing and confirmation still apply |
| Support Analyst | Triage and permitted registered correction preparation | Existing remediation custom permission now has its matching workspace controller class grant; object/field grants unchanged |
| Developer Viewer | Authorized technical evidence and command center | Sensitive-context entitlement is explicit; no correction permission or correction-controller request from the workspace |
| End User | Own notices, manual Help, diagnosis and confirmed report | Ordinary sharing and ownership remain enforced; no correction permission and no internal session-event Read/Create grant |
| Integration User | Selected server/API capture and retry | Dedicated principal; no browser role or general business-write entitlement inferred |
| Headless User | Headless endpoint alongside its underlying diagnostic role | Separate headless custom permission; no added business-object rights |
| Sample Account Remediation | Narrow registered sample acceptance | Not a general user entitlement or an approved customer recovery operation |

## Confirmed local changes

- Support Analyst's Operations workspace used the correction controller without granting
  access to that class. Add only `AEIR_RemediationController` class access; the existing
  custom permission, object/field access, registration, sharing and consent gates remain.
- The workspace no longer requests correction actions or displays correction preparation
  for users without `AEIR_Execute_Remediation`. Help and diagnostic surfaces remain usable.
- Diagnostic Assistant gains the same explicit report checkbox used by Get Help.
  Both surfaces require fresh confirmation after a failed attempt and disable repeat
  submission after a created report. Neither claims success without an escalation identity.
- Assistant status changes are announced with a status region and loading is exposed as
  busy. These are local template checks, not a completed accessibility/device acceptance.

The static custom-permission import follows [Salesforce's permission UI guidance](https://developer.salesforce.com/docs/platform/lwc/guide/create-get-permissions).
Server authorization remains authoritative. All Apex implementation is unchanged.

## Acceptance cases and proof boundary

| Case | Reviewed implementation / local evidence | Remaining live evidence |
| --- | --- | --- |
| ACC-08-01 | Existing session/notification ownership checks and ordinary vs privileged role grants; workspace permission-negative component regression | Two distinct ordinary actors, owned/foreign record access and denial, effective permissions and actual browser evidence |
| ACC-08-02 | Both Help surfaces, confirmation/failed-response/repeated-send regressions and context invalidation coverage | Ordinary-user session creation without readable evidence and malformed/unreadable reference on the selected org |
| ACC-08-03 | Workspace role gate, controller/orchestrator server checks and existing confirmation component tests | Explicitly selected registered operation/fixture, denied/success/replay/rollback evidence, or an owner-approved exclusion |
| ACC-08-04 | Existing saved-alert refresh, stale hint and dismissal component/server coverage reviewed | Actual notification creation, disconnect/refresh, dismissal/reload and canonical cross-user/expired-reference outcomes |

All four live cases remain **Not run**. Unit mocks and source/XML contracts are not proof
of effective access, server denial, rendered Lightning behavior or delivery in an org.
The user's reply “Users B I think” remains a suggested label. A read-only direct Aegis
role-assignment inventory did not identify two ordinary End User candidates; no account,
permission set, profile, session or business record was changed to manufacture a pass.

## Next execution inputs

Bind the reviewed Aegis source artifact and target, two verified ordinary users A/B,
actual support/developer/admin actors and their effective grants. Select the exact cases,
synthetic fixture budget and cleanup authority. Recovery and external delivery remain
unselected. Local changes must be present in the reviewed target before claiming live UI
acceptance; the prior deployed UI is not evidence for these new local templates.

The earlier shared-org ACC-07-01 result stays Failed, with 307 passing Aegis tests and zero
Aegis failures. No broad org validation or Apex suite is rerun by this local review.
