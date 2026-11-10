# Aegis Flow rollback and recovery preparation

**Prepared:** November 9, 2026. Local source/archive rehearsal is separate from an actual
nonproduction metadata/configuration/data recovery rehearsal. REL-24 closes only after
the agreed target rehearsal and owner review. No restore, deployment or deletion in an org
is authorized or performed by this document.

## Choose the recovery model

The release owner and Salesforce administrator choose among stopping the release, a forward
fix, and restoring a reviewed prior source/configuration baseline. Record the actual
compatibility and business impact before choosing. A rollback can reintroduce an older bug
or fail when new fields/data/configuration are already in use.

The source artifact prepared locally is the **current proposed source**, not a freshly
retrieved target baseline. The November 7 predeploy/deployed snapshots are historical
reference inputs, not an automatically valid rollback target for a future release.

## Required pre-change recovery record

Before any later release or rehearsal, record:

- Exact target identity/environment, action authority, owners and a stop/escalation channel.
- Reviewed new and prior source artifacts, manifests, hashes and the intended component delta.
- A fresh target source/configuration comparison, including enabled feature overlays, route
  resolution, masking/retention policy, allowed recovery registrations and active Flow versions.
- The five subscriber running identities, batch sizes and current subscription state; all
  relevant schedules/cadences and monitor cursors; role/profile/permission assignments.
- Diagnostic, delivery, retry and remediation audit/request state that must remain intact.
- Business-data protection/recovery scope and a reconciliation plan for writes/messages
  already attempted. Record backups only through approved data-handling procedures.
- The qualified runtime/CLI/plugin identity, native permissions and the exact restoration,
  validation, smoke-test and cleanup actions selected for the rehearsal.

No username, token, password, SFDX auth URL, private key or customer record is stored in the
portable preparation template. Record controlled references where identity/data evidence is
necessary. Keep configuration overlays separate from portable source defaults.

## Stop conditions

Stop and escalate if the artifact/target/configuration differs from the approved record,
required tests fail, role/privacy boundaries regress, a business write is uncertain, duplicate
delivery appears, or the recovery target would delete/overwrite unreviewed data. Do not
improvise broad metadata deletion, `git reset`, mass data cleanup or a forced resend.

## Rehearsal stages for a later authorized nonproduction run

| Stage | Operator action | Required evidence |
| --- | --- | --- |
| 1. Stabilize and capture | Stop the planned release/change path. Inventory current source/configuration, active work and uncertain external outcomes. Select any service pause with the administrator. | Fresh snapshot/hash, target identity, owned changes and approved stopping decision |
| 2. Restore the selected baseline | Validate the exact prior component/configuration delta before applying it. Restore approved overlays and access/subscriber/schedule choices deliberately. | Exact validation/deploy results and source/configuration comparison; no broad default deployment |
| 3. Verify and reconcile | Exercise capture/diagnosis/own notice/denial, inspect monitors and audits, reconcile business/external outcomes, measure recovery time and review the final state. | Rehearsal results, business-data invariants, delivery reconciliation, remaining defects and owner acceptance |

Run selected metadata validation and restoration only after separate target/action approval.
A check-only/dry-run deployment still contacts the org and runs tests; it is not an offline
step. Do not use a broad source-directory deployment when the reviewed component manifest
and configuration delta are narrower. Do not deploy historical snapshots without checking
compatibility against the present target.

The existing snapshot comparison helper is read-only against a **supplied** DX snapshot:

```bash
python3 scripts/compare_org_snapshot.py \
  --org-source /absolute/path/to/reviewed-snapshot/force-app/main/default \
  --output /absolute/path/to/controlled-evidence/parity.json
```

It writes a comparison report and does not retrieve or authenticate. A matching supplied
snapshot proves its stated semantic comparison, not current live-org parity. Any documented
configuration allowance must still match the selected target's actual approved overlay.

## Metadata and runtime details to preserve

Do not remove newly introduced fields/objects simply to reproduce an older source tree.
Review data retention, dependencies, formulas, triggers and permission references first.
Destructive metadata changes are outside the prepared local work and need an explicit plan.

Feature defaults can disable intentionally enabled tenant behavior. Restore the recorded
configuration, not assumed defaults. Preserve subscriber identities and the configured batch
of at most 200 unless the selected capacity review changes it. Subscriber refresh/replay and
schedule/cursor restoration are service operations with their own review; do not reset a
monitor cursor or resume from an arbitrary position to make counts look correct.

Record the prior enabled recovery handler/Flow version and its business postcondition.
Disabling an action does not reverse completed business changes. No source restoration
should rewrite lifecycle history or fabricate unknown timestamps.

## Business data and external effects

A source rollback cannot unsend email, remove an external ticket, retract an accepted
shipment/invoice, or reverse later user edits. Preserve the unique delivery/request keys and
audits. Reconcile destination-side state before any separately governed compensation/retry.
Pending/failed does not necessarily mean an external service received nothing.

Retain diagnostic and security evidence under the agreed policy. Any cleanup uses the exact
run-owned ID ledger plus its marker/owner checks and reviewed relationships. Do not issue
unbounded prefix-based deletion or delete a customer's historical diagnostics/audits.
Customer-specific business restoration requires the process owner's reviewed compensating
operation or data recovery procedure; no generic automatic business rollback is shipped.

## What the local rehearsal can establish

A local preparation snapshot is built from an explicit source selection, with hashes and a
manifest. Its file-level rehearsal checks archive CRC/inventory, safe paths, exact hashes,
one intentional scratch-copy mismatch and restoration of that scratch copy. It uses fresh
local work directories and never overwrites the owning checkout.

That evidence establishes archive and file restoration integrity only. It does not prove
Salesforce metadata compatibility, access/subscriber/schedule restoration, event replay,
business-data recovery, external compensation or an operational recovery-time objective.
Keep ACC-24-01 Not run until the actual target rehearsal occurs.

## Closure record

Record the selected end state, artifact and configuration hashes, completed/failed checks,
remaining data or external actions to reconcile, actual recovery time, cleaned-up/retained
artifacts and the named release/admin/customer reviewers. A local runbook or archive test
alone does not satisfy REL-24's nonproduction rehearsal condition.

See [release acceptance](RELEASE_ACCEPTANCE_PLAN.md),
[operating handoff](OPERATIONS_HANDOFF.md) and the
[tool qualification record](RELEASE_TOOLCHAIN_REVIEW.md).
