# amctl examples

`amctl` is the local CLI for Activity Manager. Same data the GUI shows, same
tools the MCP server exposes — just a terminal you can pipe into other
scripts.

## Files

| File | What it does |
|---|---|
| [`recent-projects.sh`](./recent-projects.sh) | List today's top projects ranked by time |
| [`top-apps.sh`](./top-apps.sh) | Top 10 apps by duration over the last week |
| [`query-yesterday.sh`](./query-yesterday.sh) | Ask the timeline a natural-language question |
| [`tail-events.sh`](./tail-events.sh) | Stream events live (best paired with `jq`) |
| [`rules-validate.sh`](./rules-validate.sh) | Validate every rule under `examples/rules/` against the schema |
| [`mcp-print-config.sh`](./mcp-print-config.sh) | Print the MCP host config snippet for your shell |

Run any of them from the repo root:

```bash
bash examples/amctl/recent-projects.sh
```

The scripts assume `amctl` is on your `$PATH` — install the Homebrew tap or
run `amctl install-shim` after a release build.
