# The release workflow rewrites `version` and `sha256` on every tag.
cask "termora" do
  version "1.0.0"
  sha256 "1e1e433b5f9c9a3ed7699213ff5532a9194827b568c41711935a5aae349eb80d"

  url "https://github.com/fballiano/termora/releases/download/v#{version}/Termora-#{version}.zip"
  name "Termora"
  desc "SSH connection manager on the Ghostty terminal engine"
  homepage "https://github.com/fballiano/termora"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Termora.app"
  binary "#{appdir}/Termora.app/Contents/MacOS/termora-cli", target: "termora"

  caveats <<~EOS
    Termora is signed ad hoc, not with an Apple Developer ID, so macOS
    blocks the first launch. Open System Settings -> Privacy & Security
    and select Open Anyway, or clear the mark from a terminal:

      xattr -dr com.apple.quarantine /Applications/Termora.app
  EOS
end
