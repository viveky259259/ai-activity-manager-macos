class Amctl < Formula
  desc "Command-line client for AI Activity Manager"
  homepage "https://github.com/viveky259259/ai-activity-manager-macos"
  version "1.0.0"
  license "MIT"

  depends_on :macos
  depends_on macos: :ventura

  on_macos do
    on_arm do
      url "https://github.com/viveky259259/ai-activity-manager-macos/releases/download/v#{version}/amctl-arm64.tar.gz"
      sha256 "b43c427da6bddb68bb65f800b1cd4ba061115fc9a3807bf7c926586d708a2f46"
    end
    on_intel do
      url "https://github.com/viveky259259/ai-activity-manager-macos/releases/download/v#{version}/amctl-x86_64.tar.gz"
      sha256 "9db4dc8f573292f1e3689040817bb5a7e7dfd2734173906cadecbfa8b73d000c"
    end
  end

  def install
    bin.install "amctl"
  end

  test do
    assert_match "amctl", shell_output("#{bin}/amctl --help 2>&1", 0)
  end
end
