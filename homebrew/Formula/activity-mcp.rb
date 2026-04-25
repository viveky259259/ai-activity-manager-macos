class ActivityMcp < Formula
  desc "MCP stdio server exposing your local activity timeline to AI assistants"
  homepage "https://github.com/viveky259259/ai_activity_manager_macos"
  version "1.0.0"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  on_macos do
    on_arm do
      url "https://github.com/viveky259259/ai_activity_manager_macos/releases/download/v#{version}/activity-mcp-arm64.tar.gz"
      sha256 "REPLACE_WITH_ARM64_SHA256_AT_RELEASE_TIME"
    end
    on_intel do
      url "https://github.com/viveky259259/ai_activity_manager_macos/releases/download/v#{version}/activity-mcp-x86_64.tar.gz"
      sha256 "REPLACE_WITH_X86_64_SHA256_AT_RELEASE_TIME"
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
      https://github.com/viveky259259/ai_activity_manager_macos for setup.
    EOS
  end

  test do
    # The binary should at minimum print version on --version and exit 0.
    assert_match version.to_s, shell_output("#{bin}/activity-mcp --version 2>&1", 0)
  end
end
