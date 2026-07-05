cask "roma-just-talk" do
  version "1.95"
  sha256 "76d5891936bf659180f0a22ff46b6285a6beb4f970b95f42f0f82f3d2f3868ff"

  url "https://github.com/happyf-weallareeuropean/roma-just-talk/releases/download/v#{version}/roma.just.talk.app.zip"
  name "roma just talk"
  desc "Dictation with rolling pre-roll capture"
  homepage "https://github.com/happyf-weallareeuropean/roma-just-talk"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "voiceink"
  depends_on macos: :sonoma

  app "roma just talk.app"

  uninstall quit: "com.prakashjoshipax.VoiceInk"

  zap trash: [
    "~/Library/Application Support/com.prakashjoshipax.VoiceInk",
    "~/Library/Application Support/VoiceInk/CustomSounds",
    "~/Library/Caches/com.prakashjoshipax.VoiceInk",
    "~/Library/HTTPStorages/com.prakashjoshipax.VoiceInk",
    "~/Library/Preferences/com.prakashjoshipax.VoiceInk.plist",
    "~/Library/Saved Application State/com.prakashjoshipax.VoiceInk.savedState",
  ]

  caveats do
    unsigned_accessibility
  end
end
