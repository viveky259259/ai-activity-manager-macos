#!/usr/bin/env bash
# Validate every JSON file under examples/rules/ against the rule schema.
set -euo pipefail
cd "$(dirname "$0")/../.."
for f in examples/rules/*.json; do
    echo "» $f"
    amctl rules validate "$f"
done
