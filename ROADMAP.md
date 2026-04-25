# Roadmap

This is a living document. The most current commitments live in [GitHub
Issues](https://github.com/viveky259259/ai-activity-manager-macos/issues) and
in the milestones below.

## Now (v1.0.x patch line)

- Stabilize the v1.0 release: bug fixes from early adopters, polish.
- Snapshot regression coverage for the remaining design system components.
- Documentation: a runnable `examples/` directory with rule + MCP query samples.

## Next (v1.1)

- **Interactive notifications** — rule actions triggerable from notification
  buttons (see issue
  [#2](https://github.com/viveky259259/ai-activity-manager-macos/issues/2)).
- **Hosted DocC** for `ActivityCore` / `ActivityMCP` public surface, published
  to GitHub Pages.
- **Codecov** integration with a coverage badge in the README.
- **CodeQL** + Dependabot security updates dialed in across all SwiftPM
  manifests.

## Later (v1.2+)

- Cross-app rule chaining (one rule's outcome triggers another).
- Optional cloud sync for rule libraries (opt-in, end-to-end encrypted).
- Plugin surface for custom MCP read tools.
- Apple Silicon-only optimizations for capture buffer.

## Out of scope

These keep the project focused. They will not be considered without a strong
contributor proposal:

- Cross-platform port (Linux, Windows, iOS).
- Online dashboard / hosted analytics — privacy posture is local-only.
- AI agent that *writes code* on your behalf — separate problem.

## Contributing to the roadmap

Propose new directions by opening a GitHub Discussion or a tracking issue
labelled `roadmap`. PRs against `ROADMAP.md` itself are welcome when an item
ships or moves between buckets.
