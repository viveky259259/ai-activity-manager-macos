class Amctl < Formula
  desc "Command-line client for AI Activity Manager"
  homepage "https://github.com/viveky259259/ai_activity_manager_macos"
  version "1.0.0"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  on_macos do
    on_arm do
      url "https://github.com/viveky259259/ai_activity_manager_macos/releases/download/v#{version}/amctl-arm64.tar.gz"
      sha256 "REPLACE_WITH_ARM64_SHA256_AT_RELEASE_TIME"
    end
    on_intel do
      url "https://github.com/viveky259259/ai_activity_manager_macos/releases/download/v#{version}/amctl-x86_64.tar.gz"
      sha256 "REPLACE_WITH_X86_64_SHA256_AT_RELEASE_TIME"
    end
  end

  def install
    bin.install "amctl"
  end

  test do
    assert_match "amctl", shell_output("#{bin}/amctl --help 2>&1", 0)
  end
end
