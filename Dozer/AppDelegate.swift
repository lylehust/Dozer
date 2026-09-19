/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import Sparkle
import Defaults
import Preferences
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    /// Sparkle's updater.
    ///
    /// Created lazily and started from `applicationDidFinishLaunching`, which is
    /// when Sparkle expects an updater to begin. Building it eagerly in `init()`
    /// would start it before the app has finished launching.
    private(set) lazy var sparkleUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Touch the controller so the updater starts now that launch is complete.
        _ = sparkleUpdaterController

        KeyboardShortcuts.onKeyUp(for: .toggleMenuItems) {
            DozerIcons.shared.toggle()
        }

        // Initalize Dozer Icons
        _ = DozerIcons.shared

        // If enabled hide menu bar icons at launch
        DozerIcons.shared.hideAtLaunch()

        _ = DozerIcons.toggleDockIcon(showIcon: false)
    }

    // Show all Dozer icons when opening Dozer from Finder etc.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DozerIcons.shared.showAll()
        return true
    }

    lazy var preferences: [PreferencePane] = [
        Dozer(),
        General()
    ]

    lazy var preferencesWindowController = PreferencesWindowController(
        preferencePanes: preferences,
        style: .toolbarItems,
        animated: true,
        hidesToolbarForSingleItem: true
    )
}
