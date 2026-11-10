# Aegis Flow — local packaging development handoff

Baseline: November 10, 2026, Metadata API 67.0. The reviewed source is ready for the packaging
team to bind to its own namespace/Dev Hub and test. No Salesforce package/version, scratch org
or namespace registration was created by this work.

## Completed locally

- Managed/unmanaged MCP routing through validated AEGIS_PACKAGE_NAMESPACE.
- Schema-derived Lightning object/field bindings, diagnosis reads and event payload fields.
- Failed custom-channel lookup leaves streaming unavailable; durable refresh remains usable.
- Nine global subscriber actions with global DTO fields and zero-argument constructors.
- Global registered retry interface/DTOs and explicit package/subscriber class resolution.
- Exact managed metadata membership, customer/development exclusions and one staging-only
  sample-field permission removal. Development source/permissions remain intact.
- Owned deepmerge security replacement and maintained ESLint runtime with qualified local
  Salesforce rule ports. Both locked audits are clean; no upstream-support claim is made.
- Full local Node 22/24 validation: 124 LWC, 33 MCP, 12 dependency/security, eight staging tests,
  metadata/manifest checks, 105 Apex grammar inputs and 14 LWC bundles / 39 compiler inputs.

The later [publication review](SOURCE_PUBLICATION_REVIEW.md) also passes an actual unmanaged
Salesforce check-only compilation: 571 components and 311/311 Aegis tests, with no errors or
coverage warnings. Four live MCP read operations pass with writes disabled. These results
do not replace namespaced build/install or ordinary-user/browser acceptance.

## Package boundary

One core package includes current product metadata and dormant optional adapters. Agentforce,
connectors, credentials, subscriber event-user assignments, schedules, destinations and customer
recovery operations remain administrator-owned setup. No business operation is enabled by staging.

The exact allowlist is packaging/managed-source-files.json. Standard Sales/Service app overrides
and utility bars, the customer Contact layout, QA flows, sample tax schema/access and sample
retry registration stay out of managed metadata. Staging removes only Product Admin's sample
Account.Tax_Code__c field permission. The development metadata is preserved. The Aegis Admin
app owns its own utility bar; customer app utility/action placement is an installation step.

## Reproduce and render local managed source

Use the complete reviewed snapshot, including tools and both lockfiles:

```bash
npm ci --ignore-scripts --no-audit --no-fund
npm ci --prefix tools/lint --ignore-scripts --no-audit --no-fund
npm run verify
npm audit --json
npm audit --prefix tools/lint --json
python3 scripts/prepare_managed_source.py --check
```

After the team selects and verifies its namespace, render a fresh local DX source directory:

```bash
python3 scripts/prepare_managed_source.py --stage /absolute/fresh/output-directory --namespace TEAM_SELECTED_NAMESPACE
```

Replace both arguments. The script rejects invalid namespaces, existing output, output inside
the source checkout, symlinks and unclassified metadata. It writes local source and hashes;
it does not run Salesforce CLI, verify namespace availability, contact an org or create a package.
Tests use synthetic namespace values only. For managed installations set the MCP bridge's
AEGIS_PACKAGE_NAMESPACE to the actual value; preserve origin and credential scope.

## Public API/configuration contract

Freeze the nine action names and global wrapper fields before the first managed release.
Subscriber Apex can implement the global AEIR_RetryHandler with the existing global
AEIR_RetryOrchestrationService.RetryRequest/RetryResult types. Recovery still enters through
the governed action/orchestrator, including its permissions, registration, budgets and audit.
Global visibility does not authorize an operation. Dynamic configuration uses exact fully
qualified describe names; standard names stay standard. Retention/action/handler/CMDT keys
remain logical identifiers. See [namespace standard](NAMESPACE_READINESS.md),
[tooling review](DEPENDENCY_SECURITY_REVIEW.md) and [MCP setup](../integrations/mcp/README.md).

## Team environment acceptance

1. Select company-owned namespace org and durable Dev Hub; verify actual IDs, namespace
   availability, ownership, settings, permissions/capacity and registry linkage.
2. Qualify the team's packaging CLI; the existing isolated validation/test CLI qualification
   did not cover package commands. Keep the existing development org out of packaging.
3. Compile and run the Aegis Apex suite in a namespaced build, including AEIR_NamespaceContractTest.
   Verify subscriber action discovery/handlers, schema/event resolution and name collisions.
4. Build/install in a clean supported subscriber org; prove least-privilege roles, onboarding,
   permissions, customer app placement, missing optional integrations and safe defaults.
5. Finish applicable UI/privacy/load/concurrency/delivery/recovery/pilot acceptance, upgrade /
   uninstall retention, hosted CI and commercial/security-review requirements.

Those environment gates have not been passed or waived by local tests. Global CLI changes,
namespace/Dev Hub setup, actual deployment, package creation and external messages
remain for separately authorized team work. Git publication is now authorized and tracked in the
[product tracker](PRODUCT_PLAN_AND_TRACKER.md).
