# Aegis Flow source publication review

Reviewed November 10, 2026 against published baseline `eda715f3c05aeda9acacd2e6bf97384cf4968801`.
The user authorized review, connected-org testing and publication to main. The review branch is published in [PR #2](https://github.com/WahidKhanTLG/Aegis-Flow/pull/2).
The hosted jobs could not start because of account billing; main merge remains pending at this checkpoint. See the [product tracker](PRODUCT_PLAN_AND_TRACKER.md)
and [structured review](../release-preparation/publication-review.json) for current scope.

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
| Hosted GitHub Actions run 42811497088 | Both Node 22/24 jobs failed before executing any step: account locked due to a billing issue | Hosted/Linux acceptance blocked; REL-20 remains open |

The complete local verification was rerun on both supported Node versions after publication
of the reviewed source; both passed with the counts above. No application/CI checks were
removed or relaxed. GitHub billing must be resolved by the account owner and the hosted
workflow rerun before REL-20 can close.

The original shared-org `ACC-07-01` remains Failed. This new Aegis-only run is a separately
authorized product test; the 16 other prepared cases remain Not run. No other product was
changed or tested during this review.

## Source, org and publication state

The fresh manifest-scoped org retrieval compares 717 logical files: 536 exact, 134 normalized,
seven expected configuration differences, 38 differing files and two missing files (the new
namespace test class and its metadata). Eleven Apex classes and 15 LWC files differ. Ten
field files differ only in serializer defaults or explicit blank-formula handling; two role
permission sets differ. The source and org therefore do not yet have full scoped parity.

The seven intentional environment differences are two enabled development feature flags and
five event subscriber running users. Portable defaults remain in Git. Any separately authorized
development deployment must preserve those live values. Raw retrieved metadata, credentials,
org snapshots and local probe scripts are not publication inputs. No actual deployment,
package/version creation, global CLI update, external delivery or customer transaction was
performed by this review checkpoint.

The unused `intermediate-package-lock.json` is preserved locally and excluded from publication.
The root lock and `tools/lint/package-lock.json` are the only installed dependency graphs.

Remaining environment and product gates include ordinary-user/browser/mobile acceptance,
live delivery and concurrency/backlog/failure/recovery cases, one selected customer pilot,
permanent namespace/Dev Hub ownership, actual namespaced build/install, upgrade/retention and
the selected commercial/security-review process. They are separate from this source merge.
