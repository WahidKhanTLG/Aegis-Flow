#!/usr/bin/env bash
set -euo pipefail
ORG_ALIAS="${1:-aeir-target}"
python3 scripts/local_audit.py
sf project deploy start --source-dir force-app --target-org "$ORG_ALIAS" --dry-run --test-level RunLocalTests --wait 60
sf apex run test --class-names AEIR_CoreTest --target-org "$ORG_ALIAS" --code-coverage --result-format human --wait 60
