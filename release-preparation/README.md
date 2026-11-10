# Local acceptance and recovery preparation

This directory contains **prepared inputs**, not executed Salesforce results. All 17 cases
start Not run. The target profile is intentionally unbound and every action authority is
false. Do not fill it with credentials or treat a completed form as automatic authorization.

- [Acceptance cases](acceptance-cases.json): REL-07–REL-14 and REL-24, finite caps, actual
  source references, expected results, evidence and run-owned cleanup.
- [Target profile example](target-profile.example.json): fields the owners must select.
  The historical alias is a suggestion for review, not a verified target binding.
- [CLI qualification](cli-qualification.json): local release-use review complete; technical eligibility is true only for the recorded restricted nonproduction scope. All execution authorities remain false.
- [Local release-use decision](cli-release-use-review.json): all 14 vendor range/pin dispositions, API/limit decisions, exact artifact/runtime/plugin/manifest binding, allowed command contracts and exclusions.
- [CLI overlay manifest](cli-remediation-manifest.json): both verified overlay layers, embedded protobuf fix, explicit vendor contract/API deviations and complete archive replay. This is provenance data, not a global installer.
- [Evidence template](acceptance-evidence.template.json): one record per case, with no
  fabricated run, pass result, reviewer or cleanup outcome.
- [Acceptance plan](../docs/RELEASE_ACCEPTANCE_PLAN.md): sequencing, fixture recipes and
  environment/delivery boundaries.
- [Rollback runbook](../docs/ROLLBACK_RUNBOOK.md): source/configuration/business distinctions.
- [Operating handoff](../docs/OPERATIONS_HANDOFF.md) and
  [user quick start](../docs/USER_QUICK_START.md).

Validate the portable local package without contacting an org:

```bash
python3 scripts/validate_release_preparation.py
```

After owners prepare an actual profile in their controlled evidence directory, validate its
execution bindings separately:

```bash
python3 scripts/validate_release_preparation.py \
  --target-profile /absolute/path/to/controlled-target-profile.json --require-ready
```

The supplied example **must fail** `--require-ready`. The validator checks structure,
required selections, finite budgets, references and explicit gates; it performs no org,
credential, delivery, deployment or data operation. A passing structural check does not
verify a target identity, grant authority, resolve an advisory or constitute acceptance.

Copy the evidence template into controlled run storage only when preparing an actual run.
Record real observed outcomes, evidence, UTC time, actor role, cleanup and review. Excluded
cases require an explicit scope/owner decision and remain distinct from Pass. Secret values,
auth output, raw customer data and sensitive destination details do not belong in Git.

CLI-01's local tool, dependency, vendor-override and API review is complete. The supplied
profile references that technical decision but still has no target/run/owners or action
authority and must fail `--require-ready`. Assign and verify those execution bindings
separately. No production or actual deployment eligibility is granted by this local review.
No source commit/push, hosted CI run, org validation, business repair,
message delivery or metadata/data rollback occurred in this local preparation.
