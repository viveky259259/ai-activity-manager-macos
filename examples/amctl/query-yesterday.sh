#!/usr/bin/env bash
# Natural-language query against yesterday's timeline.
# Uses whichever LLM backend is configured (Foundation Models on-device by
# default; falls back to the Anthropic key in Keychain if set).
set -euo pipefail
amctl query "What did I work on yesterday afternoon?"
