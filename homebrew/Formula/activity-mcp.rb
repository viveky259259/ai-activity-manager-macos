class ActivityMcp < Formula
  desc "MCP stdio server exposing your local activity timeline to AI assistants"
  homepage "https://github.com/viveky259259/ai-activity-manager-macos"
  version "1.0.0"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  on_macos do
    on_arm do
      url "https://github.com/viveky259259/ai-activity-manager-macos/releases/download/v#{version}/activity-mcp-arm64.tar.gz"
      sha256 "2cda29f51c12c762a63d5874225ae107bef223a2f158adeaf2c6a859543eb176"
    end
    on_intel do
      url "https://github.com/viveky259259/ai-activity-manager-macos/releases/download/v#{version}/activity-mcp-x86_64.tar.gz"
      sha256 "ad587ed295b068fedb9328bd25aa45238dc8a39256a93d1dfeac0fcde960635f"
    end
  end

  def install
    bin.install "activity-mcp"
  end

  def caveats
    <<~EOS
      activity-mcp is a stdio MCP server. To use it from an MCP host, add to your
      host config (Claude Desktop, Cursor, Zed, etc.):

        {
          "mcpServers": {
            "activity-manager": { "command": "#{opt_bin}/activity-mcp" }
          }
        }

      Without the macOS app installed, the server runs in standalone mode and
      will return empty results for capture-dependent tools (current_activity,
      recent_projects, etc.) until the daemon is also running. See
      https://github.com/viveky259259/ai-activity-manager-macos for setup.
    EOS
  end

  test do
    # The binary should at minimum print version on --version and exit 0.
    assert_match version.to_s, shell_output("#{bin}/activity-mcp --version 2>&1", 0)
  end
end
