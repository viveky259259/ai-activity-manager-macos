#!/usr/bin/env node
// Thin launcher: forwards stdio + args to the prebuilt activity-mcp binary
// downloaded into ./bin/ by scripts/postinstall.js.
//
// Exit code propagates from the child so MCP host doctor commands and shell
// pipelines see the real status. Signals (SIGTERM/SIGINT) are forwarded so
// `npx -y` cleans up under host shutdown.

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

const binary = path.join(__dirname, "activity-mcp");
if (!fs.existsSync(binary)) {
  console.error(
    "activity-mcp: prebuilt binary missing. Re-run `npm install` or check the postinstall log."
  );
  process.exit(1);
}

const child = spawn(binary, process.argv.slice(2), { stdio: "inherit" });

const forward = (signal) => () => {
  if (!child.killed) child.kill(signal);
};
process.on("SIGINT", forward("SIGINT"));
process.on("SIGTERM", forward("SIGTERM"));

child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});
