# Aegis Flow development deployment verification

Verified November 10, 2026. The user separately authorized actual development deployment
after the reviewed source was merged. The connected Developer Edition was freshly identified
before each deployment. The global CLI, namespace/Dev Hub and package creation were unchanged.

## Deployment and tests

| Operation | Actual result |
| --- | --- |
| DEV-ALIGN-01, `0AfgL00000dOj8nSAC` | Succeeded: 27 components, 311/311 tests from all 38 executable Aegis test classes, zero component/test errors or coverage warnings |
| Exact deployed scope | 12 Apex classes, 11 LWC bundles, two duration formula fields and two reviewed permission sets |
| Returned deployment coverage | 93.02% weighted across the ten returned executable deployed classes; none below 75%. This is a selected deployment scope, not the broader 64-class check-only percentage. |
| Test-only follow-up, `0AfgL00000dOWA0SAO` | Succeeded: one existing test class updated, 9/9 lifecycle tests pass; no production component changed by this follow-up |
| Current local Node 22.23.4 and 24.22.2 | Full verify passes: 124 LWC, 33 MCP, 12 dependency/security, eight managed-source and eight parity tests, metadata/manifest/preparation/syntax/lint gates |
| Live connector after deployment | Capabilities, own recent errors, own incidents and notifications pass; disabled mutation rejected before outbound dispatch; both enabled flags verified |

The nine focused tests include eight methods already covered by the 311-test run plus one
new formula regression; these are separate runs, not 320 distinct tests. Live connector
authentication uses the connected administrator, not ordinary-user A/B browser acceptance.
No live provider delivery or customer operation was performed.

## Final source and org comparison

The final fresh retrieve compares **717 logical release files**: **537 exact matches,
173 normalized matches and seven intended configuration differences**. There are **zero
unexpected differences, missing files or comparison failures**. This is manifest-scoped
Aegis parity, not a whole-org comparison.

The seven environment values remain byte-for-byte unchanged: the two enabled automatic
diagnosis/governed remediation flag records and five configured event subscriber records.
Those metadata types were omitted from the deployment manifest. Portable safe defaults and
unbound event-running users remain in Git for installation setup; live values remain owned
by this development environment. No feature was removed to obtain parity.

## Representation and regression corrections

The snapshot checker previously treated inactive case-sensitivity/history/trending flags
and a complete all-false object-permission row as real differences. It now recognizes only
their inactive representations. Eight regression methods preserve detection of true or
unknown grants, attributes, duplicates, other metadata changes and formula policy changes.
Salesforce documents [CustomField properties](https://developer.salesforce.com/docs/platform/api-metadata/references/meta-types/metadata-customfield.html)
and [removal of all-false permission records](https://developer.salesforce.com/docs/platform/object-reference/references/standard-objects/object-permissionset.html).

Salesforce's retrieve and direct Metadata API read both omit the explicit blank-policy node
for the two duration fields after a successful deployment. The source XML now matches that
returned representation. The formula expressions, precision, scale and explicit ISBLANK /
NULL guards are unchanged. The new deployed Apex regression verifies unknown remains null,
an actual zero stays zero, elapsed values are correct, invalid negative history stays null,
and reopening clears resolution duration while retaining first diagnosis. Formula-policy
differences are still significant to the general snapshot checker; no blanket waiver was added.

## Delivery safeguards and remaining gates

The initial exact source was main `4f3b4e0a294b569999e9b5aec3b1491791df017c`. Source updates after it consist of the
tested comparison utility/runner, one Apex test method, two XML representation alignments
and this documentation. The deployed application contracts and formula bodies are preserved.
Both submissions used normal deployment, specified tests and rollback-on-error; no ignore,
destructive, quick-deploy or test-skip flags were used. A fresh private rollback snapshot is
retained, and neither submission needed rollback. Raw org metadata and running-user values
remain outside Git.

REL-07's proof is strengthened by the actual deployment; release counts remain **nine Done,
nine Prepared, six Pending and one Awaiting billing resolution** (16 open of 25). The original
failed shared-org ACC-07-01 and 16 other unexecuted prepared cases retain their statuses.
Hosted CI remains open because GitHub billing prevented jobs from executing. Real-role/browser,
mobile/accessibility, delivery/load/concurrency/failure/privacy/recovery, pilot and actual
namespaced package/build/install acceptance remain separate gates.

See [structured verification](../release-preparation/development-deployment.json),
[product tracker](PRODUCT_PLAN_AND_TRACKER.md) and [packaging handoff](PACKAGING_DEVELOPMENT_HANDOFF.md).
