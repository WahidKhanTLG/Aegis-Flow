# Final release acceptance preparation

**Prepared:** November 9, 2026 · `1.2.0-reconciled` · API 67.0\
**State:** Local case package prepared. All 17 acceptance cases are **Not run**. No target,
identity, recipient, business recovery or metadata write is authorized by these files.

## What is ready

The [machine-readable case catalog](../release-preparation/acceptance-cases.json) covers
REL-07 through REL-14 and REL-24 with steps, finite workload caps, expected outcomes,
evidence, cleanup, prerequisites and existing source/test references. The
[target profile](../release-preparation/target-profile.example.json) deliberately leaves
execution bindings unassigned. The [evidence template](../release-preparation/acceptance-evidence.template.json)
contains no prefilled pass results. See the [preparation index](../release-preparation/README.md)
for validation commands.

Existing tests are reusable coverage references. They do not substitute for the final
release's actual org, browser, role, load, delivery or customer acceptance. The July QA
fixtures, recipients, flag states and timing assumptions are historical; do not run them
unattended or assume they remain appropriate.

## Bind the execution scope first

Before any later run, the owners must select and record:

- The exact artifact/source/manifest hash and qualified CLI/runtime/plugin identity.
- A freshly verified **nonproduction** target identity and a named release/QA administrator.
  `SyncBridge-Product` is only the historical alias of record until reverified.
- Approved ordinary test actors and their effective permission grants; do not use an
  administrator's success as an End User result.
- The customer/process or an explicitly labeled synthetic diagnostic-only scope, capture
  surfaces, context fields, recovery selection and business success conditions.
- Exact allowed cases, synthetic record markers, finite capacity/side-effect budgets,
  approved destinations, evidence storage, cleanup authority and rollback stopping rules.
- Explicit authority for each org operation. Metadata changes, creation of genuine failed
  jobs/interviews, user/access changes, email, Case automation and external actions are
  separate effects. A dry-run deployment contacts Salesforce and runs tests; it is not local work.

Capture current feature overlays, routes, subscriber users/batch sizes, schedules, cursor
state, permission assignments, customer automation and applicable retention/holds before
changing anything. Keep optional AI/connectors off unless selected and accepted. Feature
flags in this package do not suppress unrelated customer automation.

## Case map and execution order

| Task | Cases | Required result |
| --- | --- | --- |
| REL-07 | ACC-07-01 | Final source compiles and the required complete Apex release baseline passes, with exact scope/coverage recorded |
| REL-08 | ACC-08-01 through ACC-08-04 | Owned journeys, manual Help, confirmation/recovery boundaries, denial, refresh/dismissal/reload and stale-hint handling |
| REL-09 | ACC-09-01, ACC-09-02 | Agreed desktop/accessibility and available mobile/responsive surfaces accepted; platform exclusions recorded |
| REL-10 | ACC-10-01, ACC-10-02 | One intended real Email and one intended Case, masked evidence, correct audit/ownership and no replay duplicate |
| REL-11 | ACC-11-01, ACC-11-02 | Flow/async progress beyond a full page, cursor reset/late arrival, exact capture reconciliation and actual cost |
| REL-12 | ACC-12-01 | Two genuinely concurrent callers produce one durable claim and intended delivery; replay/uncertainty is safe |
| REL-13 | ACC-13-01, ACC-13-02 | Rejection, bounded transient retry, final failure and scope replay remain observable and correctly attributed |
| REL-14 | ACC-14-01, ACC-14-02 | Privacy/masking, affected-user evidence, protected lifecycle timing, long-key grouping and coverage reconcile |
| REL-24 | ACC-24-01 | Authorized nonproduction source/configuration recovery and business-data invariants pass the agreed rehearsal |

Start with compile/regression and non-delivery role/privacy/UI cases. Run selected recovery
only after its registration and business postcondition are reviewed. Run real delivery
before the concurrent-delivery case. Execute volume/fault-injection cases only within the
agreed capacity window. A failed privacy, identity, duplicate-write or source-parity gate
stops later side-effect cases until investigated.

## Fixture recipes and limits

Use a unique `AEGIS-QA-` run marker and an exact ledger of run-owned record IDs/correlations.
Select supported creation paths and review all customer triggers/Flows on those objects.
Never clean up by a broad prefix query alone. Test users are reused or provisioned only by
an authorized administrator; deleting a Salesforce User is not a cleanup strategy.

| Fixture | Prepared recipe / cap | Target-dependent work before execution |
| --- | --- | --- |
| Owned/foreign diagnostics | Two ordinary actors; one or two synthetic diagnostic/session records per selected case | Bind identities, effective access and supported capture surfaces |
| Governed recovery | One registered operation; maximum six boundary requests and one success | Approve exact writes, active handler/Flow version, custom permission and durable business postcondition |
| Email/Case | One initial request and one sequential replay per route; at most one intended delivery | Approve recipient/sender or Case owner/queue and inspect downstream automation |
| Flow backlog | 201 initial distinct failed interviews, at most one late arrival, at most three sweeps | Review a genuine failure fixture or explicitly accept an equivalent; do not insert synthetic FlowInterview rows into an org |
| Async backlog | 101 initial completed failed jobs, at most one late completion, at most three sweeps | Review daily job/capacity budget and the exact owned fixture |
| Concurrency | Two callers, two simultaneous requests, one sequential replay, one intended delivery | Prepare a real client start barrier and approved common source/route; sequential unit calls are insufficient |
| Capture failure | Three reviewed failure variants plus one valid sibling | Use existing Apex test seams first; approve any runtime injection separately; do not install a production fault flag |
| Privacy/timing | Synthetic sensitive markers only; two diagnostics and bounded protected-write/grouping comparisons | Bind roles, context allowlist, expected null/transition behavior and evidence policy |

The existing `scripts/acceptance/cross_business_rollback.apex` can be reviewed for synchronous
synthetic diagnostics after target selection. It is **not executed here**. Its savepoint does
not protect against arbitrary customer automation, Publish Immediately events, email or
external effects. Its documented flags and exact source must be reviewed before reuse.
Do not present its synchronous rollback result as committed delivery or real backlog proof.

## Commands are prepared, not executed

Before a later operator run, bind the qualified runtime/CLI entry and target in that
operator's controlled environment. Use the recorded exact paths, not a global `sf` found
by accident. The examples below are execution recipes, not authorization or completed checks.

```bash
"$AEGIS_CLI_NODE" "$AEGIS_CLI_ENTRY" project deploy start --dry-run \
  --manifest manifest/package.xml --target-org "$AEGIS_TEST_ORG" \
  --api-version 67.0 --test-level RunLocalTests --wait 60 --json

"$AEGIS_CLI_NODE" "$AEGIS_CLI_ENTRY" apex run test \
  --target-org "$AEGIS_TEST_ORG" --api-version 67.0 --test-level RunLocalTests \
  --code-coverage --wait 60 --result-format json
```

Confirm these flags against the exact candidate's help before use. No org validation,
Apex run, anonymous Apex, subscriber restart, permission assignment or delivery has been
performed by writing these commands. CLI-01's local technical gate is complete for the
[recorded restricted scope](../release-preparation/cli-release-use-review.json); the target,
run, owners and selected action authorities remain unbound. The supplied profile still
fails `--require-ready`. Production, actual deployment, bare global wrappers and CLI-backed
MCP launch are outside this qualification. Use exact command/manifest identities and
controlled plugin state. Salesforce documents the `start --dry-run` path for sandbox
validation; `project deploy validate` is outside this nonproduction review scope.

## Evidence and decision rules

Use Not run, Pass, Fail, Blocked or Excluded for actual case execution. Excluded needs a
named owner, explicit scope reason and its effect on the parent release criterion. Missing
credentials, configuration or evidence is Blocked/Not run, never Pass. An optional recovery
exclusion must be a recorded diagnostics-only scope decision.

For each executed case record the artifact/target/tool identity, UTC time, actor role,
actual inputs/caps, sanitized observation and evidence references, failure/defect details,
cleanup outcome and reviewer. Keep destination addresses, user identities and record IDs in
controlled evidence when needed; do not commit secrets, raw auth output or customer records.

Queued/Sent is not a recipient-side receipt. A known sequential replay result is not real
contention. An empty monitor page is not backlog drainage. A local compiler parse is not
Salesforce compilation. Local restored source hashes are not target-org/business rollback.
Use those distinctions when accepting the parent task.

## Exit and cleanup

Before closing a test run, reconcile actual delivery and any uncertain writes, record
remaining owned artifacts, restore only approved configuration changes and verify that
unrelated schedules, routes, subscriber users, permission grants, cursor fields and business
data were preserved. Retain required diagnostic/audit evidence and apply the agreed policy.
A required failure or unreviewed exclusion keeps the release criterion open.

Owners must review the completed evidence and the unresolved dependency/tool findings before
marking the parent tasks Done. The [rollback runbook](ROLLBACK_RUNBOOK.md) and
[operating handoff](OPERATIONS_HANDOFF.md) cover the corresponding recovery and support decisions.
