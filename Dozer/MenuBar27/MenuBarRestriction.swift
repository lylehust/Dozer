/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa

@objc private protocol MenuBarAssertion: AnyObject {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(with configuration: AnyObject,
                  completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

/// Hides menu bar items on macOS 27 and later.
///
/// macOS 26 and earlier drew every status item as its own window, which is what
/// let Dozer "hide" its neighbours by inflating a status item until the others
/// were pushed off screen. macOS 27 renders the entire bar as one window, so
/// that trick is a no-op: an oversized item is simply capped in width and its
/// neighbours do not move at all.
///
/// What the system offers instead is an "assessment mode" allow-list: while an
/// assertion is active, MenuBarAgent shows only the listed system items and
/// bundle identifiers. Verified on macOS 27.2: with an assertion in place the
/// non-listed items disappear, and they reappear when it is released.
///
/// This is a private framework, so it is loaded by name at runtime rather than
/// linked. If it or its classes ever disappear, `isAvailable` becomes false and
/// Dozer degrades to the legacy path instead of crashing.
final class MenuBarRestriction {
    static let shared = MenuBarRestriction()

    /// Apple's own menu bar agents. Their items are addressed by bundle id and
    /// must stay allowed or the bar loses the clock and Control Centre.
    private static let systemBundleIDs = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.TextInputMenuAgent",
        "com.apple.Siri",
        "com.apple.Spotlight",
        "com.apple.wifi.WiFiAgent",
        "com.apple.ScreenTimeAgent",
        "com.apple.AirPlayUIAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
    ]

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationSelector =
        NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")

    private let assertionClass: NSObject.Type?
    private let configurationClass: NSObject.Type?
    private var active: MenuBarAssertion?

    /// The allow-list currently in force, or nil when nothing is restricted.
    private(set) var appliedAllowList: [String]?

    var isAvailable: Bool { assertionClass != nil && configurationClass != nil }

    private init() {
        // Every selector is checked up front: an unverified message send would
        // crash rather than degrade.
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              assertion.instancesRespond(to: #selector(MenuBarAssertion.activate(with:completionHandler:))),
              assertion.instancesRespond(to: #selector(MenuBarAssertion.invalidate)),
              configuration.instancesRespond(to: Self.configurationSelector)
        else {
            assertionClass = nil
            configurationClass = nil
            return
        }
        assertionClass = assertion
        configurationClass = configuration
    }

    /// Keeps the system agents and everything in `visibleBundleIDs` on screen and
    /// hides every other bundle's status items.
    func restrict(visibleBundleIDs: [String], completion: ((Bool) -> Void)? = nil) {
        guard let assertionClass, let configurationClass else {
            completion?(false)
            return
        }
        // The identifier space is small and Apple has added to it, so allow a
        // generous range rather than a fixed list.
        let systemItems = (0..<64).map { NSNumber(value: $0) } as NSArray
        let allowList = Set(Self.systemBundleIDs).union(visibleBundleIDs)

        guard let configuration = Self.makeConfiguration(
            configurationClass, systemItems: systemItems, bundleIDs: Array(allowList)
        ) else {
            completion?(false)
            return
        }

        let assertion = unsafeBitCast(assertionClass.init(), to: MenuBarAssertion.self)
        assertion.activate(with: configuration) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    NSLog("Dozer: menu bar restriction failed: %@", error.localizedDescription)
                    completion?(false)
                } else {
                    // The previous assertion is only dropped once the new one is
                    // in place, so nothing flashes back into view.
                    self.active?.invalidate()
                    self.active = assertion
                    self.appliedAllowList = Array(allowList)
                    completion?(true)
                }
            }
        }
    }

    func release() {
        guard let active else { return }
        active.invalidate()
        self.active = nil
        appliedAllowList = nil
    }

    private static func makeConfiguration(
        _ cls: NSObject.Type, systemItems: NSArray, bundleIDs: [String]
    ) -> AnyObject? {
        // alloc returns +1 and init consumes it, so the result is taken retained.
        let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        return allocated?
            .perform(configurationSelector, with: systemItems, with: bundleIDs as NSArray)?
            .takeRetainedValue()
    }
}
