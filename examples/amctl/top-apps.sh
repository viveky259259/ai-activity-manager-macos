#!/usr/bin/env bash
# Top 10 apps by foreground duration over the last 7 days.
set -euo pipefail
amctl top --by app --window 7d --limit 10
