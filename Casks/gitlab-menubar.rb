cask "gitlab-menubar" do
  version "1.2.0"
  sha256 "f083e28226043cfd751a5f967b7f0a9d2b3ae67856109594c77fa8bee7da9fe3"

  url "https://github.com/diogomgbrito/gitlabmenubar/releases/download/v#{version}/GitlabMenubar-#{version}.dmg"
  name "GitLab Menubar"
  desc "Menu bar access to GitLab projects, issues, merge requests and pipelines"
  homepage "https://github.com/diogomgbrito/gitlabmenubar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "GitlabMenubar.app"

  # App is ad-hoc signed (not notarized): clear quarantine so Gatekeeper doesn't block launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/GitlabMenubar.app"],
        writable_paths: ["{{appdir}}/GitlabMenubar.app"]
  end

  uninstall quit: "pt.dmgb.GitlabMenubar"

  zap trash: [
    "~/Library/Caches/pt.dmgb.GitlabMenubar",
    "~/Library/HTTPStorages/pt.dmgb.GitlabMenubar",
    "~/Library/Preferences/pt.dmgb.GitlabMenubar.plist",
  ]
end
