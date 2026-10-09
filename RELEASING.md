# Releasing

GitlabMenubar ships as an ad-hoc signed (not notarized) DMG on GitHub Releases, installed through Homebrew. This repo is its own tap: the cask is `Casks/gitlab-menubar.rb`. The cask removes the quarantine flag after install, so Gatekeeper doesn't block the app.

Install:

```bash
brew tap diogomgbrito/gitlabmenubar https://github.com/diogomgbrito/gitlabmenubar
brew install --cask gitlab-menubar
```

## Release a new version

1. Bump `MARKETING_VERSION` (both Debug and Release) in `GitlabMenubar.xcodeproj/project.pbxproj`, e.g. `1.0.1`.
2. Build the DMG:
   ```bash
   scripts/release.sh
   ```
   Prints the version, `build/GitlabMenubar-<version>.dmg` and its SHA256.
3. Update `version` and `sha256` in `Casks/gitlab-menubar.rb` with the values the script printed. Don't rebuild after this: every build changes the SHA.
4. Commit, tag and push:
   ```bash
   git commit -am "Release 1.0.1"
   git tag v1.0.1
   git push origin main v1.0.1
   ```
5. Create the GitHub release with the DMG:
   ```bash
   gh release create v1.0.1 build/GitlabMenubar-1.0.1.dmg --title "GitlabMenubar 1.0.1" --generate-notes
   ```
Users then get it with `brew upgrade --cask gitlab-menubar`.

## Notes

- The DMG file name must match the cask URL: `GitlabMenubar-<version>.dmg` under tag `v<version>`.
- Ad-hoc signing changes the code signature with every build, so macOS may ask for keychain access once after an upgrade ("Always Allow").
- The app icon source is `scripts/AppIcon.svg`. Regenerate the PNGs with `rsvg-convert -w <size> -h <size> scripts/AppIcon.svg -o GitlabMenubar/Assets.xcassets/AppIcon.appiconset/icon_<size>.png` for sizes 16, 32, 64, 128, 256, 512 and 1024.
