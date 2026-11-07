# The release workflow rewrites `version` and `sha256` on every tag.
cask "termora" do
  version "1.1.2"
  sha256 "c10028d8fe3bddeff3ffe54a6119de476cea83db20bf49a46661afc2d7401c39"

  url "https://github.com/fballiano/termora/releases/download/v#{version}/Termora-#{version}.zip"
  name "Termora"
  desc "SSH connection manager on the Ghostty terminal engine"
  homepage "https://github.com/fballiano/termora"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Termora.app"
  binary "#{appdir}/Termora.app/Contents/MacOS/termora-cli", target: "termora"
end
