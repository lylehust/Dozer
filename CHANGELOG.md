# Changelog

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
