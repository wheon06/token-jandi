cask "token-jandi" do
  version "0.4.0"
  sha256 "" # TODO: fill after release build

  url "https://github.com/wheon/token-jandi/releases/download/v#{version}/Token.Jandi-#{version}.zip"
  name "Token Jandi"
  desc "AI token usage heatmap for macOS menu bar"
  homepage "https://github.com/wheon/token-jandi"

  depends_on macos: ">= :sonoma"

  app "Token Jandi.app"

  zap trash: [
    "~/Library/Preferences/com.heeyeonlee.token-jandi.plist",
  ]
end
