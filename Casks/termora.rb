# The release workflow rewrites `version` and `sha256` on every tag.
cask "termora" do
  version "1.1.0"
  sha256 "eaf2d84dea9d1729365360d5cbd5ede715b7447334bac574f2d5945ee139aaa2"

  url "https://github.com/fballiano/termora/releases/download/v#{version}/Termora-#{version}.zip"
  name "Termora"
  desc "SSH connection manager on the Ghostty terminal engine"
  homepage "https://github.com/fballiano/termora"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Termora.app"
  binary "#{appdir}/Termora.app/Contents/MacOS/termora-cli", target: "termora"
end
