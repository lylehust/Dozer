/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import ApplicationServices

/// One status item in the menu bar, as far as Accessibility reports it.
struct MenuBarItem {
    let bundleID: String
    let x: CGFloat
}

/// Reads menu bar items and their positions through Accessibility.
///
/// macOS 27 no longer exposes status items as windows, so this is the only way
/// to learn which item belongs to which app and where it sits relative to
/// Dozer's separators. Positions can go stale after a reflow, so callers should
/// treat a scan as a snapshot rather than a live view.
enum MenuBarItemScanner {
    /// An unresponsive app must not stall the scan.
    private static let messagingTimeout: Float = 0.4

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks the system to show the Accessibility prompt.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func scan() -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited,
                  let bundleID = app.bundleIdentifier
            else { continue }
            for element in extrasMenuBarItems(of: app.processIdentifier) {
                guard let position = position(of: element) else { continue }
                items.append(MenuBarItem(bundleID: bundleID, x: position))
            }
        }
        return items.sorted { $0.x < $1.x }
    }

    private static func extrasMenuBarItems(of pid: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXExtrasMenuBarAttribute as CFString, &barValue
        ) == .success,
            let bar = barValue, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return [] }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue
        ) == .success,
            let children = childrenValue as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func position(of element: AXUIElement) -> CGFloat? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &value
        ) == .success,
            let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point.x
    }
}
