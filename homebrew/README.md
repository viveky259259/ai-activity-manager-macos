# Homebrew formulas

Source-of-truth Homebrew formulas for the standalone CLI binaries.

To publish to the user-facing tap (`viveky259259/homebrew-tap`):

1. Cut the GitHub release with notarized macOS binary tarballs:
   - `amctl-arm64.tar.gz`, `amctl-x86_64.tar.gz`
   - `activity-mcp-arm64.tar.gz`, `activity-mcp-x86_64.tar.gz`
2. Compute SHA256 for each tarball:
   ```bash
   shasum -a 256 build/release/*.tar.gz
   ```
3. Replace the `REPLACE_WITH_*_SHA256_AT_RELEASE_TIME` placeholders in
   `Formula/amctl.rb` and `Formula/activity-mcp.rb`.
4. Copy the updated `.rb` files into the tap repo and push:
   ```bash
   cp Formula/*.rb ../homebrew-tap/Formula/
   ( cd ../homebrew-tap && git commit -am "v1.0.0" && git push )
   ```
5. Verify a clean install path on a fresh machine:
   ```bash
   brew tap viveky259259/tap
   brew install amctl activity-mcp
   amctl --help
   activity-mcp --version
   ```

## Why not auto-publish?

The first release is hand-rolled to keep the supply chain auditable. Once the
flow is stable, a `brew bump-formula-pr`-style action can land in CI.
