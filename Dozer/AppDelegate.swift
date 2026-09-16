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

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_: Notification) {
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

    var sparkleUpdaterController: SPUStandardUpdaterController {
        updaterController
    }
}
