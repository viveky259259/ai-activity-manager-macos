#!/usr/bin/env bash
# Stream events as they are captured. Pipe to jq for nicer formatting.
# Press Ctrl-C to stop.
set -euo pipefail
amctl tail | jq --unbuffered '.'
