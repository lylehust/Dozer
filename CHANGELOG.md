# Changelog

## Version 5.1.2

Fixes a regression introduced in 5.1.1: on macOS 15, 26 and anything else below
27, clicking a dot stopped hiding the icons.

5.1.1 set `NSStatusItem.isVisible = false` on the left dot from the shared
`hide()` path. Below macOS 27 that takes the item out of the menu bar layout, and
the trick that hides the neighbours depends on that item staying in the layout
with a 10,000pt length so they get pushed off screen. With the item removed,
nothing moved and nothing hid.

`isVisible` is now only touched inside the macOS 27 code path, which is gated on
`#available(macOS 27.0, *)` as well as on the private framework being present.
The macOS 14–26 path is byte-for-byte the code that shipped in 5.0.1.

## Version 5.1.1

* On macOS 27, hiding now leaves a single Dozer dot in the menu bar instead of
  two. One dot is enough to click to bring the icons back, and it matches what
  the pre-27 behaviour did by expanding the left dot away.
* Visibility is restored for every dot when showing, including after a display
  change that leaves a dot without a window.

## Version 5.1.0

Adds macOS 27 support. macOS 27 renders the whole menu bar as a single window, so
Dozer's original mechanism — inflating a status item until its neighbours are
pushed off screen — became a no-op: an oversized item is capped in width and its
neighbours no longer move. Clicking a dot hid only the dot.

Dozer now hides items through the menu bar allow-list that macOS 27 introduced:
while an assertion is active, MenuBarAgent shows only the listed system items and
bundle identifiers. Everything below macOS 27 still uses the original mechanism.

New requirements on macOS 27:
* Accessibility permission, needed to read which item belongs to which app and
  where it sits. Dozer explains this and offers to open the setting.
* The app must live in /Applications; MenuBarAgent ignores the allow-list
  elsewhere. Dozer explains this too.

Notes:
* Hiding is per app rather than per item, because the allow-list is keyed by
  bundle identifier. An app with items on both sides of a separator keeps both.
* Siri and the input-source indicator are always left out of the allow-list so
  they hide like any other icon.

## Version 5.0.1

Fixes found while reviewing 5.0.0.

Fixed:
* **Repeating-timer leak.** Every hide/show cycle started another 0.5s timer
  without invalidating the previous one. The run loop retained the orphan, so
  it kept running forever and could never be stopped. Because each tick
  enumerates every on-screen window, the cost compounded with use — the likely
  cause of the long-standing high-CPU and memory reports (upstream #211).
  Timers are now invalidated before being replaced.
* Removed three `fatalError` calls from the status-icon lookup. It is reachable
  during normal use, so a transiently missing status item crashed the app
  instead of being ignored.
* The status-icon lookup compared on-screen x positions for equality, and a
  status item with no window reported `0`. That could select or remove the
  wrong icon; selection is now by identity, and icons without a known position
  are excluded.
* `AppInfo.bundleIdentifier` force-unwrapped `Bundle.main.bundleIdentifier`.
* Sparkle's updater is now started from `applicationDidFinishLaunching`, as
  Sparkle expects, rather than during `AppDelegate.init()`.
* The hardcoded `"Dozer"` window-owner check now uses the real process name.

Internal:
* `Scripts/release.sh` derives the version from `project.yml` (the old default
  resolved to the literal string `$(MARKETING_VERSION)`, since Info.plist holds
  build-setting references), fetches the Sparkle tools it needs instead of
  assuming they exist, emits the correct `sparkle:version`, and refuses to
  release if the app's `SUPublicEDKey` does not match the signing key.
* `make release` now runs the real signing/notarization pipeline. It previously
  produced an ad-hoc signed archive while claiming to be signed.
* Removed a leftover debug `print`, an unused import, a stale `.gitignore`
  entry, and the process-lifetime cache of the menu bar height.

## Version 5.0.0

Modernization release. The minimum supported macOS is now 14.0 (Sonoma).

Fixed:
* Dozer crashed on macOS 26 "Tahoe" (`EXC_BAD_INSTRUCTION`, upstream #202).
* Menu bar status items were assumed to be exactly 22pt tall. The menu bar is
  taller on current macOS, which broke auto-hide; the range is now derived from
  the live menu bar thickness.
* Preferences could crash through recursive `UserDefaults` change handling.

Changed:
* Ships a universal binary (arm64 + x86_64) instead of an Intel-only build.
* Signed with a Developer ID certificate and notarized by Apple.
* Dependencies migrated from Carthage to Swift Package Manager.
* Sparkle 1.26 → 2.x; the update feed now points at this fork.
* `MASShortcut` replaced with `KeyboardShortcuts`.
* Launch at login now uses `SMAppService` via `LaunchAtLogin-Modern`.
* `Defaults` and `Preferences` updated to current releases.
* Removed the Objective-C bridging header and the legacy Carthage scripts.
* Bundle identifier is now `com.lylehust.Dozer`.

## Version 4.2.0
New features:
* Configure amount of seconds to hide the icons after #104. @blakedgordon
* Resize icons and padding capability added #101. @blakedgordon

Fixed:
* Fix both dozer icons from being hidden #105. @blakedgordon

Thank you @blakedgordon for the contributions🙌

## Version 4.1.0
New features:
* Hide status bar icons at launch #78. @aonez

Fixed:
* Reduce CPU usage when "Hide status bar icons after 10 seconds" is checked #78. @aonez

Thank you @aonez for the contributions🙌

## Version 4
New features:
* ”Remove”-icon. Additional icon to hide/show icons with `option+click`
* Auto-hide status bar icons #22
* ”No Icon”-mode. Hide/show only using keyboard shortcut

Other:
* Improved UI in preferences
