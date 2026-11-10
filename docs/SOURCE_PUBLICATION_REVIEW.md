# Aegis Flow source publication review

Reviewed November 10, 2026 against published baseline `eda715f3c05aeda9acacd2e6bf97384cf4968801`.
The user authorized review, connected-org testing and publication to main. [PR #2](https://github.com/WahidKhanTLG/Aegis-Flow/pull/2) is merged to main at `0089f56e21d4efa25048ea9a7411d148b2e13eb5`.
The full post-merge local checks and live read-only connector proof pass. Hosted jobs could
not start because of account billing; REL-20 remains open. See the [product tracker](PRODUCT_PLAN_AND_TRACKER.md)
and [structured review](../release-preparation/publication-review.json) for current scope.

## Subsequent development deployment (E47)

The user subsequently authorized deployment. The actual development run passes 27 components
and 311/311 Aegis tests; a test-only lifecycle follow-up passes 9/9. Final retrieved source
parity passes all 717 logical files, with only seven deliberately retained environment values.
Both enabled feature flags and five event users are unchanged. See the
[current deployment verification](DEVELOPMENT_DEPLOYMENT_VERIFICATION.md). The earlier
check-only/publication checkpoint below remains dated evidence.

## Feature preservation

All baseline Salesforce metadata files remain. A parser comparison of 91 baseline Apex classes
found no removed or narrowed contract among 613 public/protected declarations. All 26 baseline
LWC public APIs remain across 14 bundles. Existing capture, diagnosis, help, notification,
remediation, retry, escalation, retention and headless/MCP operations remain represented in
the [55-entry feature inventory](PRODUCT_PLAN_AND_TRACKER.md). This is structural and test
evidence; it is not a guarantee against every possible runtime defect.

The intentional behavior changes are:

- Capture acknowledgement distinguishes queuing from persistence; rejected capture and final
  publication failures produce telemetry. Transient persistence failures retain bounded retry.
- Batch failures keep event-specific identities. Flow/async monitors keep bounded persistent
  cursors. Flow coverage matches observed interviews, and lifecycle metrics use server-owned
  transitions with unknown historic times left empty.
- Escalation requests use source locks and durable route keys. Existing completed, failed,
  pending or uncertain deliveries are not implicitly sent again.
- Ordinary users reach manual Help through the controller. Direct access to the internal
  session-command event is denied, and event attribution is bound to its authenticated publisher.
- Support can load the read-only remediation catalogue; executing a correction still requires
  its separate permission, feature flag, registration, confirmation and record/field access.
- Help/escalation UI preserves confirmation and repeat protection, including failure/reset states.
- Managed/unmanaged REST routing, schema imports and event payloads use explicit namespace
  contracts. Failed custom-channel lookup fails closed while saved-alert refresh stays usable.
- Nine subscriber actions and retry DTOs widen API visibility without removing prior signatures
  or bypassing authorization. Actual managed build/install acceptance remains separate.
- Development standard-app/layout/sample metadata remains in source. Only the isolated managed
  staging copy excludes those explicit inputs and removes the sample tax-field permission.

## Verification

| Check | Actual result | Limit |
| --- | --- | --- |
| Salesforce `PUB-APEX-01`, check-only job `0AfgL00000dOLKzSAO` | Succeeded: 571 components, zero component errors; 311/311 tests from all 38 executable Aegis test classes; zero coverage warnings | No metadata saved; unmanaged development target |
| Returned Aegis coverage | 93.14% weighted across 64 executable classes, none below 75% | Returned coverage, not a production/org-wide percentage |
| Current local Node 22.23.4 and 24.22.2 verification | 124 LWC, 33 MCP, 12 dependency/security and eight managed-source tests pass; XML, Apex/LWC/source syntax, manifest/preparation and lint pass | Component/protocol mocks do not replace rendered Salesforce acceptance |
| Live current MCP implementation against deployed REST API | Capabilities, own recent errors, own incidents and notifications pass; disabled mutation rejected before API dispatch | Four read requests, connected administrator; no ordinary-user browser or live mutation acceptance |
| Dependency review | Root and isolated lint all-severity audits clean; source-backed vendor changes retain license/provenance and compatibility checks | Owned fork maintenance remains required |
| Hosted GitHub Actions, PR run 42811497088 and merge-main run 42812085120 | Both Node 22/24 jobs failed before executing any step: account locked due to a billing issue | Hosted/Linux acceptance blocked; REL-20 remains open |

The complete local verification was rerun on both supported Node versions before merge;
both passed with the counts above. After merge, the full Node 24 verification and all four
live MCP reads passed again. Both refreshed dependency audits remain zero at every severity.
All 747 product metadata/test files are identical to the successful check-only snapshot. No application/CI checks were
removed or relaxed. GitHub billing must be resolved by the account owner and the hosted
workflow rerun before REL-20 can close.

The original shared-org `ACC-07-01` remains Failed. This new Aegis-only run is a separately
authorized product test; the 16 other prepared cases remain Not run. No other product was
changed or tested during this review.

## Source, org and publication state

Before deployment, the scoped snapshot had 38 differing files and the new test class/metadata
absent. The separately authorized E47 deployment and test-only follow-up now establish final
717-file scoped parity: 537 exact, 173 normalized, seven expected environment values, zero
unexpected or missing files. The two duration XML files use the returned server representation
with unchanged formula bodies and a new live null/zero/elapsed/invalid/reopen regression.

The preserved environment values are two enabled feature flags and five event-running users;
their full configuration file hashes are unchanged. Portable defaults remain in Git. The
global CLI, namespace/Dev Hub, package creation, customer transactions and provider delivery
were unchanged. Raw retrieved metadata, private rollback snapshots and running-user values
are excluded from publication. Actual browser/customer and managed-package acceptance remain.

The unused `intermediate-package-lock.json` is preserved locally and excluded from publication.
The root lock and `tools/lint/package-lock.json` are the only installed dependency graphs.

Remaining environment and product gates include ordinary-user/browser/mobile acceptance,
live delivery and concurrency/backlog/failure/recovery cases, one selected customer pilot,
permanent namespace/Dev Hub ownership, actual namespaced build/install, upgrade/retention and
the selected commercial/security-review process. They are separate from this source merge.
