#!/usr/bin/env node
// Downloads the prebuilt activity-mcp binary for the host's CPU arch from the
// matching GitHub release and verifies its SHA256 against the manifest baked
// into this package. Runs once at `npm install` / `npx -y` time.
//
// Network failure or checksum mismatch aborts install — the package never
// silently ships an unverified or missing binary.

const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const crypto = require("crypto");
const { execSync } = require("child_process");

const pkg = require("../package.json");
const VERSION = pkg.version;
const REPO = "viveky259259/ai_activity_manager_macos";

// Expected SHA256s per arch. These MUST be filled in at release time before
// `npm publish`. The script aborts if a placeholder is encountered, so a
// forgotten checksum can't ship.
const CHECKSUMS = {
  arm64: "REPLACE_WITH_ARM64_SHA256_AT_RELEASE_TIME",
  x64: "REPLACE_WITH_X86_64_SHA256_AT_RELEASE_TIME",
};

function fail(msg) {
  console.error(`activity-mcp postinstall: ${msg}`);
  process.exit(1);
}

if (process.platform !== "darwin") {
  fail(`unsupported platform: ${process.platform}. activity-mcp only ships macOS binaries.`);
}

const arch = process.arch === "arm64" ? "arm64" : process.arch === "x64" ? "x64" : null;
if (!arch) {
  fail(`unsupported CPU arch: ${process.arch}. Need arm64 or x64.`);
}

const expectedSha = CHECKSUMS[arch];
if (!expectedSha || expectedSha.startsWith("REPLACE_")) {
  fail(`no SHA256 baked in for ${arch}. The package was published without a release checksum.`);
}

const tarballName = arch === "arm64" ? "activity-mcp-arm64.tar.gz" : "activity-mcp-x86_64.tar.gz";
const url = `https://github.com/${REPO}/releases/download/v${VERSION}/${tarballName}`;

const binDir = path.join(__dirname, "..", "bin");
fs.mkdirSync(binDir, { recursive: true });
const tarPath = path.join(binDir, tarballName);

function download(url, dest, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          file.close();
          fs.unlinkSync(dest);
          if (redirectsLeft <= 0) return reject(new Error("too many redirects"));
          return download(res.headers.location, dest, redirectsLeft - 1).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          file.close();
          fs.unlinkSync(dest);
          return reject(new Error(`HTTP ${res.statusCode} fetching ${url}`));
        }
        res.pipe(file);
        file.on("finish", () => file.close(resolve));
      })
      .on("error", (err) => {
        file.close();
        try { fs.unlinkSync(dest); } catch (_) {}
        reject(err);
      });
  });
}

function sha256(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

(async () => {
  try {
    console.log(`activity-mcp: downloading ${tarballName} v${VERSION}...`);
    await download(url, tarPath);

    const actual = sha256(tarPath);
    if (actual !== expectedSha) {
      try { fs.unlinkSync(tarPath); } catch (_) {}
      fail(`SHA256 mismatch for ${tarballName}. Expected ${expectedSha}, got ${actual}.`);
    }

    execSync(`tar -xzf ${JSON.stringify(tarPath)} -C ${JSON.stringify(binDir)}`);
    fs.unlinkSync(tarPath);

    const binary = path.join(binDir, "activity-mcp");
    fs.chmodSync(binary, 0o755);
    console.log("activity-mcp: ready.");
  } catch (err) {
    fail(err.message || String(err));
  }
})();
