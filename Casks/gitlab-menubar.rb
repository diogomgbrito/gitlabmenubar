cask "gitlab-menubar" do
  version "1.1.0"
  sha256 "b1e5f20ad47c0d228ebfeaa6ff111d5e740e73017891bbaf99246880f9fe05ad"

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
