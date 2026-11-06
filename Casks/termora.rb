# The release workflow rewrites `version` and `sha256` on every tag.
cask "termora" do
  version "1.1.1"
  sha256 "454629efba776c1f6acd3c1168d5e7f4f026e077602b9323997b71a9bb40db99"

  url "https://github.com/fballiano/termora/releases/download/v#{version}/Termora-#{version}.zip"
  name "Termora"
  desc "SSH connection manager on the Ghostty terminal engine"
  homepage "https://github.com/fballiano/termora"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Termora.app"
  binary "#{appdir}/Termora.app/Contents/MacOS/termora-cli", target: "termora"
end
