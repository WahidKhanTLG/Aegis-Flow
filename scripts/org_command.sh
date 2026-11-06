#!/usr/bin/env bash
set -euo pipefail
COMMAND_NAME="${1:?Usage: scripts/org_command.sh <open|test|smoke> <authorized-org-alias>}"
ORG_ALIAS="${2:?An explicit authorized Salesforce org alias is required.}"
shift 2
case "$COMMAND_NAME" in
  open)
    sf org open --target-org "$ORG_ALIAS" "$@"
    ;;
  test)
    sf apex run test --class-names AEIR_CoreTest,AEIR_ReconciledFeaturesTest \
      --target-org "$ORG_ALIAS" --code-coverage --result-format human --wait 60 "$@"
    ;;
  smoke)
    # This is a deliberate business-data probe; never invoked by local verification.
    sf apex run --file scripts/smoke_test.apex --target-org "$ORG_ALIAS" "$@"
    ;;
  *)
    printf '%s\n' 'Supported commands: open, test, smoke.' >&2
    exit 2
    ;;
esac
