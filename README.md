<p align="center">
	<img width="200" height="200" margin-right="100%" src="https://raw.githubusercontent.com/Mortennn/Dozer/master/Stuff/AppIcon.png">
</p>
<p align="center">Hide menu bar icons to give your Mac a cleaner look.</p>
<p align="center">
	<a href="https://github.com/lylehust/Dozer/releases/latest">
 		<img src="https://img.shields.io/badge/download-latest-brightgreen.svg" alt="download">
	<a href="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
 		<img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="platform">
	</a>
	<a href="https://img.shields.io/badge/requirements-macOS 14+-ff69b4.svg">
 		<img src="https://img.shields.io/badge/requirements-macOS 14+-lightgrey.svg" alt="systemrequirements">
	</a>
	<a href="https://opensource.org/licenses/MPL-2.0">
 		<img src="https://img.shields.io/badge/License-MPL%202.0-orange.svg" alt="license">
 	</a>
</p>
<p align="center">
	<img height="100" min-width="100" src="https://github.com/Mortennn/Dozer/raw/master/Stuff/demo.gif" alt="demo">
</p>

## About this fork

This is a maintained fork of [Mortennn/Dozer](https://github.com/Mortennn/Dozer).

Upstream has not shipped a release since 4.0.0 (2019) and its binaries are
Intel-only. On current Macs they run under Rosetta and crash on macOS 26
"Tahoe" because they were built against long-removed assumptions about the
menu bar. This fork keeps Dozer's original minimalist behaviour but updates
the project so it builds and runs natively on modern macOS.

## What's new in 5.0.0

- **Runs on macOS 26 (Tahoe) and later.** Dozer 4.x assumed every menu bar
  status item was exactly 22pt tall, which stopped being true when Apple made
  the menu bar taller, breaking auto-hide. The detection now derives its range
  from the live menu bar thickness, so it keeps working on future releases.
- **Universal binary.** One download runs natively on both Apple Silicon and
  Intel.
- **Signed and notarized.** Signed with a Developer ID certificate and
  notarized by Apple, so it opens without Gatekeeper warnings.
- **Dependencies moved from Carthage to Swift Package Manager.**
- **Sparkle 1.x → 2.x** for updates, with the feed pointing at this fork.
- **`MASShortcut` → [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts)**
  for the global toggle shortcut.
- **Modern launch-at-login** via `SMAppService` through
  [`LaunchAtLogin-Modern`](https://github.com/sindresorhus/LaunchAtLogin-Modern).
- Updated `Defaults` and `Preferences`, fixing the `Preferences` crash caused
  by recursive `UserDefaults` change handling.
- Removed the Objective-C bridging header and the legacy Carthage scripts.

## ⚙️ Install

[Download the latest release](https://github.com/lylehust/Dozer/releases/latest),
open the DMG and drag **Dozer** to your Applications folder.

Homebrew Cask still points at the deprecated upstream build and is not
recommended for this fork.

## ⚫️ Dozer Icons

There are 2 or 3, numbered from right to left:

1. this can be positioned anywhere you prefer, it is only a point of interaction
2. this and everything to its left will be hidden/shown by clicking any Dozer icon
3. (Optional) the "remove" icon and everything to its left will be hidden/shown by option-clicking any Dozer icon

## 👨‍💻 Usage

* Move the icons you want to hide until clicked to the left of the second Dozer icon
* Move the icons you want to hide until option-clicked to the left of the third Dozer icon

**N.B. hold command (`⌘`) then drag to move the menu bar icons.**

## 👇 Interactions
* Left-click one of the Dozer icons to hide/show the first group of menu bar icons
* Option-Left-click one of the Dozer icons to show the second group of menu bar icons (optional)
* Right-click one of the Dozer icons to open the settings

## 📄 Requirements
macOS 14 Sonoma or later, on Apple Silicon or Intel.

## 🛠 Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Swift
Package Manager — Carthage is no longer used.

```sh
brew bundle            # xcodegen, swiftlint, swiftformat
make setup             # generate Dozer.xcodeproj
make build             # build
make run               # build and launch
make release           # signed universal Release archive
```

Releasing also requires exporting the archive with `ExportOptions.plist`
(Developer ID) and notarizing the resulting DMG — see
`Scripts/release.sh`.

## License

[Mozilla Public License 2.0](LICENSE), unchanged from upstream.
