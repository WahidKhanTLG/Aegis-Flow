#!/usr/bin/env bash
set -euo pipefail
ORG_ALIAS="${1:-aeir-target}"
python3 scripts/local_audit.py
sf project deploy start --source-dir force-app --target-org "$ORG_ALIAS" --test-level RunLocalTests --wait 60
