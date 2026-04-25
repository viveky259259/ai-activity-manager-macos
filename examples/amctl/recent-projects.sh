#!/usr/bin/env bash
# Top projects you touched in the last 24h.
set -euo pipefail
amctl top --by repo --window 24h --limit 5
