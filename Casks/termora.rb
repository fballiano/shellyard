# The cask of the old tap, fballiano/termora. It is frozen: the app is now
# Shellyard, and its cask is fballiano/tap/shellyard.
cask "termora" do
  version "1.2.0"
  sha256 "4d8b4ca4ad09da82d4f448c89a94b8982c047e867499f0a6c4a56136e10b4fa1"

  url "https://github.com/fballiano/termora/releases/download/v#{version}/Termora-#{version}.zip"
  name "Termora"
  desc "SSH connection manager on the Ghostty terminal engine"
  homepage "https://github.com/fballiano/termora"

  deprecate! date: "2026-11-08", because: "has moved to fballiano/tap/shellyard"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Termora.app"
  binary "#{appdir}/Termora.app/Contents/MacOS/termora-cli", target: "termora"
end
