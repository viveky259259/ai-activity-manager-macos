#!/usr/bin/env bash
# Build activity-mcp and launch the official MCP Inspector against it.
# The Inspector is the de-facto smoke test: it speaks JSON-RPC, lets you call
# every tool interactively, and shows the request/response payloads.
#
# Requires: node 18+, network access (Inspector is fetched via npx).

set -euo pipefail

cd "$(dirname "$0")/.."

echo "» Building activity-mcp (release)..."
swift build --package-path Apps/activity-mcp -c release --product activity-mcp >/dev/null

BIN="$(swift build --package-path Apps/activity-mcp -c release --show-bin-path)/activity-mcp"
if [[ ! -x "$BIN" ]]; then
    echo "✗ activity-mcp binary not found at $BIN" >&2
    exit 1
fi

echo "» Launching MCP Inspector against $BIN ..."
echo "  (Ctrl-C to stop)"
exec npx -y @modelcontextprotocol/inspector "$BIN"
