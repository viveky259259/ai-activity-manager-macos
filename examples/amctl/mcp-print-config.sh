#!/usr/bin/env bash
# Print the MCP host config snippet for the current install. Pipe to your
# clipboard manager and merge into the host's config file.
set -euo pipefail
amctl mcp config --host claude-desktop
