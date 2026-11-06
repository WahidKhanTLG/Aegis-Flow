#!/usr/bin/env bash
set -euo pipefail
ORG_ALIAS="${1:?Usage: scripts/deploy.sh <authorized-org-alias>}"
python3 scripts/local_audit.py
sf project deploy start --manifest manifest/package.xml --target-org "$ORG_ALIAS" --test-level RunLocalTests --wait 60
